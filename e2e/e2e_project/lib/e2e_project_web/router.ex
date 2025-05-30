defmodule E2eProjectWeb.Router do
  use BrandoWeb, :router

  import Brando.Plug.I18n
  import Brando.Router
  import Phoenix.LiveDashboard.Router
  import Plug.BasicAuth
  import BrandoAdmin.UserAuth

  @sql_sandbox Application.compile_env(:e2e_project, :sql_sandbox) || false

  pipeline :browser do
    plug :halt
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug RemoteIp
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
    plug :basic_auth, username: "admin", password: "JM6wBszRWc"
  end

  defp halt(%{request_path: "/halt"}, _opts) do
    send(:e2e_helper, :halt)
    # this ensure playwright waits until the server force stops
    Process.sleep(:infinity)
  end

  defp halt(conn, _opts), do: conn

  if @sql_sandbox do
    forward "/__e2e", Brando.Plug.E2ETest

    scope "/e2e" do
      post "/setup_fixtures/:name", E2EFixtureController, :setup
      post "/login/:email", E2EFixtureController, :login
    end
  end

  scope "/__dashboard" do
    pipe_through [:browser, :basic_httpauth]
    live_dashboard "/", metrics: E2eProjectWeb.Telemetry
  end

  admin_routes do
    live "/", E2eProjectAdmin.DashboardLive

    scope "/projects", E2eProjectAdmin.Projects do
      live "/clients", ClientListLive
      live "/clients/create", ClientFormLive, :create
      live "/clients/update/:entry_id", ClientFormLive, :update
      live "/categories", CategoryListLive
      live "/categories/create", CategoryFormLive, :create
      live "/categories/update/:entry_id", CategoryFormLive, :update
      live "/projects", ProjectListLive
      live "/projects/create", ProjectFormLive, :create
      live "/projects/update/:entry_id", ProjectFormLive, :update
    end
  end

  scope "/coming-soon", E2eProjectWeb do
    get "/", LockdownController, :index
    post "/", LockdownController, :post_password
  end

  scope "/api", E2eProjectWeb do
    pipe_through :browser_api
    # get "/projects/all/:page", PostController, :api_get
  end

  scope "/" do
    pipe_through :browser
    get "/new/redirect", E2eProjectWeb.PageController, :redirect_success
    get "/project/:slug", E2eProjectWeb.ProjectController, :detail
    page_routes()
  end
end
