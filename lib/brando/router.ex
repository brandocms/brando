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

          live_session :redirect_if_user_is_authenticated,
            on_mount: [{BrandoAdmin.UserAuth, :redirect_if_user_is_authenticated}] do
            live "/login", UserLoginLive, :new
          end

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

        live_session :require_authenticated_user,
          on_mount: [{BrandoAdmin.UserAuth, :ensure_authenticated}] do
          # brando routes
          live "/assets/images", BrandoAdmin.Images.ImageListLive
          live "/assets/images/update/:entry_id", BrandoAdmin.Images.ImageFormLive, :update
          live "/assets/files", BrandoAdmin.Files.FileListLive
          live "/assets/videos", BrandoAdmin.Videos.VideoListLive

          scope "/config" do
            live "/cache", BrandoAdmin.Sites.CacheLive
            live "/global_sets", BrandoAdmin.Sites.GlobalSetListLive
            live "/global_sets/create", BrandoAdmin.Sites.GlobalSetFormLive, :create
            live "/global_sets/update/:entry_id", BrandoAdmin.Sites.GlobalSetFormLive, :update
            live "/identity", BrandoAdmin.Sites.IdentityLive
            live "/scheduled_publishing", BrandoAdmin.Sites.ScheduledPublishingLive
            live "/seo", BrandoAdmin.Sites.SEOLive
            live "/utils", BrandoAdmin.Sites.UtilsLive

            live "/navigation/menus", BrandoAdmin.Navigation.MenuListLive
            live "/navigation/menus/create", BrandoAdmin.Navigation.MenuFormLive, :create

            live "/navigation/menus/update/:entry_id",
                 BrandoAdmin.Navigation.MenuFormLive,
                 :update

            live "/navigation/menus/item/create", BrandoAdmin.Navigation.ItemFormLive, :create

            live "/navigation/menus/item/update/:entry_id",
                 BrandoAdmin.Navigation.ItemFormLive,
                 :update

            live "/content/containers", BrandoAdmin.Content.ContainerListLive
            live "/content/containers/create", BrandoAdmin.Content.ContainerFormLive, :create

            live "/content/containers/update/:entry_id",
                 BrandoAdmin.Content.ContainerFormLive,
                 :update

            live "/content/modules", BrandoAdmin.Content.ModuleListLive
            live "/content/modules/update/:entry_id", BrandoAdmin.Content.ModuleFormLive, :update
            live "/content/module_sets", BrandoAdmin.Content.ModuleSetListLive
            live "/content/module_sets/create", BrandoAdmin.Content.ModuleSetFormLive, :create

            live "/content/module_sets/update/:entry_id",
                 BrandoAdmin.Content.ModuleSetFormLive,
                 :update

            live "/content/palettes", BrandoAdmin.Content.PaletteListLive
            live "/content/palettes/create", BrandoAdmin.Content.PaletteFormLive, :create

            live "/content/palettes/update/:entry_id",
                 BrandoAdmin.Content.PaletteFormLive,
                 :update

            live "/content/table_templates", BrandoAdmin.Content.TableTemplateListLive

            live "/content/table_templates/create",
                 BrandoAdmin.Content.TableTemplateFormLive,
                 :create

            live "/content/table_templates/update/:entry_id",
                 BrandoAdmin.Content.TableTemplateFormLive,
                 :update

            live "/content/templates", BrandoAdmin.Content.TemplateListLive
            live "/content/templates/create", BrandoAdmin.Content.TemplateFormLive, :create

            live "/content/templates/update/:entry_id",
                 BrandoAdmin.Content.TemplateFormLive,
                 :update
          end

          scope "/globals" do
            live "/", BrandoAdmin.Globals.GlobalsLive
          end

          scope "/pages" do
            live "/", BrandoAdmin.Pages.PageListLive
            live "/create", BrandoAdmin.Pages.PageFormLive, :create
            live "/update/:entry_id", BrandoAdmin.Pages.PageFormLive, :update
            live "/fragments/create", BrandoAdmin.Pages.FragmentFormLive, :create
            live "/fragments/update/:entry_id", BrandoAdmin.Pages.FragmentFormLive, :update
          end

          scope "/users" do
            live "/", BrandoAdmin.Users.UserListLive
            live "/create", BrandoAdmin.Users.UserFormLive
            live "/update/:entry_id", BrandoAdmin.Users.UserFormLive, :update
            live "/password/:entry_id", BrandoAdmin.Users.UserUpdatePasswordLive
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
