defmodule PronotexWeb.ConnCase do
  @moduledoc "Connection helpers for Phoenix tests without a database."

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint PronotexWeb.Endpoint

      use PronotexWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import PronotexWeb.ConnCase
    end
  end

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
