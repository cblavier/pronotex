defmodule PronotexWeb.Router do
  use PronotexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PronotexWeb.Layouts, :root}
    plug PronotexWeb.CSRFProtection
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug PronotexWeb.Auth
  end

  scope "/", PronotexWeb do
    pipe_through :browser
    get "/login", LoginController, :index
    post "/login", LoginController, :create
    post "/logout", LoginController, :delete
  end

  scope "/", PronotexWeb do
    pipe_through [:browser, :authenticated]

    get "/avatars/:index", AvatarController, :show

    live_session :authenticated, on_mount: [PronotexWeb.Auth] do
      live "/", DashboardLive, :index
      live "/:child", DashboardLive, :index
      live "/:child/:section", DashboardLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", PronotexWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:pronotex, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:browser, :authenticated]

      live_dashboard "/dashboard", metrics: PronotexWeb.Telemetry, on_mount: [PronotexWeb.Auth]
    end
  end
end
