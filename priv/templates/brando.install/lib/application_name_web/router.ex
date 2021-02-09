defmodule <%= application_module %>Web.Router do
  use <%= application_module %>Web, :router

  import Brando.Plug.I18n
  import Brando.Router
  import Phoenix.LiveDashboard.Router
  import Plug.BasicAuth

  @sql_sandbox Application.get_env(:<%= application_name %>, :sql_sandbox) || false

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
    # plug :put_meta, %{
    #   "google-site-verification" => "GSV"
    # }
  end

  pipeline :browser_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_extra_secure_browser_headers
  end

  pipeline :basic_httpauth do
    plug :basic_auth, username: "admin", password: "<%= :os.timestamp |> :erlang.phash2 |> Integer.to_string(32) |> String.downcase %>"
  end

  if @sql_sandbox do
    forward "/__e2e", Brando.Plug.E2ETest
  end

  scope "/__dashboard" do
    pipe_through [:browser, :basic_httpauth]
    live_dashboard "/", metrics: <%= application_module %>Web.Telemetry
  end

  admin_routes()

  scope "/coming-soon" do
    get "/", <%= application_module %>Web.LockdownController, :index
    post "/", <%= application_module %>Web.LockdownController, :post_password
  end

  scope "/api" do
    pipe_through :browser_api
  end

  scope "/" do
    pipe_through :browser
    page_routes()
  end
end
