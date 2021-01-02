defmodule Brando.Router do
  defmacro page_routes do
    quote do
      get "/robots.txt", Brando.SEOController, :robots
      get "/", Brando.web_module(PageController), :index
      get "/*path", Brando.web_module(PageController), :show
    end
  end

  defmacro admin_routes(path \\ "/admin") do
    quote do
      upload_ctrl = Brando.Admin.API.Images.UploadController
      villain_ctrl = Brando.Admin.API.Villain.VillainController

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
        plug Brando.web_module(Guardian.GQLPipeline)
        plug Brando.Plug.APIContext
        plug Brando.Plug.SentryUserContext
      end

      pipeline :api do
        plug :accepts, ["json"]
        # plug RemoteIp
        # plug :refresh_token
      end

      pipeline :token do
        plug Brando.web_module(Guardian.TokenPipeline)
        plug Brando.Plug.SentryUserContext
      end

      pipeline :authenticated do
        plug Guardian.Plug.EnsureAuthenticated, handler: Brando.AuthHandler.APIAuthHandler
      end

      scope unquote(path), as: :admin do
        pipe_through :admin

        forward "/auth", Brando.Plug.Authentication,
          guardian_module: Brando.web_module(Guardian),
          authorization_module: Brando.app_module(Authorization)

        scope "/api" do
          pipe_through [:api, :token, :authenticated]

          # General image uploads
          post "/images/upload/image_series/:image_series_id", upload_ctrl, :post

          # Villain
          post "/villain/upload", villain_ctrl, :upload_image
          get "/villain/templates/:slug", villain_ctrl, :templates
          post "/villain/templates/", villain_ctrl, :store_template
          post "/villain/templates/delete", villain_ctrl, :delete_template
          post "/villain/templates/sequence", villain_ctrl, :sequence_templates
          get "/villain/browse/:slug", villain_ctrl, :browse_images
        end

        # Main API scope for GraphQL
        scope "/graphql" do
          pipe_through [:graphql]
          forward "/", Absinthe.Plug, schema: Brando.app_module(Schema)
        end

        get "/*path", Brando.AdminController, :index
      end
    end
  end
end
