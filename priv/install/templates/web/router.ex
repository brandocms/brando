defmodule <%= application_module %>.Router do
  use <%= application_module %>.Web, :router

  import Brando.Routes.Admin.Users
  import Brando.Routes.Admin.News
  import Brando.Routes.Admin.Dashboard
  import Brando.Routes.Admin.Images
  import Brando.Routes.Admin.Pages
  import Brando.Routes.Admin.Instagram

  alias Brando.Plug.Authenticate

  pipeline :admin do
    plug :accepts, ~w(html json)
    plug :fetch_session
    plug :fetch_flash
    plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
    plug Authenticate
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug Brando.Plug.Lockdown
    plug :protect_from_forgery
  end

  pipeline :auth do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/admin", as: :admin do
    pipe_through :admin
    dashboard_routes   "/"
    user_routes        "/brukere"
    post_routes        "/nyheter"
    image_routes       "/bilder"
    instagram_routes   "/instagram"
    page_routes        "/sider"
  end

  scope "/coming-soon" do
    get "/", <%= application_module %>.LockdownController, :index
  end

  socket "/admin/ws", Brando do
    channel "system:*", SystemChannel
    channel "stats", StatsChannel
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