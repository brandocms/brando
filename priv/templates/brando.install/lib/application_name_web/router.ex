defmodule <%= application_module %>Web.Router do
  use <%= application_module %>Web, :router

  import Brando.Plug.I18n
  import Brando.Images.Routes.Admin.API
  import Brando.Villain.Routes.Admin.API

  # additional optional modules

  pipeline :admin do
    plug :accepts, ~w(html json)
    plug :fetch_session
    plug :fetch_flash
    plug :put_admin_locale
    plug :put_layout, {<%= application_module %>Web.LayoutView, "admin.html"}
    plug :put_secure_browser_headers
  end

  pipeline :graphql do
    # plug RemoteIp
    plug Guardian.Plug.VerifyHeader, realm: "Bearer"
    plug Guardian.Plug.EnsureAuthenticated, handler: Brando.AuthHandler.GQLAuthHandler
    plug Guardian.Plug.LoadResource
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
  end

  pipeline :browser_session do
    plug Guardian.Plug.VerifySession
    plug Guardian.Plug.LoadResource
  end

  pipeline :auth do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug Guardian.Plug.VerifySession
    plug Guardian.Plug.LoadResource
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    # plug RemoteIp
    # plug :refresh_token
  end

  pipeline :token do
    plug Guardian.Plug.VerifyHeader, realm: "Bearer"
    plug Guardian.Plug.LoadResource
    plug Brando.Plug.SentryUserContext
  end

  pipeline :authenticated do
    plug Guardian.Plug.EnsureAuthenticated, handler: Brando.AuthHandler.APIAuthHandler
  end

  scope "/admin", as: :admin do
    pipe_through :admin

    scope "/auth" do
      post "/login", Brando.SessionController, :create
      post "/logout", Brando.SessionController, :delete
      post "/verify", Brando.SessionController, :verify
    end

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
    get "/", Brando.LockdownController, :index
    post "/", Brando.LockdownController, :post_password
  end

  scope "/auth" do
    pipe_through :auth
    get  "/login", Brando.SessionController, :login, private: %{model: Brando.User}
    post "/login", Brando.SessionController, :login, private: %{model: Brando.User}
    get  "/logout", Brando.SessionController, :logout, private: %{model: Brando.User}
  end

  scope "/" do
    pipe_through :browser
    get "/", <%= application_module %>Web.PageController, :index
  end
end
