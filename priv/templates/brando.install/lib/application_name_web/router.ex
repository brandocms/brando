defmodule <%= application_module %>Web.Router do
  use <%= application_module %>Web, :router

  import Brando.Plug.I18n
  import Brando.Router
  import Phoenix.LiveDashboard.Router
  import Plug.BasicAuth
  import BrandoAdmin.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_locale
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_extra_secure_browser_headers
    plug PlugHeartbeat
    plug Brando.Plug.Identity
    plug Brando.Plug.Navigation, key: "main", as: :navigation
    plug Brando.Plug.Fragment, parent_key: "partials", as: :partials
    # plug :put_meta, %{
    #   "google-site-verification" => "GSV"
    # }
  end

  pipeline :browser_api do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # plug :put_extra_secure_browser_headers
  end

  pipeline :basic_httpauth do
    plug :basic_auth, username: "admin", password: "<%= Brando.Utils.random_string(10) %>"
  end

  scope "/__dashboard" do
    pipe_through [:browser, :basic_httpauth]
    live_dashboard "/", metrics: <%= application_module %>Web.Telemetry
  end

  admin_routes do
    # live "/projects", <%= application_module %>Web.Projects.ProjectListLive
    # live "/projects/create", <%= application_module %>Web.Projects.ProjectCreateLive
    # live "/projects/update/:entry_id", <%= application_module %>Web.Projects.ProjectUpdateLive
  end

  scope "/coming-soon", <%= application_module %>Web do
    get "/", LockdownController, :index
    post "/", LockdownController, :post_password
  end

  scope "/api", <%= application_module %>Web do
    pipe_through :browser_api
    # get "/projects/all/:page", PostController, :api_get
  end

  scope "/" do
    pipe_through :browser
    page_routes()
  end
end
