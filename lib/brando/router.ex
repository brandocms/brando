defmodule Brando.Router do
  # script-src:
  # img-src: https://www.google-analytics.com
  # connect-src: https://www.google-analytics.com

  @default_extra_secure_headers [
    {"content-security-policy",
     "default-src 'self'; connect-src *; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://www.google-analytics.com https://ssl.google-analytics.com https://challenges.cloudflare.com; frame-src 'self' https://challenges.cloudflare.com; img-src * data:; media-src *"},
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
        get "/__ssg_preview__/:token/*path", Brando.SSG.PreviewController, :show
        get "/sitemaps/:file", Brando.SitemapController, :show
        # Inside the application's browser pipeline, so `protect_from_forgery`
        # checks the token `Brando.HTML.Forms.site_form/1` carries.
        post "/__brando/forms/:key", Brando.Forms.SubmissionController, :create
        get "/__brando/forms/csrf-token", Brando.Forms.SubmissionController, :csrf_token
      end

      if unquote(options)[:catch_all] do
        get "/", Brando.web_module(PageController), :index
        get "/*path", Brando.web_module(PageController), :show
      end
    end
  end

  @doc """
  The route statically delivered sites post their forms to.

  A static site has no session for a CSRF token, so this route must sit outside
  the browser pipeline; it checks that the request comes from one of the
  site's own domains instead (see `Brando.Forms.Delivery`). Add it at the top
  level of the router, before the scope that calls `page_routes/1`:

      form_routes()

      scope "/" do
        pipe_through :browser
        page_routes()
      end
  """
  defmacro form_routes do
    quote do
      pipeline :brando_static_forms do
        plug :accepts, ["html", "json"]
      end

      scope "/__brando/forms/static" do
        pipe_through :brando_static_forms
        post "/:site/:environment/:key", Brando.Forms.SubmissionController, :create_static
      end
    end
  end

  defmacro admin_routes(path \\ "/admin", options \\ [], do: block) do
    quote do
      import BrandoAdmin.UserAuth
      import Brando.Plug.I18n, only: [put_admin_locale: 2]

      # Check if @sql_sandbox module attribute is set (for e2e testing)
      # If so, include LiveAcceptance hook to grant sandbox access before auth checks
      sandbox_hooks =
        if Module.get_attribute(__MODULE__, :sql_sandbox) do
          [{BrandoAdmin.Mounts.LiveAcceptance, {:default, nil}}]
        else
          []
        end

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
        plug Brando.Plug.AdminTenant
        plug :put_admin_locale
      end

      pipeline unquote(Keyword.get(options, :api_pipeline, :api)) do
        plug :accepts, ["json"]
        # plug RemoteIp
        # plug :refresh_token
      end

      pipeline :brando_root_layout do
        plug :put_root_layout, {BrandoAdmin.Layouts, :root}
      end

      # The icon stylesheet (`Brando.Icons.stylesheet_path/0`). Outside the admin path
      # and its pipelines: the login page and front-end edit mode use icons too.
      forward "/__brando/icons", Brando.Plug.Icons

      scope unquote(path), as: :admin do
        scope "/", BrandoAdmin do
          pipe_through [:admin, :redirect_if_user_is_authenticated]

          live_session :redirect_if_user_is_authenticated,
            on_mount: sandbox_hooks ++ [{BrandoAdmin.UserAuth, :redirect_if_user_is_authenticated}] do
            live "/login", UserLoginLive, :new
            live "/login/two-factor", UserTwoFactorLive, :verify
            live "/login/two-factor/setup", UserTwoFactorSetupLive, :setup
            live "/reset-password", UserForgotPasswordLive, :new
            live "/reset-password/:token", UserResetPasswordLive, :edit
          end

          post "/login", UserSessionController, :create
          post "/login/two-factor", UserSessionController, :two_factor
          post "/login/two-factor/complete", UserSessionController, :complete_setup
        end

        scope "/", BrandoAdmin do
          pipe_through [:admin]

          get "/logout", UserSessionController, :delete
        end
      end

      scope unquote(path), as: :admin do
        pipe_through [:admin, :brando_root_layout, :require_authenticated_user]

        get "/access-denied", BrandoAdmin.AccessDeniedController, :show
        get "/content-transfer/download/:token", BrandoAdmin.ContentTransferDownloadController, :show
        get "/forms/:key/submissions/export", BrandoAdmin.FormSubmissionsExportController, :export

        post "/environment", BrandoAdmin.EnvironmentController, :update
        post "/api/content/image/replace_crop", BrandoAdmin.API.Content.Upload.ImageController, :replace_crop

        live_session :require_authenticated_user,
          on_mount:
            sandbox_hooks ++
              [
                {BrandoAdmin.UserAuth, :ensure_authenticated},
                {Brando.Tenant.LiveView, :default},
                {BrandoAdmin.Authorization, :default}
              ] do
          live "/groups", BrandoAdmin.Users.GroupsLive
          live "/assistant", BrandoAdmin.AI.AssistantLive
          live "/assistant/shared/:token", BrandoAdmin.AI.AssistantLive, :shared
          live "/assistant/connected", BrandoAdmin.AI.AssistantLive, :connected
          live "/assistant/connected/:proposal_id", BrandoAdmin.AI.AssistantLive, :connected
          live "/assistant/:conversation_id", BrandoAdmin.AI.AssistantLive, :show
          # The sidebar of frontend edit mode, framed by the published page.
          live "/frontend-edit", BrandoAdmin.FrontendEdit.EditorLive
          # brando routes
          live "/sites", BrandoAdmin.Sites.SiteLive
          live "/assets/images", BrandoAdmin.Images.ImageListLive
          live "/assets/images/alt-text", BrandoAdmin.Images.AltTextLive
          live "/assets/images/update/:entry_id", BrandoAdmin.Images.ImageFormLive, :update
          live "/assets/videos", BrandoAdmin.Videos.VideoListLive
          live "/assets/videos/update/:entry_id", BrandoAdmin.Videos.VideoFormLive, :update
          live "/assets/galleries", BrandoAdmin.Galleries.GalleryListLive

          live "/assets/galleries/update/:entry_id",
               BrandoAdmin.Galleries.GalleryFormLive,
               :update

          live "/assets/files", BrandoAdmin.Files.FileListLive

          scope "/config" do
            unquote(config_routes())
          end

          unquote(section_routes())

          # app routes
          unquote(block)
        end
      end
    end
  end

  # Brando's own admin screens, kept out of `admin_routes/3`'s quote.
  defp config_routes do
    quote do
      live "/assets", BrandoAdmin.Sites.AssetLive
      live "/environments", BrandoAdmin.Sites.EnvironmentLive
      live "/publishing", BrandoAdmin.Sites.PublishingLive
      live "/markdown-sources", BrandoAdmin.Sites.MarkdownSourcesLive
      live "/cache", BrandoAdmin.Sites.CacheLive
      live "/forms", BrandoAdmin.Forms.FormListLive
      live "/forms/create", BrandoAdmin.Forms.FormFormLive, :create
      live "/forms/update/:entry_id", BrandoAdmin.Forms.FormFormLive, :update
      live "/forms/messages", BrandoAdmin.Forms.MessagesLive
      live "/global_sets", BrandoAdmin.Sites.GlobalSetListLive
      live "/global_sets/create", BrandoAdmin.Sites.GlobalSetFormLive, :create
      live "/global_sets/update/:entry_id", BrandoAdmin.Sites.GlobalSetFormLive, :update
      live "/identity", BrandoAdmin.Sites.IdentityLive
      live "/scheduled_publishing", BrandoAdmin.Sites.ScheduledPublishingLive
      live "/activity", BrandoAdmin.Sites.ActivityLive
      live "/seo", BrandoAdmin.Sites.SEOLive
      live "/utils", BrandoAdmin.Sites.UtilsLive
      live "/utils/loose-blocks", BrandoAdmin.Sites.BlockAuditLive
      live "/assistant", BrandoAdmin.AI.GuidanceLive
      live "/import-export", BrandoAdmin.Sites.ContentTransferLive

      live "/navigation/menus", BrandoAdmin.Navigation.MenuListLive
      live "/navigation/menus/create", BrandoAdmin.Navigation.MenuFormLive, :create

      live "/navigation/menus/update/:entry_id",
           BrandoAdmin.Navigation.MenuFormLive,
           :update

      live "/content/containers", BrandoAdmin.Content.ContainerListLive
      live "/content/containers/create", BrandoAdmin.Content.ContainerFormLive, :create

      live "/content/containers/update/:entry_id",
           BrandoAdmin.Content.ContainerFormLive,
           :update

      live "/content/modules", BrandoAdmin.Content.ModuleListLive
      live "/content/modules/update/:entry_id", BrandoAdmin.Content.ModuleFormLive, :update
      live "/content/shared_library", BrandoAdmin.Content.SharedLibraryLive

      live "/content/shared_library/modules/update/:entry_id",
           BrandoAdmin.Content.ModuleFormLive,
           :shared_update

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
  end

  defp section_routes do
    quote do
      scope "/globals" do
        live "/", BrandoAdmin.Globals.GlobalsLive
      end

      # What visitors sent; the forms themselves are built under Configuration
      scope "/forms" do
        live "/", BrandoAdmin.Forms.InboxLive
        live "/:key/submissions", BrandoAdmin.Forms.SubmissionsLive
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
        live "/password", BrandoAdmin.Users.UserUpdatePasswordLive
        live "/security", BrandoAdmin.Users.UserSecurityLive
        live "/sign-in-policy", BrandoAdmin.Users.SignInPolicyLive
      end
    end
  end

  @spec put_extra_secure_browser_headers(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
