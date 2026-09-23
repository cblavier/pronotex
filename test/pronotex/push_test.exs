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

  test "manual notification targets subscribed devices without changing observations", c do
    subscribe()
    subscribe("family", "second-device")
    subscribe("child-1", "another-profile")
    server = start_supervised!({ChildrenSession, [c.child]})
    assert {:ok, %{queued: 2}} = Push.notify_grades("family", "edgar", server: server)
    assert [first, second] = Repo.all(Delivery)
    assert first.payload == second.payload
    assert first.payload["title"] == "Edgar a eu de nouvelles notes"
    assert first.payload["url"] == "/edgar/notes"
    assert first.payload["body"] == ""
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
    assert Enum.all?(deliveries, &(&1.payload["title"] == "Edgar a eu de nouvelles notes"))
    assert Enum.all?(deliveries, &(&1.payload["url"] == "/edgar/notes?period=semester1"))
    assert deliveries |> Enum.map(& &1.payload["tag"]) |> Enum.uniq() |> length() == 1
    assert {:ok, 0} = Push.observe("family", c.context, c.child, next, @now)
    assert length(Repo.all(Delivery)) == 2
  end

  test "notification lists only new subjects, strips subdivisions and deduplicates", c do
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
    assert delivery.payload["body"] == "ESPAGNOL LV2, ANGLAIS LV1"
  end

  test "manual notification accepts subjects without reading grades", c do
    subscribe()
    server = start_supervised!({ChildrenSession, [c.child]})

    assert {:ok, %{queued: 1}} =
             Push.notify_grades("family", "Edgar",
               server: server,
               subjects: ["Maths > Algèbre", "maths > Géométrie", "Anglais", " > Vide"]
             )

    assert [delivery] = Repo.all(Delivery)
    assert delivery.payload["body"] == "Maths, Anglais"
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

    assert Enum.sort(Enum.map(Repo.all(Delivery), & &1.payload["title"])) ==
             ["Edgar a eu de nouvelles notes", "Victor a eu de nouvelles notes"]

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
