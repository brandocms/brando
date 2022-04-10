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

  defmacro admin_routes(path \\ "/admin", do: block) do
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

      pipeline :api do
        plug :accepts, ["json"]
        # plug RemoteIp
        # plug :refresh_token
      end

      pipeline :root_layout do
        plug :put_root_layout, {BrandoAdmin.LayoutView, :root}
      end

      scope unquote(path), as: :admin do
        scope "/", BrandoAdmin do
          pipe_through [:admin, :redirect_if_user_is_authenticated]

          get "/login", UserSessionController, :new
          post "/login", UserSessionController, :create
        end

        scope "/", BrandoAdmin do
          pipe_through [:admin]

          get "/logout", UserSessionController, :delete
        end
      end

      scope unquote(path), as: :admin do
        pipe_through [:admin, :root_layout, :require_authenticated_user]

        post "/api/content/upload/image", BrandoAdmin.API.Content.Upload.ImageController, :create

        live_session :admin do
          # brando routes
          scope "/assets", BrandoAdmin.Assets do
            live "/images", ImagesLive
            live "/files", FilesLive
          end

          scope "/config", BrandoAdmin.Sites do
            live "/cache", CacheLive
            live "/global_sets", GlobalSetListLive
            live "/global_sets/create", GlobalSetCreateLive
            live "/global_sets/update/:entry_id", GlobalSetUpdateLive
            live "/identity", IdentityLive
            live "/scheduled_publishing", ScheduledPublishingLive
            live "/seo", SEOLive
          end

          scope "/config", BrandoAdmin.Navigation do
            live "/navigation/menus", MenuListLive
            live "/navigation/menus/create", MenuCreateLive
            live "/navigation/menus/update/:entry_id", MenuUpdateLive
          end

          scope "/config", BrandoAdmin.Content do
            live "/content/modules", ModuleListLive
            live "/content/modules/update/:entry_id", ModuleUpdateLive
            live "/content/palettes", PaletteListLive
            live "/content/palettes/create", PaletteCreateLive
            live "/content/palettes/update/:entry_id", PaletteUpdateLive
            live "/content/templates", TemplateListLive
            live "/content/templates/create", TemplateCreateLive
            live "/content/templates/update/:entry_id", TemplateUpdateLive
          end

          scope "/globals", BrandoAdmin.Globals do
            live "/", GlobalsLive
          end

          scope "/pages", BrandoAdmin.Pages do
            live "/", PageListLive
            live "/create", PageCreateLive
            live "/create/:parent_id", PageCreateLive
            live "/update/:entry_id", PageUpdateLive
            live "/fragments/create", PageFragmentCreateLive
            live "/fragments/create/:parent_id", PageFragmentCreateLive
            live "/fragments/update/:entry_id", PageFragmentUpdateLive
          end

          scope "/users", BrandoAdmin.Users do
            live "/", UserListLive
            live "/create", UserCreateLive
            live "/update/:entry_id", UserUpdateLive
          end

          # app routes
          unquote(block)
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
