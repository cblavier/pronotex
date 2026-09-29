defmodule PronotexWeb.MessageComposeLiveTest do
  use PronotexWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defmodule API do
    def sender_name, do: {:ok, "Christian Blavier"}

    def children,
      do:
        {:ok,
         [
           %{id: "a", name: "Alice", school_name: "Collège Jules Ferry", class_name: "5B"},
           %{id: "b", name: "Marius", class_name: "3A"}
         ]}

    def homework(_, _, _), do: {:ok, []}
    def homework_writable?(_), do: false
    def discussions(_), do: {:ok, []}
    def parent_discussions, do: {:ok, [%{unread: 2}]}

    def message_recipients do
      case Application.get_env(:pronotex, :composer_mode) do
        :load_error ->
          {:error, :offline}

        _ ->
          {:ok,
           [
             %{
               id: "3:teacher",
               name: "Mme Élise Martin",
               type: "Professeur",
               subjects: ["Mathématiques"]
             },
             %{id: "5:parent", name: "M. Dupont", type: "Responsable", subjects: []},
             %{id: "34:staff", name: "Vie scolaire", type: "Personnel", subjects: []}
           ]}
      end
    end

    def send_message(ids, subject, content) do
      send(Application.fetch_env!(:pronotex, :composer_pid), {:sent, ids, subject, content})

      case Application.get_env(:pronotex, :composer_mode) do
        :simulated ->
          {:ok, :simulated}

        :send_error ->
          {:error, :offline}

        :slow ->
          send(Application.fetch_env!(:pronotex, :composer_pid), {:pending, self()})

          receive do
            :finish -> {:ok, :sent}
          end

        _ ->
          {:ok, :sent}
      end
    end
  end

  setup do
    keys = [
      :pronote_client,
      :composer_mode,
      :composer_pid,
      :dashboard_test_mode,
      :dashboard_test_pid
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:pronotex, &1)})
    Application.put_env(:pronotex, :pronote_client, API)
    Application.put_env(:pronotex, :composer_pid, self())
    Application.delete_env(:pronotex, :composer_mode)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:pronotex, key, value)
        {key, :error} -> Application.delete_env(:pronotex, key)
      end)
    end)

    {:ok, conn: build_conn() |> Plug.Test.init_test_session(Pronotex.Auth.session("parent-1"))}
  end

  defp compose(conn) do
    {:ok, view, _} = live(conn, "/alice/parent-messages/new")
    render_async(view)
    view
  end

  defp draft(view) do
    render_click(view, "add-recipient", %{"id" => "3:teacher"})

    view
    |> form("#message-form", draft: %{subject: "Rendez-vous", content: "Bonjour !"})
    |> render_change()
  end

  test "composer includes the shared header and protects navigation", %{conn: conn} do
    view = compose(conn)
    render_async(view)
    assert has_element?(view, "#message-sender[disabled][value='Christian Blavier']")
    refute has_element?(view, "#compose-title")
    assert has_element?(view, "#child-name", "Alice")
    assert has_element?(view, "#school-name", "Collège Jules Ferry")
    assert has_element?(view, "#school-name", "5B")
    assert has_element?(view, "#section-navigation #nav-notes")
    assert has_element?(view, "#parent-messages-unread-count", "2")
    draft(view)
    view |> element("#nav-notes") |> render_click()
    assert has_element?(view, "[role=alertdialog]", "Votre saisie sera perdue")
    render_click(view, "dismiss-confirmation")
    assert has_element?(view, "#message-subject[value='Rendez-vous']")
    view |> element("#nav-notes") |> render_click()
    render_click(view, "confirm-cancel")
    assert_redirect(view, "/alice/notes")
  end

  test "empty composer can switch children and open settings", %{conn: conn} do
    view = compose(conn)
    render_click(view, "select-child", %{"id" => "b"})
    assert_redirect(view, "/marius/parent-messages")
    view = compose(conn)
    render_click(view, "section", %{"section" => "settings"})
    assert_redirect(view, "/alice/reglages")
  end

  test "logout also confirms abandoning a draft", %{conn: conn} do
    view = compose(conn)
    draft(view)
    render_submit(view, "request-logout", %{})
    assert has_element?(view, "[role=alertdialog]", "Votre saisie sera perdue")
    render_click(view, "confirm-cancel")
    assert_push_event(view, "compose-logout", %{})
  end

  test "only the logged-in account's mailbox permits composing", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/alice/messages/new")
    child = build_conn() |> Plug.Test.init_test_session(Pronotex.Auth.session("child-1"))
    assert {:error, {:redirect, %{to: "/"}}} = live(child, "/alice/parent-messages/new")
    assert {:ok, view, _} = live(child, "/alice/messages/new")
    render_async(view)
    assert has_element?(view, "#message-form")
    family = build_conn() |> Plug.Test.init_test_session(Pronotex.Auth.session("family"))
    assert {:error, {:redirect, %{to: "/"}}} = live(family, "/alice/messages/new")
  end

  test "autocomplete matches accents and subjects and preserves distinct types", %{conn: conn} do
    view = compose(conn)
    render_click(view, "show-recipients")
    assert has_element?(view, "[role=option]", "Responsable")
    assert has_element?(view, "[role=option]", "Personnel")

    view
    |> form("#message-form", draft: %{query: "elise"})
    |> render_change(%{"_target" => ["draft", "query"]})

    assert has_element?(view, "[role=option]", "Mme Élise Martin")
    refute has_element?(view, "[role=option]", "Dupont")

    view
    |> form("#message-form", draft: %{query: "mathematiques"})
    |> render_change(%{"_target" => ["draft", "query"]})

    assert has_element?(view, "[role=option]", "Mme Élise Martin")
    render_click(view, "add-recipient", %{"id" => "3:teacher"})
    refute has_element?(view, "#recipient-options")
    assert has_element?(view, "#recipient-query[aria-expanded=false]")
    render_click(view, "show-recipients")
    assert has_element?(view, "#recipient-options")
    render_click(view, "add-recipient", %{"id" => "3:teacher"})
    render_click(view, "add-recipient", %{"id" => "foreign"})

    assert length(
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find(".selected-recipient")
           ) == 1

    assert has_element?(view, "#selected-recipients", "Mathématiques")
    refute has_element?(view, "#selected-recipients", "Alice")
    refute has_element?(view, "#selected-recipients", "Marius")
    render_click(view, "add-recipient", %{"id" => "34:staff"})
    assert has_element?(view, "#selected-recipients", "Vie scolaire")
    render_click(view, "remove-recipient", %{"id" => "3:teacher"})
    refute has_element?(view, "#selected-recipients", "Martin")
  end

  test "send requires explicit confirmation and cannot be repeated", %{conn: conn} do
    view = compose(conn)
    draft(view)
    render_click(view, "confirm-send")
    refute_received {:sent, _, _, _}
    view |> form("#message-form") |> render_submit()
    assert has_element?(view, "[role=alertdialog]", "Envoyer ce message")
    refute_received {:sent, _, _, _}
    render_click(view, "confirm-send")
    assert_receive {_, {:redirect, _, redirect}}
    result = {:error, {:live_redirect, redirect}}
    assert_received {:sent, ["3:teacher"], "Rendez-vous", "Bonjour !"}
    Application.put_env(:pronotex, :pronote_client, PronotexWeb.DashboardLiveTest.API)
    Application.put_env(:pronotex, :dashboard_test_mode, :messages)
    Application.put_env(:pronotex, :dashboard_test_pid, self())
    {:ok, inbox, _} = follow_redirect(result, conn, "/alice/parent-messages")
    render_async(inbox)
    assert has_element?(inbox, "#messages-content > #message-sent", "Votre message a été envoyé.")
    refute has_element?(inbox, "#message-composer")
    inbox |> element("#message-sent button") |> render_click()
    refute has_element?(inbox, "#message-sent")
    refute_received {:sent, _, _, _}
  end

  test "simulated sends return to the list with an explicit simulation notice", %{conn: conn} do
    Application.put_env(:pronotex, :composer_mode, :simulated)
    view = compose(conn)
    draft(view)
    view |> form("#message-form") |> render_submit()
    render_click(view, "confirm-send")
    flash = assert_redirect(view, "/alice/parent-messages")
    assert flash["message_sent"] =~ "Envoi simulé"
    assert flash["message_sent"] =~ "aucun message"
    refute flash["message_sent"] =~ "Votre message a été envoyé"
  end

  test "cancel and return ask before losing a draft", %{conn: conn} do
    view = compose(conn)
    draft(view)
    view |> element(".lesson-back-link") |> render_click()
    assert has_element?(view, "[role=alertdialog]", "Votre saisie sera perdue")
    render_click(view, "dismiss-confirmation")
    assert has_element?(view, "#message-subject[value='Rendez-vous']")
    view |> element("#cancel-message") |> render_click()
    render_click(view, "confirm-cancel")
    assert_redirect(view, "/alice/parent-messages")
  end

  test "empty cancel goes back directly", %{conn: conn} do
    view = compose(conn)
    view |> element("#cancel-message") |> render_click()
    assert_redirect(view, "/alice/parent-messages")
  end

  test "empty or oversized content never reaches the send confirmation", %{conn: conn} do
    view = compose(conn)
    render_click(view, "add-recipient", %{"id" => "3:teacher"})

    for fields <- [
          %{"subject" => " ", "content" => "Bonjour"},
          %{"subject" => "Objet", "content" => " "},
          %{"subject" => String.duplicate("x", 201), "content" => "Bonjour"}
        ] do
      render_submit(view, "review-send", %{"draft" => fields})
      assert has_element?(view, "#message-form-error")
      refute has_element?(view, "[role=alertdialog]")
    end

    refute_received {:sent, _, _, _}
  end

  test "a pending send blocks duplicate submissions and cancellation", %{conn: conn} do
    Application.put_env(:pronotex, :composer_mode, :slow)
    view = compose(conn)
    draft(view)
    view |> form("#message-form") |> render_submit()
    render_click(view, "confirm-send")
    assert_receive {:pending, sender}
    assert_receive {:sent, _, _, _}
    render_click(view, "confirm-send")
    render_click(view, "cancel")
    refute has_element?(view, "[role=alertdialog]")
    assert has_element?(view, "fieldset[disabled]")
    refute_received {:sent, _, _, _}
    send(sender, :finish)
    assert_redirect(view, "/alice/parent-messages")
  end

  test "load failure can be retried without losing text", %{conn: conn} do
    Application.put_env(:pronotex, :composer_mode, :load_error)
    view = compose(conn)
    assert has_element?(view, "[role=alert]", "Impossible")
    Application.delete_env(:pronotex, :composer_mode)
    render_click(view, "refresh")
    render_async(view)
    refute has_element?(view, "#message-composer [role=alert]")
  end

  test "send failure preserves draft and requires checking before another attempt", %{conn: conn} do
    Application.put_env(:pronotex, :composer_mode, :send_error)
    view = compose(conn)
    draft(view)
    view |> form("#message-form") |> render_submit()
    render_click(view, "confirm-send")
    render_async(view)
    assert_received {:sent, _, _, _}
    assert has_element?(view, "#message-subject[value='Rendez-vous']")
    assert has_element?(view, "#message-content", "Bonjour !")
    assert has_element?(view, "#send-message[disabled]")
    view |> form("#message-form") |> render_submit()
    render_click(view, "confirm-send")
    refute_received {:sent, _, _, _}
    render_click(view, "verified-not-sent")
    render_async(view)
    refute has_element?(view, "#send-message[disabled]")
  end

  test "unknown child cannot load recipients", %{conn: conn} do
    {:ok, view, _} = live(conn, "/unknown/parent-messages/new")
    render_async(view)
    assert has_element?(view, "[role=alert]", "Impossible")
    assert has_element?(view, "#send-message[disabled]")
  end
end
