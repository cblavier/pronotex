defmodule PronotexWeb.CSRFProtection do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  require Logger

  @impl true
  def init(opts), do: Plug.CSRFProtection.init(opts)

  @impl true
  def call(conn, opts) do
    Plug.CSRFProtection.call(conn, opts)
  rescue
    error in Plug.CSRFProtection.InvalidCSRFTokenError ->
      # Log only presence flags, never cookies, tokens, PINs or request bodies.
      Logger.warning(
        "CSRF rejected: " <>
          "session_cookie_present=#{Map.has_key?(conn.req_cookies, "_pronotex_key")} " <>
          "session_csrf_present=#{is_binary(get_session(conn, "_csrf_token"))} " <>
          "form_csrf_present=#{is_binary(conn.body_params["_csrf_token"])}"
      )

      if conn.method == "POST" and conn.request_path == "/login" do
        Plug.CSRFProtection.delete_csrf_token()

        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("location", "/login?session_expired=1")
        |> send_resp(303, "")
        |> halt()
      else
        reraise error, __STACKTRACE__
      end
  end
end
