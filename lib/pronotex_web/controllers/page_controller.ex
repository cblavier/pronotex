defmodule PronotexWeb.PageController do
  use PronotexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
