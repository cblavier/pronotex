defmodule PronotexWeb.PushController do
  use PronotexWeb, :controller
  alias Pronotex.Push
  @cookie "captain_push_device"

  def config(conn, _) do
    conn = fetch_cookies(conn, signed: [@cookie])
    sub = Push.subscription(device_id(conn), get_session(conn, "auth_account"))
    json(conn, %{publicKey: Push.public_key(), enabled: not is_nil(sub)})
  end

  def create(conn, params) do
    conn = fetch_cookies(conn, signed: [@cookie])

    case Push.subscribe(get_session(conn, "auth_account"), params) do
      {:ok, sub} ->
        old = device_id(conn)
        if old != sub.id, do: Push.unsubscribe(old)

        conn
        |> put_resp_cookie(@cookie, Integer.to_string(sub.id),
          sign: true,
          http_only: true,
          secure: conn.scheme == :https or Application.get_env(:pronotex, :secure_cookies, false),
          same_site: "Lax",
          max_age: 31_536_000
        )
        |> json(%{enabled: true})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_subscription"})
    end
  end

  def delete(conn, _) do
    conn |> forget_device() |> json(%{enabled: false})
  end

  def forget_device(conn) do
    conn = fetch_cookies(conn, signed: [@cookie])
    Push.unsubscribe(device_id(conn))
    delete_resp_cookie(conn, @cookie)
  end

  defp device_id(conn) do
    case Integer.parse(conn.cookies[@cookie] || "") do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end
end
