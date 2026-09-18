defmodule PronotexWeb.AvatarController do
  use PronotexWeb, :controller

  def show(conn, %{"index" => index}) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")

    case Pronotex.Family.avatar_data(index) do
      {:ok, type, bytes} -> conn |> put_resp_content_type(type) |> send_resp(200, bytes)
      :error -> send_resp(conn, 404, "")
    end
  end
end
