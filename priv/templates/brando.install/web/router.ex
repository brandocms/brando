defmodule <%= application_module %>.Router do
  use <%= application_module %>.Web, :router

  alias Brando.Plug.Authenticate
  alias Brando.Plug.Lockdown

  import Brando.Plug.I18n

  import Brando.Analytics.Routes.Admin
  import Brando.Dashboard.Routes.Admin
  import Brando.Images.Routes.Admin
  import Brando.Users.Routes.Admin

  # additional optional modules
  # import Brando.Instagram.Routes.Admin
  # import Brando.News.Routes.Admin
  # import Brando.Pages.Routes.Admin

  pipeline :admin do
    plug :accepts, ~w(html json)
    plug :fetch_session
    plug :fetch_flash
    plug :put_admin_locale, <%= application_module %>.Backend.Gettext
    plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
    plug Authenticate
    plug :put_secure_browser_headers
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug Lockdown, [
      layout: {<%= application_module %>.LockdownLayoutView, "lockdown.html"},
      view: {<%= application_module %>.LockdownView, "lockdown.html"}]
    plug :put_locale, <%= application_module %>.Gettext
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :auth do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/admin", as: :admin do
    pipe_through :admin
    dashboard_routes "/"
    user_routes      "/users"
    image_routes     "/images"
    analytics_routes "/analytics"

    # additional optional routes
    # instagram_routes "/instagram"
    # page_routes      "/pages"
    # post_routes      "/news"
  end

  scope "/coming-soon" do
    get "/",  <%= application_module %>.LockdownController, :index
    post "/", <%= application_module %>.LockdownController, :post_password
  end

  scope "/auth" do
    pipe_through :auth
    get  "/login", Brando.SessionController, :login, private: %{model: Brando.User}
    post "/login", Brando.SessionController, :login, private: %{model: Brando.User}
    get  "/logout", Brando.SessionController, :logout, private: %{model: Brando.User}
  end

  scope "/" do
    pipe_through :browser
    get "/", <%= application_module %>.PageController, :index
  end
end
