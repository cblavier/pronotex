defmodule PronotexWeb.SettingsLiveTest do
  use PronotexWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defmodule API do
    def children, do: {:ok, [%{id: "alice", name: "Alice"}]}
    def homework(_, _, _), do: {:ok, []}
    def homework_writable?(_), do: false
    def lessons(_, _, _), do: {:ok, []}
    def events(_), do: {:ok, []}
  end

  setup do
    previous = Application.get_env(:pronotex, :pronote_client)
    Application.put_env(:pronotex, :pronote_client, API)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pronotex, :pronote_client, previous),
        else: Application.delete_env(:pronotex, :pronote_client)
    end)

    :ok
  end

  test "settings require authentication" do
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), "/alice/reglages")
  end

  test "settings appear under the shared navigation without a back button", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/alice/reglages")
    render_async(view)
    assert has_element?(view, "#child-header", "Alice")
    assert has_element?(view, "#section-navigation #nav-agenda")
    assert has_element?(view, "#page-content #settings-content #app-settings")
    assert has_element?(view, "#app-settings[phx-hook=Settings]")
    assert has_element?(view, "#notifications-enabled")
    assert has_element?(view, "input[name=theme][value=system]")
    assert has_element?(view, "input[name=zoom][value=large]")
    refute has_element?(view, "a", "Retour")
    view |> element("#nav-agenda") |> render_click()
    render_async(view)
    refute has_element?(view, "#settings-content")
    view |> element("#open-settings") |> render_click()
    render_async(view)
    assert has_element?(view, "#settings-content")
    send(view.pid, :auth_expired)
    assert_redirect(view, "/login")
  end
end
