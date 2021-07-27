defmodule Brando.Router do
  # script-src:
  # img-src: https://www.google-analytics.com
  # connect-src: https://www.google-analytics.com

  @default_extra_secure_headers [
    {"content-security-policy",
     "default-src 'self'; connect-src *; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://www.google-analytics.com https://ssl.google-analytics.com; img-src * data:; media-src *"},
    {"referrer-policy", "strict-origin-when-cross-origin"},
    {"permissions-policy",
     "accelerometer=(), camera=(), fullscreen=(self), geolocation=(self), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"}
  ]
  defmacro page_routes do
    quote do
      get "/robots.txt", Brando.SEOController, :robots
      get "/", Brando.web_module(PageController), :index
      get "/__p__/:preview_key", Brando.PreviewController, :show
      get "/*path", Brando.web_module(PageController), :show
    end
  end

  defmacro admin_routes(path \\ "/admin") do
    quote do
      import BrandoAdmin.UserAuth

      upload_ctrl = BrandoAdmin.API.Images.UploadController
      villain_ctrl = BrandoAdmin.API.Villain.VillainController

      pipeline :admin do
        plug :accepts, ["html"]
        plug :fetch_session
        plug :fetch_live_flash
        plug :protect_from_forgery
        plug :put_secure_browser_headers
        plug :put_extra_secure_browser_headers
        plug :put_root_layout, {BrandoAdmin.LayoutView, :root}
        plug :fetch_current_user
        plug :put_admin_locale
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
        scope "/", BrandoAdmin do
          pipe_through [:admin, :redirect_if_user_is_authenticated]

          get "/login", UserSessionController, :new
          post "/login", UserSessionController, :create
          get "/users/reset_password", UserResetPasswordController, :new
          post "/users/reset_password", UserResetPasswordController, :create
          get "/users/reset_password/:token", UserResetPasswordController, :edit
          put "/users/reset_password/:token", UserResetPasswordController, :update
        end

        scope "/", BrandoAdmin do
          pipe_through [:admin, :require_authenticated_user]

          get "/users/settings", UserSettingsController, :edit
          put "/users/settings", UserSettingsController, :update
          get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email
        end

        scope "/", BrandoAdmin do
          pipe_through [:admin]

          get "/logout", UserSessionController, :delete
          get "/users/confirm", UserConfirmationController, :new
          post "/users/confirm", UserConfirmationController, :create
          get "/users/confirm/:token", UserConfirmationController, :confirm
        end

        scope "/api" do
          pipe_through [:api, :token, :authenticated]

          # General image uploads
          post "/images/upload/image_series/:image_series_id", upload_ctrl, :post

          # Villain
          post "/villain/upload", villain_ctrl, :upload_image
          get "/villain/modules/:slug", villain_ctrl, :modules
          post "/villain/modules/", villain_ctrl, :store_module
          post "/villain/modules/delete", villain_ctrl, :delete_module
          post "/villain/modules/sequence", villain_ctrl, :sequence_modules
          get "/villain/browse/:slug", villain_ctrl, :browse_images
        end

        # Main API scope for GraphQL
        scope "/graphql" do
          pipe_through [:graphql]
          forward "/", Absinthe.Plug, schema: Brando.app_module(Schema)
        end
      end
    end
  end

  @spec put_extra_secure_browser_headers(Plug.Conn.t(), Map.t()) :: Plug.Conn.t()
  def put_extra_secure_browser_headers(conn, extra_headers \\ %{}) do
    if Brando.env() == :prod do
      conn
      |> Plug.Conn.merge_resp_headers(@default_extra_secure_headers)
      |> Plug.Conn.merge_resp_headers(extra_headers)
    else
      conn
    end
  end
end
