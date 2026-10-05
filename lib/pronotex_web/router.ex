defmodule PronotexWeb.Router do
  use PronotexWeb, :router

  pipeline :browser do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PronotexWeb.Layouts, :root}
    plug PronotexWeb.CSRFProtection
    plug :put_secure_browser_headers
  end

  pipeline :authenticated do
    plug PronotexWeb.Auth
  end

  scope "/", PronotexWeb do
    pipe_through :browser
    get "/app-version", DeploymentController, :show
    get "/login", LoginController, :index
    post "/login", LoginController, :create
    post "/logout", LoginController, :delete
  end

  scope "/", PronotexWeb do
    pipe_through [:browser, :authenticated]

    get "/push/config", PushController, :config
    post "/push/subscription", PushController, :create
    delete "/push/subscription", PushController, :delete

    get "/avatars/:index", AvatarController, :show

    live_session :authenticated, on_mount: [PronotexWeb.Auth] do
      live "/:child/:section/new", MessageComposeLive, :new
      live "/:child/:section/:discussion/reply", MessageComposeLive, :reply
      live "/", DashboardLive, :index
      live "/:child", DashboardLive, :index
      live "/:child/:section", DashboardLive, :index
      live "/:child/:section/:discussion", DashboardLive, :index
    end
  end
end
