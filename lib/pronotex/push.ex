defmodule Pronotex.Push do
  @moduledoc "Durable Web Push subscriptions, grade baselines and per-device delivery queue."
  import Ecto.Query
  alias Pronotex.{Accounts, Repo}
  alias Pronotex.Push.{Baseline, Delivery, Setting, Subscription}

  def configure do
    # Keep the server identity with the database: container replacement must not
    # invalidate every installed PWA's subscription.
    {:ok, keys} =
      Repo.transaction(fn ->
        case Repo.get(Setting, "vapid") do
          nil ->
            keys = WebPush.Vapid.generate_keypair() |> Map.new(fn {k, v} -> {to_string(k), v} end)
            Repo.insert!(%Setting{key: "vapid", value: keys}).value

          setting ->
            setting.value
        end
      end)

    subject =
      Application.get_env(:pronotex, :push_subject) ||
        "https://" <>
          to_string(
            Application.get_env(:pronotex, PronotexWeb.Endpoint)[:url][:host] || "localhost"
          )

    Application.put_env(:web_push, :vapid,
      public_key: keys["public_key"],
      private_key: keys["private_key"],
      subject: subject
    )

    :ok
  end

  def public_key, do: WebPush.Vapid.public_key()

  def subscribe(account_id, params) do
    with account when not is_nil(account) <- Accounts.get(account_id),
         {:ok, sub} <- WebPush.Subscription.from_map(params),
         true <- valid_endpoint?(sub.endpoint),
         true <- valid_keys?(sub.p256dh, sub.auth) do
      Repo.transaction(fn ->
        # An endpoint belongs to a single login profile; switching profile drops
        # queued notifications for the previous one.
        if old = Repo.get_by(Subscription, endpoint: sub.endpoint), do: Repo.delete!(old)

        Repo.insert!(%Subscription{
          account_id: account.id,
          account_fingerprint: Accounts.fingerprint(account.id),
          endpoint: sub.endpoint,
          p256dh: sub.p256dh,
          auth: sub.auth
        })
      end)
    else
      _ -> {:error, :invalid_subscription}
    end
  end

  def subscription(id, account_id) when is_integer(id) do
    fingerprint = Accounts.fingerprint(account_id)

    case Repo.get(Subscription, id) do
      %Subscription{account_id: ^account_id, account_fingerprint: ^fingerprint} = sub -> sub
      _ -> nil
    end
  end

  def subscription(_, _), do: nil

  def unsubscribe(id) when is_integer(id) do
    Repo.delete_all(from(s in Subscription, where: s.id == ^id))
    :ok
  end

  def unsubscribe(_), do: :ok

  def valid_endpoint?(endpoint) when is_binary(endpoint) and byte_size(endpoint) <= 4096 do
    case URI.parse(endpoint) do
      %URI{scheme: "https", host: host, port: 443, userinfo: nil, fragment: nil}
      when is_binary(host) ->
        host == "fcm.googleapis.com" or host == "updates.push.services.mozilla.com" or
          String.ends_with?(host, ".push.services.mozilla.com") or
          host == "web.push.apple.com" or String.ends_with?(host, ".push.apple.com") or
          host == "wns2-par02p.notify.windows.com" or
          String.ends_with?(host, ".notify.windows.com")

      _ ->
        false
    end
  end

  def valid_endpoint?(_), do: false

  defp valid_keys?(public, auth) do
    with {:ok, <<4, _::binary-size(64)>> = point} <- Base.url_decode64(public, padding: false),
         {:ok, <<_::binary-size(16)>>} <- Base.url_decode64(auth, padding: false) do
      # Validate the curve point before saving client-controlled input.
      {_, private} = :crypto.generate_key(:ecdh, :prime256v1)
      :crypto.compute_key(:ecdh, point, private, :prime256v1)
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc "Observe a successful fresh read. The first observation establishes a silent baseline."
  def observe(account_id, context, child, report, now \\ DateTime.utc_now()) do
    if Accounts.get(account_id) do
      fingerprint = Accounts.fingerprint(account_id)
      # Resource IDs change on PRONOTE reconnect. Use the authenticated profile,
      # school and full child name instead; never share subscriptions across profiles.
      key =
        digest(
          {account_id, fingerprint, context.school_url, context.school_year, context.period,
           normalize(child.name), normalize(Map.get(child, :school_name) || "")}
        )

      # Counts per evaluation date + subject survive ID rotations, score/comment
      # corrections, list reordering and disappearing/reappearing evaluations.
      # Keep the largest observed count, rather than treating a reappearance as new.
      counts = Enum.frequencies_by(report.grades, &digest({&1.date, normalize(&1.subject)}))

      Repo.transaction(fn ->
        previous = Repo.get(Baseline, key)

        added =
          if previous,
            do:
              Enum.reduce(counts, 0, fn {k, n}, acc ->
                acc + max(n - Map.get(previous.counts, k, 0), 0)
              end),
            else: 0

        merged =
          Map.merge((previous && previous.counts) || %{}, counts, fn _, a, b -> max(a, b) end)

        Repo.insert!(%Baseline{key: key, counts: merged},
          on_conflict: [set: [counts: merged]],
          conflict_target: :key
        )

        if added > 0 do
          subjects =
            report.grades
            |> Enum.filter(fn grade ->
              bucket = digest({grade.date, normalize(grade.subject)})
              counts[bucket] > Map.get(previous.counts, bucket, 0)
            end)
            |> Enum.map(& &1.subject)

          enqueue_grades(account_id, fingerprint, child, context.period, now, subjects)
        end

        added
      end)
    else
      {:ok, 0}
    end
  end

  @doc """
  Manually queues a grades notification for one child of a configured profile.

      Pronotex.Push.notify_grades("family", "Edgar")
      Pronotex.Push.notify_grades("family", "Edgar", period: "semester1", subjects: ["Maths", "Anglais"])

  Resolves the child by first or full name (case-insensitive) through that
  profile's PRONOTE session. Does not fetch or modify grades, history or baselines.
  The optional `:subjects` list supplies the notification body; omitted means an empty body.
  Returns `{:ok, %{queued: count}}`, not a delivery receipt. Errors include
  `:unknown_account`, `:child_not_found`, `:ambiguous_child`, `:no_subscriptions`
  and `:pronote_unavailable`. Each explicit call creates a new notification.
  """
  def notify_grades(account_id, child_name, options \\ []) when is_binary(child_name) do
    with account when not is_nil(account) <- Accounts.get(account_id),
         {:ok, children} <- notification_children(account.id, options),
         {:ok, child} <- notification_child(children, child_name) do
      result =
        Repo.transaction(fn ->
          count =
            enqueue_grades(
              account.id,
              Accounts.fingerprint(account.id),
              child,
              Keyword.get(options, :period),
              DateTime.utc_now(),
              Keyword.get(options, :subjects, [])
            )

          if count == 0, do: Repo.rollback(:no_subscriptions)
          %{queued: count}
        end)

      if match?({:ok, _}, result), do: Pronotex.Push.Worker.deliver_now()
      result
    else
      nil -> {:error, :unknown_account}
      error -> error
    end
  end

  defp notification_children(account_id, options) do
    server =
      Keyword.get_lazy(options, :server, fn ->
        Pronotex.Pronote.Session.for_account(account_id)
      end)

    case Pronotex.Pronote.children(server) do
      {:ok, children} -> {:ok, children}
      _ -> {:error, :pronote_unavailable}
    end
  rescue
    _ in Pronotex.Pronote.Error -> {:error, :pronote_unavailable}
  catch
    :exit, _ -> {:error, :pronote_unavailable}
  end

  defp notification_child(children, name) do
    matches =
      Enum.filter(children, fn child ->
        normalize(name) in [normalize(child.name), normalize(Pronotex.Family.first_name(child))]
      end)

    case matches do
      [child] -> {:ok, child}
      [] -> {:error, :child_not_found}
      _ -> {:error, :ambiguous_child}
    end
  end

  defp enqueue_grades(account_id, fingerprint, child, period, now, subjects) do
    name = Pronotex.Family.first_name(child)

    slug =
      name
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/u, "-")
      |> URI.encode(&URI.char_unreserved?/1)

    payload = %{
      "title" => "#{name} a eu de nouvelles notes",
      "body" => subject_names(subjects),
      "url" =>
        "/#{slug}/notes" <>
          if(period, do: "?" <> URI.encode_query(%{"period" => period}), else: ""),
      "tag" => "grades-" <> Ecto.UUID.generate()
    }

    Repo.all(
      from(s in Subscription,
        where: s.account_id == ^account_id and s.account_fingerprint == ^fingerprint
      )
    )
    |> Enum.map(fn sub ->
      Repo.insert!(%Delivery{
        subscription_id: sub.id,
        payload: payload,
        due_at: now,
        expires_at: DateTime.add(now, 86400, :second)
      })
    end)
    |> length()
  end

  defp subject_names(subjects) do
    subjects
    |> Enum.map(fn subject -> subject |> String.split(">", parts: 2) |> hd() |> String.trim() end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&normalize/1)
    |> Enum.join(", ")
  end

  def deliver_pending(sender \\ &Pronotex.Push.Sender.send/2, now \\ DateTime.utc_now()) do
    Repo.delete_all(from(d in Delivery, where: d.expires_at <= ^now))
    deliveries = Repo.all(from(d in Delivery, where: d.due_at <= ^now, order_by: d.id, limit: 20))

    Enum.each(deliveries, fn delivery ->
      case Repo.get(Subscription, delivery.subscription_id) do
        nil ->
          Repo.delete!(delivery)

        sub ->
          if Accounts.get(sub.account_id) &&
               sub.account_fingerprint == Accounts.fingerprint(sub.account_id) do
            result =
              try do
                sender.(sub, delivery.payload)
              rescue
                _ -> {:error, :send_failed}
              end

            case result do
              :ok ->
                Repo.delete!(delivery)

              {:error, :gone} ->
                Repo.delete!(sub)

              _ ->
                attempts = delivery.attempts + 1

                if attempts >= 8 do
                  Repo.delete!(delivery)
                else
                  delay = min(30 * Integer.pow(2, attempts), 3600)

                  delivery
                  |> Ecto.Changeset.change(
                    attempts: attempts,
                    due_at: DateTime.add(now, delay, :second)
                  )
                  |> Repo.update!()
                end
            end
          else
            Repo.delete!(sub)
          end
      end
    end)

    :ok
  end

  defp normalize(value),
    do: value |> String.downcase() |> String.normalize(:nfc) |> String.split() |> Enum.join(" ")

  defp digest(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term)) |> Base.url_encode64(padding: false)
end
