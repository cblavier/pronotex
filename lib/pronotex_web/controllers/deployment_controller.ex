defmodule PronotexWeb.DeploymentController do
  use PronotexWeb, :controller

  def version, do: :persistent_term.get({__MODULE__, :version})

  def show(conn, _) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{version: version()})
  end
end
