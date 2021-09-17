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
          live "/", BrandoAdmin.DashboardLive
          live "/config/navigation", BrandoAdmin.NavigationLive
          live "/config/identity", BrandoAdmin.Sites.IdentityLive
          live "/config/globals", BrandoAdmin.Sites.GlobalsLive
          live "/config/content/modules", BrandoAdmin.Content.ModuleListLive
          live "/config/content/modules/update/:entry_id", BrandoAdmin.Content.ModuleUpdateLive
          live "/config/content/sections", BrandoAdmin.Content.SectionListLive
          live "/config/content/sections/create", BrandoAdmin.Content.SectionCreateLive
          live "/config/content/sections/update/:entry_id", BrandoAdmin.Content.SectionUpdateLive
          live "/pages", BrandoAdmin.Pages.PageListLive
          live "/pages/create", BrandoAdmin.Pages.PageCreateLive
          live "/pages/create/:parent_id", BrandoAdmin.Pages.PageCreateLive
          live "/pages/update/:entry_id", BrandoAdmin.Pages.PageUpdateLive
          live "/pages/fragments/create", BrandoAdmin.Pages.PageFragmentCreateLive
          live "/pages/fragments/create/:parent_id", BrandoAdmin.Pages.PageFragmentCreateLive
          live "/pages/fragments/update/:entry_id", BrandoAdmin.Pages.PageFragmentUpdateLive
          live "/users", BrandoAdmin.Users.UserListLive
          live "/users/create", BrandoAdmin.Users.UserCreateLive
          live "/users/update/:entry_id", BrandoAdmin.Users.UserUpdateLive

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
