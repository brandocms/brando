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
  defmacro page_routes(opts \\ []) do
    default = [root: true, catch_all: true]
    options = Keyword.merge(default, opts)

    quote do
      if unquote(options)[:root] do
        get "/robots.txt", Brando.SEOController, :robots
        get "/__p__/:preview_key", Brando.PreviewController, :show
        get "/sitemaps/:file", Brando.SitemapController, :show
      end

      if unquote(options)[:catch_all] do
        get "/", Brando.web_module(PageController), :index
        get "/*path", Brando.web_module(PageController), :show
      end
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
        plug :put_root_layout, {BrandoAdmin.Layouts, :root}
        plug :fetch_current_user
        plug :put_admin_locale
      end

      pipeline :api do
        plug :accepts, ["json"]
        # plug RemoteIp
        # plug :refresh_token
      end

      pipeline :brando_root_layout do
        plug :put_root_layout, {BrandoAdmin.Layouts, :root}
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
        pipe_through [:admin, :brando_root_layout, :require_authenticated_user]

        post "/api/content/upload/image", BrandoAdmin.API.Content.Upload.ImageController, :create
        post "/api/content/upload/file", BrandoAdmin.API.Content.Upload.FileController, :create

        live_session :admin, on_mount: [{Brando.Users, :ensure_authenticated}] do
          # brando routes
          live "/assets/images", BrandoAdmin.Images.ImageListLive
          live "/assets/images/update/:entry_id", BrandoAdmin.Images.ImageUpdateLive
          live "/assets/files", BrandoAdmin.Files.FileListLive
          live "/assets/videos", BrandoAdmin.Videos.VideoListLive

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
            live "/password/:entry_id", UserUpdatePasswordLive
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
