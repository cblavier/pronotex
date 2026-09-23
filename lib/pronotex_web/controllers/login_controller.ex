defmodule PronotexWeb.LoginController do
  use PronotexWeb, :controller
  alias Pronotex.Auth

  def index(conn, params) do
    conn = assign(conn, :return_to, PronotexWeb.NotesDestination.validate(params["return_to"]))

    error =
      if params["session_expired"] == "1",
        do: "Le formulaire de connexion a expiré. Veuillez saisir votre code à nouveau."

    if Auth.valid?(get_session(conn)),
      do: redirect(conn, to: conn.assigns[:return_to] || "/"),
      else: page(conn, error)
  end

  def delete(conn, _) do
    if socket_id = get_session(conn, "live_socket_id") do
      PronotexWeb.Endpoint.broadcast(socket_id, "disconnect", %{})
    end

    conn
    |> PronotexWeb.PushController.forget_device()
    |> clear_session()
    |> configure_session(drop: true)
    |> put_resp_header("cache-control", "private, no-store")
    |> redirect(to: "/login")
  end

  def create(conn, params) do
    conn = assign(conn, :return_to, PronotexWeb.NotesDestination.validate(params["return_to"]))
    account = params["account"]
    remember = params["remember"] == "true"
    conn = assign(conn, :selected_account, account) |> assign(:remember, remember)

    case Auth.attempt(account, params["pin"]) do
      :ok ->
        if socket_id = get_session(conn, "live_socket_id") do
          PronotexWeb.Endpoint.broadcast(socket_id, "disconnect", %{})
        end

        Plug.CSRFProtection.delete_csrf_token()

        conn =
          conn
          |> PronotexWeb.PushController.forget_device()
          |> configure_session(renew: true)
          |> clear_session()

        conn =
          put_session(
            conn,
            "live_socket_id",
            "auth:" <> Base.url_encode64(:crypto.strong_rand_bytes(24))
          )

        conn =
          Enum.reduce(Auth.session(account, remember), conn, fn {key, value}, conn ->
            put_session(conn, key, value)
          end)

        redirect(conn, to: conn.assigns[:return_to] || "/")

      {:wait, seconds} ->
        blocked(conn, seconds)

      {:invalid, seconds} when seconds > 0 ->
        blocked(conn, seconds)

      {:invalid, _} ->
        page(conn, "Code PIN incorrect.")

      :unconfigured ->
        page(conn, "Ce compte est indisponible. Vérifiez sa configuration.")
    end
  end

  defp blocked(conn, seconds) do
    conn
    |> put_status(429)
    |> put_resp_header("retry-after", to_string(seconds))
    |> page("Veuillez attendre #{seconds} secondes avant une nouvelle tentative.")
  end

  defp page(conn, error) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> render(:index,
      page_title: "Captain Notes",
      return_to: conn.assigns[:return_to],
      configured: Auth.configured?(),
      error: error,
      accounts: Pronotex.Accounts.all(),
      selected_account: conn.assigns[:selected_account],
      remember: conn.assigns[:remember] || false
    )
  end
end
