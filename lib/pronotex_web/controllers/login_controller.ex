defmodule PronotexWeb.LoginController do
  use PronotexWeb, :controller
  alias Pronotex.Auth

  def index(conn, params) do
    error =
      if params["session_expired"] == "1",
        do: "Le formulaire de connexion a expiré. Veuillez saisir votre code à nouveau."

    if Auth.valid?(get_session(conn)), do: redirect(conn, to: "/"), else: page(conn, error)
  end

  def delete(conn, _) do
    if socket_id = get_session(conn, "live_socket_id") do
      PronotexWeb.Endpoint.broadcast(socket_id, "disconnect", %{})
    end

    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> put_resp_header("cache-control", "private, no-store")
    |> redirect(to: "/login")
  end

  def create(conn, params) do
    case Auth.attempt(params["pin"]) do
      :ok ->
        Plug.CSRFProtection.delete_csrf_token()
        conn = conn |> configure_session(renew: true) |> clear_session()

        conn =
          put_session(
            conn,
            "live_socket_id",
            "auth:" <> Base.url_encode64(:crypto.strong_rand_bytes(24))
          )

        conn =
          Enum.reduce(Auth.session(), conn, fn {key, value}, conn ->
            put_session(conn, key, value)
          end)

        redirect(conn, to: "/")

      {:wait, seconds} ->
        blocked(conn, seconds)

      {:invalid, seconds} when seconds > 0 ->
        blocked(conn, seconds)

      {:invalid, _} ->
        page(conn, "Code PIN incorrect.")

      :unconfigured ->
        if Auth.enabled?(), do: page(conn), else: redirect(conn, to: "/")
    end
  end

  defp blocked(conn, seconds) do
    conn
    |> put_status(429)
    |> put_resp_header("retry-after", to_string(seconds))
    |> page("Veuillez attendre #{seconds} secondes avant une nouvelle tentative.")
  end

  defp page(conn, error \\ nil) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> render(:index, page_title: "Connexion", configured: Auth.configured?(), error: error)
  end
end
