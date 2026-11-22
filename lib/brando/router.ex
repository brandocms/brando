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
        get "/robots.txt", BrandoWeb.SEOController, :robots
        get "/__p__/:preview_key", BrandoWeb.PreviewController, :show
        get "/__ssg_preview__/:token/*path", Brando.SSG.PreviewController, :show
        get "/sitemaps/:file", BrandoWeb.SitemapController, :show
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

  @doc """
  The remote MCP endpoint (`Brando.MCP`), its OAuth endpoints and metadata,
  and the consent screen. Mounting them lets an administrator turn the
  endpoint on per site environment, under Configuration → Integrations;
  until then every one of them answers 404. Without this call there is no
  network path to MCP at all.

  Add it after `admin_routes/3`, whose admin pipeline the consent screen
  uses, and before the scope that calls `page_routes/1`, whose catch-all
  would otherwise take `/mcp`:

      admin_routes do
        # …
      end

      mcp_routes()

      scope "/" do
        pipe_through :browser
        page_routes()
      end

  It mounts `/mcp` and `/mcp/*`, `/.well-known/oauth-protected-resource/mcp…`,
  `/.well-known/oauth-authorization-server/mcp…` and `/admin/mcp/authorize`,
  outside the browser pipeline: the endpoint takes bearer tokens, not the
  session.
  """
  defmacro mcp_routes do
    quote do
      @doc "Whether this router mounts `Brando.Router.mcp_routes/0`."
      def __brando_mcp_routes__, do: true

      mcp_sandbox_hooks =
        if Module.get_attribute(__MODULE__, :sql_sandbox),
          do: [{BrandoAdmin.Mounts.LiveAcceptance, {:default, nil}}],
          else: []

      pipeline :brando_mcp_consent_check do
        plug Brando.MCP.ConsentPlug, :check
      end

      pipeline :brando_mcp_consent do
        plug Brando.MCP.ConsentPlug, :guard
      end

      Brando.Router.__admin_routes_start__(__MODULE__)

      scope "/" do
        match :*, "/.well-known/oauth-protected-resource/mcp", Brando.MCP.HTTP, :resource_metadata
        match :*, "/.well-known/oauth-protected-resource/mcp/*tenant", Brando.MCP.HTTP, :resource_metadata
        match :*, "/.well-known/oauth-authorization-server/mcp", Brando.MCP.HTTP, :server_metadata
        match :*, "/.well-known/oauth-authorization-server/mcp/*tenant", Brando.MCP.HTTP, :server_metadata
        match :*, "/mcp", Brando.MCP.HTTP, :endpoint
        # An upload URL's secret is a path segment, so its parameters are not
        # logged (Phoenix filters them by name only)
        match :*, "/mcp/uploads/:id/:secret", Brando.MCP.HTTP, :upload, log: false
        match :*, "/mcp/:site/:environment/uploads/:id/:secret", Brando.MCP.HTTP, :upload, log: false
        match :*, "/mcp/*path", Brando.MCP.HTTP, :dispatch
      end

      scope "/admin/mcp", as: :admin_mcp do
        pipe_through [:brando_mcp_consent_check, :admin, :brando_root_layout, :brando_mcp_consent]

        live_session :brando_mcp_consent,
          on_mount:
            mcp_sandbox_hooks ++
              [
                {BrandoAdmin.UserAuth, :ensure_authenticated},
                {Brando.Tenant.LiveView, :default},
                {BrandoAdmin.Authorization, :default}
              ] do
          live "/authorize", BrandoAdmin.MCP.ConsentLive
        end
      end

      Brando.Router.__admin_routes_end__(__MODULE__)
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

      @before_compile Brando.Router

      @brando_admin_path Phoenix.Router.scoped_path(__MODULE__, unquote(path))

      @doc """
      The path `Brando.Router.admin_routes/3` mounts the admin on, with that
      of any enclosing scope.
      """
      def __brando_admin_path__, do: @brando_admin_path

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

      Brando.Router.__admin_routes_start__(__MODULE__)

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
          post "/login/passkey/options", UserSessionController, :passkey_options
          post "/login/passkey", UserSessionController, :passkey
        end

        scope "/", BrandoAdmin do
          pipe_through [:admin]

          # A GET only asks (`BrandoAdmin.UserLogoutLive`): signing out takes a
          # DELETE with the CSRF token. POST is for an endpoint without
          # `Plug.MethodOverride`.
          live_session :logout, on_mount: sandbox_hooks ++ [{BrandoAdmin.UserAuth, :mount_current_user}] do
            live "/logout", UserLogoutLive, :confirm
          end

          delete "/logout", UserSessionController, :delete
          post "/logout", UserSessionController, :delete
        end
      end

      scope unquote(path), as: :admin do
        pipe_through [:admin, :brando_root_layout, :require_authenticated_user]

        get "/access-denied", BrandoAdmin.AccessDeniedController, :show
        # The Cache screen's address: its action moved to Utilities
        get "/config/cache", BrandoAdmin.MovedController, :utilities
        get "/content-transfer/download/:token", BrandoAdmin.ContentTransferDownloadController, :show
        get "/forms/:key/submissions/export", BrandoAdmin.FormSubmissionsExportController, :export
        # Where Figma sends the browser back to (Brando.Figma.OAuth.redirect_url/0);
        # not logged, for the code in its query
        get "/config/mcp/figma/callback", BrandoAdmin.FigmaCallbackController, :show, log: false

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
          # What a connected tool does as it happens (Brando.MCP.Watch)
          live "/assistant/connected/live/:grant_id", BrandoAdmin.MCP.WatchLive
          live "/assistant/connected/:proposal_id", BrandoAdmin.AI.AssistantLive, :connected
          live "/assistant/:conversation_id", BrandoAdmin.AI.AssistantLive, :show
          # The sidebar of frontend edit mode, framed by the published page.
          live "/frontend-edit", BrandoAdmin.FrontendEdit.EditorLive
          # Every entry the user may read, by title and content (Brando.Search)
          live "/search", BrandoAdmin.SearchLive
          # Publishing, scheduled revisions and expiries by day (BrandoAdmin.Schedule)
          live "/calendar", BrandoAdmin.CalendarLive
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

      Brando.Router.__admin_routes_end__(__MODULE__)
    end
  end

  @doc """
  Marks where the routes of `admin_routes/3` or `mcp_routes/0` start in
  `module`. The routes declared until `__admin_routes_end__/1` are left out of
  the match on a host that does not serve the admin
  (`BrandoAdmin.AdminHost`), with the complete paths of any enclosing scope.
  """
  def __admin_routes_start__(module) do
    Module.put_attribute(module, :brando_admin_routes_start, route_count(module))
  end

  @doc "Marks where the routes `__admin_routes_start__/1` started end in `module`."
  def __admin_routes_end__(module) do
    range = Module.get_attribute(module, :brando_admin_routes_start)..(route_count(module) - 1)//1
    Module.put_attribute(module, :brando_admin_routes, [range | Module.get_attribute(module, :brando_admin_routes) || []])
  end

  defp route_count(module), do: module |> Module.get_attribute(:phoenix_routes) |> length()

  # `__match_route_without_admin__/3`: Phoenix's `__match_route__/3` for every
  # route but those `admin_routes/3` and `mcp_routes/0` declare, in the order
  # they are declared, with pipelines of its own. `__match_route__/3` itself
  # becomes host-aware, so the router's `call/2`, `Phoenix.Router.route_info/4`
  # and a LiveView's join all match the same routes. Phoenix defines
  # `__match_route__/3` in its own `@before_compile`, which `use Phoenix.Router`
  # registers before `admin_routes/3` registers this one, so it is defined
  # (and can be overridden) by the time this runs.
  @doc false
  defmacro __before_compile__(env) do
    admin_ranges = Module.get_attribute(env.module, :brando_admin_routes) || []

    routes =
      env.module
      |> Module.get_attribute(:phoenix_routes)
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.reject(fn {_route, index} -> Enum.any?(admin_ranges, &(index in &1)) end)
      |> Enum.map(&elem(&1, 0))

    {clauses, {pipes, _known}} = Enum.map_reduce(routes, {[], %{}}, &build_match_without_admin(&1, &2, env))

    # Generated, as Phoenix's own catch-all is: a router ending in a route that
    # matches every path makes it unreachable
    match_catch_all =
      quote generated: true do
        defp __match_route_without_admin__(_verb, _path, _host), do: :error
      end

    quote do
      unquote(pipes)

      unquote(clauses)
      unquote(match_catch_all)

      defoverridable __match_route__: 3

      @doc """
      Matches a route as `Phoenix.Router` does, but on a host that does not
      serve the admin the routes `Brando.Router.admin_routes/3` and
      `Brando.Router.mcp_routes/0` declare are left out
      (`BrandoAdmin.AdminHost.serves_admin_on?/1`).
      """
      def __match_route__(verb, path, host) do
        if BrandoAdmin.AdminHost.serves_admin_on?(host),
          do: super(verb, path, host),
          else: __match_route_without_admin__(verb, path, host)
      end
    end
  end

  defp build_match_without_admin(route, {pipes, known}, env) do
    {pipe_name, pipes, known} =
      case Map.fetch(known, route.pipe_through) do
        {:ok, name} ->
          {name, pipes, known}

        :error ->
          name = :"__brando_site_pipe_through#{map_size(known)}__"
          {name, [build_pipe(name, route.pipe_through, env) | pipes], Map.put(known, route.pipe_through, name)}
      end

    %{prepare: prepare, dispatch: dispatch, path_params: path_params, hosts: hosts, path: path} =
      Phoenix.Router.Route.exprs(route)

    verb =
      case route.verb do
        :* -> Macro.var(:_verb, nil)
        verb -> verb |> to_string() |> String.upcase()
      end

    clauses =
      for host <- hosts do
        quote line: route.line do
          defp __match_route_without_admin__(unquote(verb), unquote(path), unquote(host)) do
            {unquote(route_metadata(route, path_params)),
             fn var!(conn, :conn), %{path_params: var!(path_params, :conn)} -> unquote(prepare) end,
             &(unquote(Macro.var(pipe_name, __MODULE__)) / 1), unquote(dispatch)}
          end
        end
      end

    {clauses, {pipes, known}}
  end

  defp route_metadata(route, path_params) do
    pairs = [
      conn: nil,
      route: route.path,
      plug: route.plug,
      plug_opts: Macro.escape(route.plug_opts),
      path_params: path_params,
      pipe_through: route.pipe_through
    ]

    {:%{}, [], pairs ++ Macro.escape(Map.to_list(route.metadata))}
  end

  defp build_pipe(name, pipe_through, env) do
    plugs =
      pipe_through
      |> Enum.reverse()
      |> Enum.map(fn
        {plug, opts} -> {plug, opts, true}
        plug -> {plug, [], true}
      end)

    {conn, body} = Plug.Builder.compile(env, plugs, init_mode: Phoenix.plug_init_mode(), log_on_halt: :debug)

    quote do
      defp unquote(name)(unquote(conn)), do: unquote(body)
    end
  end

  # Brando's own admin screens, kept out of `admin_routes/3`'s quote.
  defp config_routes do
    quote do
      live "/assets", BrandoAdmin.Sites.AssetLive
      live "/environments", BrandoAdmin.Sites.EnvironmentLive
      live "/publishing", BrandoAdmin.Sites.PublishingLive
      live "/markdown-sources", BrandoAdmin.Sites.MarkdownSourcesLive
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
      live "/integrations", BrandoAdmin.Sites.IntegrationsLive
      live "/webhooks", BrandoAdmin.Sites.WebhooksLive, :index
      live "/webhooks/new", BrandoAdmin.Sites.WebhooksLive, :new
      live "/webhooks/deliveries", BrandoAdmin.Sites.WebhooksLive, :deliveries
      live "/webhooks/:id/edit", BrandoAdmin.Sites.WebhooksLive, :edit
      live "/webhooks/:id/deliveries", BrandoAdmin.Sites.WebhooksLive, :deliveries
      live "/notifications", BrandoAdmin.Sites.NotificationsLive, :index
      live "/notifications/new", BrandoAdmin.Sites.NotificationsLive, :new
      live "/notifications/deliveries", BrandoAdmin.Sites.NotificationsLive, :deliveries
      live "/notifications/:id/edit", BrandoAdmin.Sites.NotificationsLive, :edit
      live "/notifications/:id/deliveries", BrandoAdmin.Sites.NotificationsLive, :deliveries
      live "/mcp", BrandoAdmin.Sites.MCPLive
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
      live "/content/modules/stale-blocks", BrandoAdmin.Content.StaleBlocksLive, :index
      live "/content/modules/release", BrandoAdmin.Content.ReleaseChangesLive
      live "/content/modules/update/:entry_id", BrandoAdmin.Content.ModuleFormLive, :update
      live "/content/modules/update/:entry_id/stale-blocks", BrandoAdmin.Content.StaleBlocksLive, :module
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

      live "/confirm", BrandoAdmin.Users.ConfirmLive
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
