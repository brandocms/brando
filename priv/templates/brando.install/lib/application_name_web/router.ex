defmodule <%= application_module %>Web.Router do
  use <%= application_module %>Web, :router

  import Brando.Plug.I18n
  import Brando.Images.Routes.Admin.API
  import Brando.Villain.Routes.Admin.API
  import Phoenix.LiveDashboard.Router

  @sql_sandbox Application.get_env(:<%= application_name %>, :sql_sandbox) || false

  # additional optional modules

  pipeline :admin do
    plug :accepts, ~w(html json)
    plug :fetch_session
    plug :fetch_flash
    plug :put_admin_locale
    plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
    plug :put_secure_browser_headers
  end

  pipeline :graphql do
    # plug RemoteIp
    plug <%= application_module %>Web.Guardian.GQLPipeline
    plug Brando.Plug.APIContext
    plug Brando.Plug.SentryUserContext
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_locale
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PlugHeartbeat
    plug Brando.Plug.Identity
    # plug :put_meta, %{
    #   "google-site-verification" => "GSV"
    # }
  end

  pipeline :basic_auth do
    plug :basic_auth, username: "admin", password: "<%= :os.timestamp |> :erlang.phash2 |> Integer.to_string(32) |> String.downcase %>"
  end

  pipeline :api do
    plug :accepts, ["json"]
    # plug RemoteIp
    # plug :refresh_token
  end

  pipeline :token do
    plug <%= application_module %>Web.Guardian.TokenPipeline
    plug Brando.Plug.SentryUserContext
  end

  pipeline :authenticated do
    plug Guardian.Plug.EnsureAuthenticated, handler: Brando.AuthHandler.APIAuthHandler
  end

  if @sql_sandbox do
    forward "/__e2e", Brando.Plug.E2ETest
  end

  scope "/__dashboard" do
    pipe_through [:browser, :basic_auth]
    live_dashboard "/"
  end

  scope "/admin", as: :admin do
    pipe_through :admin

    forward "/auth", Brando.Plug.Authentication,
          guardian_module: <%= application_module %>Web.Guardian,
          authorization_module: <%= application_module %>.Authorization

    scope "/api" do
      pipe_through [:api, :token, :authenticated]
      api_image_routes "/images"
      api_villain_routes()
    end

    # Main API scope for GraphQL
    scope "/graphql" do
      pipe_through [:graphql]
      forward "/", Absinthe.Plug, schema: <%= application_module %>.Schema
    end

    get "/*path", Brando.AdminController, :index
  end

  scope "/coming-soon" do
    get "/", <%= application_module %>Web.LockdownController, :index
    post "/", <%= application_module %>Web.LockdownController, :post_password
  end

  scope "/" do
    pipe_through :browser
    get "/", <%= application_module %>Web.PageController, :index
    get "/*path", <%= application_module %>Web.PageController, :show
  end
end
