defmodule Pronotex.PushTest do
  use ExUnit.Case, async: false
  alias Pronotex.{Push, Repo}
  alias Pronotex.Push.{Baseline, Delivery, Subscription}
  @now ~U[2026-09-23 10:00:00.000000Z]

  setup do
    Repo.delete_all(Delivery)
    Repo.delete_all(Subscription)
    Repo.delete_all(Baseline)

    context = %{
      school_url: "https://school.test",
      school_year: "2026-2027",
      period: "semester1",
      student_id: "rotates"
    }

    child = %{name: "TEST Edgar", first_name: "Edgar", school_name: "Collège"}
    grade = %{id: "rotates", date: ~D[2026-09-21], subject: "Maths", score: "12"}
    %{context: context, child: child, grade: grade}
  end

  defp subscribe(account \\ "family", suffix \\ "a") do
    keys = WebPush.Vapid.generate_keypair()

    {:ok, sub} =
      Push.subscribe(account, %{
        "endpoint" => "https://web.push.apple.com/#{suffix}",
        "keys" => %{
          "p256dh" => keys.public_key,
          "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        }
      })

    sub
  end

  defmodule ChildrenSession do
    use GenServer
    def start_link(children), do: GenServer.start_link(__MODULE__, children)
    def init(children), do: {:ok, children}
    def handle_call(:children, _, children), do: {:reply, {:ok, children}, children}
  end

  defp cancelled_lesson(overrides \\ %{}) do
    struct!(
      Pronotex.Pronote.Lesson,
      Map.merge(
        %{
          id: "rotates",
          subject: "Maths",
          canceled: true,
          start: ~N[2026-09-23 16:00:00],
          end: ~N[2026-09-23 17:00:00]
        },
        overrides
      )
    )
  end

  test "same-day cancellations notify every device of the matching profile", c do
    subscribe()
    subscribe("family", "second")
    subscribe("child-1", "other")
    child = %{c.child | name: "TEST Victor", first_name: "Victor"}

    assert {:ok, 1} =
             Push.observe_cancellations("family", c.context, child, [cancelled_lesson()], @now)

    assert [first, second] = Repo.all(Delivery)
    assert first.payload == second.payload
    assert first.payload["title"] == "Annulation de cours"
    assert first.payload["body"] == "Voir l'agenda de Victor"
    assert first.payload["url"] == "/victor"
    assert first.payload["tag"] =~ "cancellations-"
    assert DateTime.compare(first.expires_at, @now) == :gt
    assert DateTime.diff(first.expires_at, @now) < 86400
  end

  test "cancellations ignore past, future, ended and active lessons", c do
    subscribe()

    lessons = [
      cancelled_lesson(%{canceled: false}),
      cancelled_lesson(%{start: ~N[2026-09-22 16:00:00], end: ~N[2026-09-22 17:00:00]}),
      cancelled_lesson(%{start: ~N[2026-09-24 16:00:00], end: ~N[2026-09-24 17:00:00]}),
      cancelled_lesson(%{start: ~N[2026-09-23 06:00:00], end: ~N[2026-09-23 07:00:00]})
    ]

    assert {:ok, 0} = Push.observe_cancellations("family", c.context, c.child, lessons, @now)
    assert Repo.all(Delivery) == []

    assert {:ok, 1} =
             Push.observe_cancellations("family", c.context, c.child, [cancelled_lesson()], @now)
  end

  test "an active duplicate suppresses the cancellation without marking it seen", c do
    subscribe()
    lesson = cancelled_lesson(%{subject: "ANGLAIS LV1"})
    active = %{lesson | id: "replacement", canceled: false}

    for lessons <- [[lesson, active], [active, lesson]] do
      assert {:ok, 0} = Push.observe_cancellations("family", c.context, c.child, lessons, @now)
      assert Repo.all(Delivery) == []
    end

    assert {:ok, 1} =
             Push.observe_cancellations("family", c.context, c.child, [lesson], @now)

    assert [_] = Repo.all(Delivery)
  end

  test "partial replacements suppress cancellations but adjacent lessons do not", c do
    subscribe()
    lesson = cancelled_lesson()

    replacement =
      cancelled_lesson(%{
        subject: "Français",
        canceled: false,
        start: ~N[2026-09-23 16:30:00],
        end: ~N[2026-09-23 17:00:00]
      })

    assert {:ok, 0} =
             Push.observe_cancellations("family", c.context, c.child, [lesson, replacement], @now)

    assert Repo.all(Delivery) == []
    adjacent = cancelled_lesson(%{start: ~N[2026-09-23 17:00:00], end: ~N[2026-09-23 18:00:00]})

    assert {:ok, 1} =
             Push.observe_cancellations(
               "family",
               c.context,
               c.child,
               [lesson, replacement, adjacent],
               @now
             )

    assert [_] = Repo.all(Delivery)
  end

  test "cancellations survive ID rotation, disappearance, repeat reads and delivery", c do
    subscribe()
    lesson = cancelled_lesson()

    assert {:ok, 1} =
             Push.observe_cancellations("family", c.context, c.child, [lesson, lesson], @now)

    Push.deliver_pending(fn _, _ -> :ok end, @now)
    assert Repo.all(Delivery) == []
    assert {:ok, 0} = Push.observe_cancellations("family", c.context, c.child, [], @now)

    assert {:ok, 0} =
             Push.observe_cancellations(
               "family",
               %{c.context | period: "semester2"},
               c.child,
               [%{lesson | id: "new-id"}],
               @now
             )

    assert Repo.all(Delivery) == []
    other = cancelled_lesson(%{start: ~N[2026-09-23 17:00:00], end: ~N[2026-09-23 18:00:00]})

    assert {:ok, 1} =
             Push.observe_cancellations("family", c.context, c.child, [lesson, other], @now)

    assert [_] = Repo.all(Delivery)
  end

  test "future cancellations alert on their day and children are independent", c do
    subscribe()
    lesson = cancelled_lesson(%{start: ~N[2026-09-24 16:00:00], end: ~N[2026-09-24 17:00:00]})
    assert {:ok, 0} = Push.observe_cancellations("family", c.context, c.child, [lesson], @now)
    tomorrow = DateTime.add(@now, 86400)
    assert {:ok, 1} = Push.observe_cancellations("family", c.context, c.child, [lesson], tomorrow)
    child2 = %{c.child | name: "TEST Victor", first_name: "Victor"}
    assert {:ok, 1} = Push.observe_cancellations("family", c.context, child2, [lesson], tomorrow)
    assert length(Repo.all(Delivery)) == 2
    Push.deliver_pending(fn _, _ -> flunk("expired") end, DateTime.add(tomorrow, 86400))
    assert Repo.all(Delivery) == []
  end

  test "cancellation day and expiry use the school server's local calendar", c do
    subscribe()
    [utc | _] = :calendar.local_time_to_universal_time_dst({{2026, 9, 24}, {0, 15, 0}})
    now = utc |> NaiveDateTime.from_erl!({0, 6}) |> DateTime.from_naive!("Etc/UTC")
    lesson = cancelled_lesson(%{start: ~N[2026-09-24 08:00:00], end: ~N[2026-09-24 09:00:00]})
    assert {:ok, 1} = Push.observe_cancellations("family", c.context, c.child, [lesson], now)
    [delivery] = Repo.all(Delivery)

    local_expiry =
      delivery.expires_at
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()
      |> :calendar.universal_time_to_local_time()

    assert local_expiry == {{2026, 9, 25}, {0, 0, 0}}
  end

  test "multiple new cancellations are grouped and grade baselines remain separate", c do
    subscribe()
    lesson = cancelled_lesson()

    assert {:ok, 2} =
             Push.observe_cancellations(
               "family",
               c.context,
               c.child,
               [lesson, %{lesson | subject: "Anglais"}],
               @now
             )

    assert [_] = Repo.all(Delivery)
    assert {:ok, 0} = Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    assert {:ok, 0} = Push.observe_cancellations("missing", c.context, c.child, [lesson], @now)
    assert [_] = Repo.all(Delivery)
  end

  test "manual notification targets subscribed devices without changing observations", c do
    subscribe()
    subscribe("family", "second-device")
    subscribe("child-1", "another-profile")
    server = start_supervised!({ChildrenSession, [c.child]})
    assert {:ok, %{queued: 2}} = Push.notify_grades("family", "edgar", server: server)
    assert [first, second] = Repo.all(Delivery)
    assert first.payload == second.payload
    assert first.payload["title"] == "Nouvelle notes"
    assert first.payload["url"] == "/edgar/notes"
    assert first.payload["body"] == "Voir les notes de Edgar"
    assert Repo.all(Baseline) == []

    assert {:ok, %{queued: 2}} =
             Push.notify_grades("family", c.child.name, server: server, period: "semester1")

    assert length(Repo.all(Delivery)) == 4
    assert Enum.any?(Repo.all(Delivery), &(&1.payload["url"] == "/edgar/notes?period=semester1"))
    assert {:ok, 0} = Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    assert length(Repo.all(Delivery)) == 4
  end

  test "manual notification reports missing account, child and subscriptions", c do
    server = start_supervised!({ChildrenSession, [c.child]})
    assert {:error, :unknown_account} = Push.notify_grades("missing", "Edgar", server: server)
    assert {:error, :child_not_found} = Push.notify_grades("family", "Victor", server: server)
    assert {:error, :no_subscriptions} = Push.notify_grades("family", "Edgar", server: server)
    assert Repo.all(Delivery) == []

    assert {:error, :pronote_unavailable} =
             Push.notify_grades("family", "Edgar", server: :nonexistent_push_test_session)
  end

  test "manual notification rejects an ambiguous first name", c do
    subscribe()
    server = start_supervised!({ChildrenSession, [c.child, %{c.child | name: "OTHER Edgar"}]})
    assert {:error, :ambiguous_child} = Push.notify_grades("family", "Edgar", server: server)
    assert Repo.all(Delivery) == []
    assert {:ok, %{queued: 1}} = Push.notify_grades("family", "TEST Edgar", server: server)
  end

  test "baseline is silent, one grouped delivery per device and child", c do
    subscribe()
    subscribe("family", "b")
    subscribe("child-1", "other-profile")
    assert {:ok, 0} = Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    assert Repo.all(Delivery) == []

    next = %{
      grades: [c.grade, %{c.grade | id: "second"}, %{c.grade | id: "third", subject: "Anglais"}]
    }

    assert {:ok, 2} = Push.observe("family", c.context, c.child, next, @now)
    deliveries = Repo.all(Delivery)
    assert length(deliveries) == 2
    assert Enum.all?(deliveries, &(&1.payload["title"] == "Nouvelle notes"))
    assert Enum.all?(deliveries, &(&1.payload["url"] == "/edgar/notes?period=semester1"))
    assert deliveries |> Enum.map(& &1.payload["tag"]) |> Enum.uniq() |> length() == 1
    assert {:ok, 0} = Push.observe("family", c.context, c.child, next, @now)
    assert length(Repo.all(Delivery)) == 2
  end

  test "notification body directs to the child grades regardless of subjects", c do
    subscribe()
    Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)

    new_grades =
      Enum.map(
        [
          "ESPAGNOL LV2 > Compréhension",
          "ESPAGNOL LV2 > Expression",
          " ESPAGNOL LV2 ",
          "ANGLAIS LV1"
        ],
        fn subject -> %{c.grade | subject: subject} end
      )

    assert {:ok, 4} =
             Push.observe("family", c.context, c.child, %{grades: [c.grade | new_grades]}, @now)

    assert [delivery] = Repo.all(Delivery)
    assert delivery.payload["body"] == "Voir les notes de Edgar"
  end

  test "manual notification directs to the child grades without reading grades", c do
    subscribe()
    server = start_supervised!({ChildrenSession, [c.child]})

    assert {:ok, %{queued: 1}} =
             Push.notify_grades("family", "Edgar", server: server)

    assert [delivery] = Repo.all(Delivery)
    assert delivery.payload["body"] == "Voir les notes de Edgar"
    assert Repo.all(Baseline) == []
  end

  test "rotation, corrections, reorder and reappearance never announce existing grades", c do
    subscribe()
    Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    rotated = %{c.grade | id: "new-session", score: "18"} |> Map.put(:comment, "Correction")

    assert {:ok, 0} =
             Push.observe(
               "family",
               %{c.context | student_id: "also-rotated"},
               c.child,
               %{grades: [rotated]},
               @now
             )

    assert {:ok, 0} = Push.observe("family", c.context, c.child, %{grades: []}, @now)
    assert {:ok, 0} = Push.observe("family", c.context, c.child, %{grades: [rotated]}, @now)
    assert Repo.all(Delivery) == []
  end

  test "empty baseline then several new grades produces a single notification", c do
    subscribe()
    Push.observe("family", c.context, c.child, %{grades: []}, @now)

    assert {:ok, 2} =
             Push.observe("family", c.context, c.child, %{grades: [c.grade, c.grade]}, @now)

    assert [_] = Repo.all(Delivery)
  end

  test "children and periods have independent silent baselines", c do
    subscribe()
    child2 = %{c.child | name: "TEST Victor", first_name: "Victor"}

    for child <- [c.child, child2] do
      Push.observe("family", c.context, child, %{grades: []}, @now)
      Push.observe("family", c.context, child, %{grades: [c.grade]}, @now)
    end

    assert Enum.sort(Enum.map(Repo.all(Delivery), & &1.payload["body"])) ==
             ["Voir les notes de Edgar", "Voir les notes de Victor"]

    assert {:ok, 0} =
             Push.observe(
               "family",
               %{c.context | period: "semester2"},
               c.child,
               %{grades: [c.grade]},
               @now
             )

    assert length(Repo.all(Delivery)) == 2
  end

  test "notifications invalidate only the corresponding cache before sending" do
    alias Pronotex.Pronote.ReadCache
    sub = subscribe()

    for {notification, affected} <- [{"grades", :grades}, {"cancellation", :lessons}] do
      keys =
        for profile <- [:parent, :child], kind <- [:grades, :lessons, :menus] do
          key = {self(), {profile, {kind, "child"}}}
          {:miss, generation} = ReadCache.fetch(key)
          ReadCache.put(key, :cached, 300_000, generation)
          {kind, key, generation}
        end

      Repo.insert!(%Delivery{
        subscription_id: sub.id,
        payload: %{"kind" => notification, "tag" => notification <> "-test"},
        due_at: @now,
        expires_at: DateTime.add(@now, 86400)
      })

      Push.deliver_pending(
        fn _, _ ->
          for {kind, key, generation} <- keys do
            if kind == affected do
              assert {:miss, _} = ReadCache.fetch(key)
              ReadCache.put(key, :stale_inflight_response, 300_000, generation)
              assert {:miss, _} = ReadCache.fetch(key)
            else
              assert {:hit, :cached} = ReadCache.fetch(key)
            end
          end

          :ok
        end,
        @now
      )

      ReadCache.invalidate(self())
    end
  end

  test "delivery retries with a stable tag, success removes queue entry", c do
    subscribe()
    Push.observe("family", c.context, c.child, %{grades: []}, @now)
    Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    [original] = Repo.all(Delivery)
    Push.deliver_pending(fn _, _ -> {:error, :unavailable} end, @now)
    [retry] = Repo.all(Delivery)
    assert retry.attempts == 1
    assert retry.payload == original.payload
    assert DateTime.compare(retry.due_at, @now) == :gt
    Push.deliver_pending(fn _, _ -> flunk("too soon") end, @now)

    Push.deliver_pending(
      fn _, payload ->
        assert payload == original.payload
        :ok
      end,
      retry.due_at
    )

    assert Repo.all(Delivery) == []
  end

  test "gone subscriptions and their queued deliveries are removed", c do
    subscribe()
    Push.observe("family", c.context, c.child, %{grades: []}, @now)
    Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    Push.deliver_pending(fn _, _ -> {:error, :gone} end, @now)
    assert Repo.all(Subscription) == []
    assert Repo.all(Delivery) == []
  end

  test "expired deliveries are discarded without sending", c do
    subscribe()
    Push.observe("family", c.context, c.child, %{grades: []}, @now)
    Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    Push.deliver_pending(fn _, _ -> flunk("expired") end, DateTime.add(@now, 86400))
    assert Repo.all(Delivery) == []
  end

  test "switching profile replaces the endpoint and drops old pending deliveries", c do
    old = subscribe()
    Push.observe("family", c.context, c.child, %{grades: []}, @now)
    Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    new = subscribe("child-1")
    assert Repo.all(Delivery) == []
    assert Repo.get(Subscription, old.id) == nil
    assert Push.subscription(new.id, "family") == nil
    assert Push.subscription(new.id, "child-1") == new
  end

  test "changed profile credentials disable previous subscriptions", c do
    sub = subscribe()
    Push.observe("family", c.context, c.child, %{grades: []}, @now)
    Push.observe("family", c.context, c.child, %{grades: [c.grade]}, @now)
    sub |> Ecto.Changeset.change(account_fingerprint: <<0>>) |> Repo.update!()
    Push.deliver_pending(fn _, _ -> flunk("obsolete profile") end, @now)
    assert Repo.all(Subscription) == []
    assert Repo.all(Delivery) == []
  end

  test "VAPID public key survives reconfiguration and can sign" do
    before = Push.public_key()
    Push.configure()
    assert Push.public_key() == before
    assert WebPush.Vapid.authorization_header("https://web.push.apple.com/test") =~ "vapid t="
  end

  test "endpoints and curve points are validated before persistence" do
    for endpoint <- [
          "http://fcm.googleapis.com/x",
          "https://127.0.0.1/",
          "https://localhost/",
          "https://fcm.googleapis.com.evil.test/x",
          "https://fcm.googleapis.com@evil.test/x",
          "https://fcm.googleapis.com:444/x",
          "https://evil.test/",
          "https://web.push.apple.com/#a"
        ] do
      refute Push.valid_endpoint?(endpoint)
    end

    assert {:error, :invalid_subscription} =
             Push.subscribe("family", %{
               "endpoint" => "https://fcm.googleapis.com/x",
               "keys" => %{"p256dh" => "bad", "auth" => "bad"}
             })

    assert {:error, :invalid_subscription} = Push.subscribe("missing", %{})
    assert Repo.all(Subscription) == []
  end
end
