defmodule PronotexWeb.Auth do
  import Plug.Conn
  import Phoenix.LiveView
  alias Pronotex.Auth

  def init(opts), do: opts

  def call(conn, _) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")

    if Auth.valid?(get_session(conn)) do
      conn
    else
      # A late unauthenticated request must not overwrite the cookie belonging
      # to an open login form (or a login that has just completed in another tab).
      # Authentication is still checked on every request; successful login renews
      # the session and clears its previous contents.
      conn
      |> configure_session(ignore: true)
      |> Phoenix.Controller.redirect(
        to:
          PronotexWeb.NotesDestination.login_url(
            conn.request_path <>
              if(conn.query_string == "", do: "", else: "?" <> conn.query_string)
          )
      )
      |> halt()
    end
  end

  def avatar_allowed?(conn, path) do
    account = Pronotex.Accounts.get(get_session(conn, "auth_account"))

    if account do
      api = Application.get_env(:pronotex, :pronote_client, Pronotex.Pronote)

      result =
        if api == Pronotex.Pronote do
          Pronotex.Pronote.children(Pronotex.Pronote.Session.for_account(account.id))
        else
          api.children()
        end

      case result do
        {:ok, children} -> Enum.any?(children, &(Pronotex.Family.avatar(&1) == path))
        _ -> false
      end
    else
      false
    end
  end

  def on_mount(:default, _, session, socket) do
    mount_authenticated(session, socket)
  end

  defp mount_authenticated(session, socket) do
    if Auth.valid?(session) do
      if connected?(socket) do
        Process.send_after(
          self(),
          :auth_expired,
          max(Auth.expires_at(session) - Auth.now(), 0) * 1000
        )
      end

      socket =
        socket
        |> Phoenix.Component.assign(:account, Pronotex.Accounts.get(session["auth_account"]))
        |> attach_hook(:auth_event, :handle_event, fn _, _, socket -> check(session, socket) end)
        |> attach_hook(:auth_params, :handle_params, fn _, _, socket -> check(session, socket) end)
        |> attach_hook(:auth_info, :handle_info, fn
          :auth_expired, socket -> {:halt, redirect(socket, to: "/login")}
          _, socket -> check(session, socket)
        end)

      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  defp check(session, socket) do
    if Auth.valid?(session), do: {:cont, socket}, else: {:halt, redirect(socket, to: "/login")}
  end
end
