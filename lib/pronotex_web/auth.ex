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
      conn |> clear_session() |> Phoenix.Controller.redirect(to: "/login") |> halt()
    end
  end

  def on_mount(:default, _, session, socket) do
    if Auth.enabled?(), do: mount_authenticated(session, socket), else: {:cont, socket}
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
