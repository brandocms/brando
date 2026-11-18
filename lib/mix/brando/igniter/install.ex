if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Igniter.Code.List, as: IgniterList
    alias Igniter.Project.Application, as: ProjectApplication
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.AgentFiles
    alias Mix.Brando.Igniter.Assets
    alias Mix.Brando.Igniter.Dependencies
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Install.Deployment
    alias Mix.Brando.Igniter.Install.Docker
    alias Mix.Brando.Igniter.Install.PhoenixStatic
    alias Mix.Brando.Igniter.Install.Toolchain
    alias Mix.Brando.Igniter.Install.Version
    alias Mix.Brando.Igniter.Project
    alias Mix.Brando.Igniter.Release
    alias Mix.Brando.Igniter.RouteInventory
    alias Mix.Brando.Igniter.SoftDeleteRepo
    alias Mix.Brando.Igniter.Source
    alias Mix.Brando.Install.Hosts
    alias Mix.Brando.Install.Options
    alias Mix.Brando.Install.Templates
    alias Sourceror.Zipper

    @support_templates ~w(
      lib/application_name/presence.ex
      lib/application_name/authorization.ex
      lib/application_name_web/villain/parser.ex
      lib/application_name_web/villain/filters.ex
      lib/application_name_admin/menus.ex
      lib/application_name_admin/live/dashboard_live.ex
    )

    def plan(igniter) do
      with {:ok, igniter, options} <- Configuration.namespace_options(igniter, igniter.args.options),
           {:ok, igniter, project} <- Project.discover(igniter, options),
           :ok <- public_site_options(options),
           {:ok, igniter, fresh?} <- preflight(igniter, project),
           {:ok, igniter} <- Mix.Brando.Igniter.Install.Migrations.preflight(igniter),
           {:ok, igniter, existing} <- Configuration.existing_tenancy(igniter),
           {:ok, tenancy} <- resolve_tenancy(options, existing, project),
           {igniter, deployment} = Deployment.existing(igniter),
           {:ok, hosts} <- resolve_hosts(options, project, deployment) do
        igniter
        |> Configuration.configure(project, tenancy)
        |> dependencies(options)
        |> Version.plan()
        |> Deployment.plan(project, hosts, deployment, tenancy.mode)
        |> Docker.plan(project, tenancy.mode)
        |> Toolchain.plan(fresh?)
        |> Release.plan(project, existing: :keep)
        |> SoftDeleteRepo.plan(project.repo)
        |> support_files(project)
        |> AgentFiles.plan()
        |> Assets.plan(project)
        |> PhoenixStatic.plan()
        |> PhoenixStatic.icons(project)
        |> Mix.Brando.Igniter.Install.Migrations.plan(project)
        |> application(project)
        |> endpoint(project, tenancy.mode)
        |> router(project)
        |> public_site(project, options, fresh?)
        # Last: Rewrite rereads the formatters when .formatter.exs changes, and
        # the files above are formatted as the project's formatters stood.
        |> formatter()
        |> instructions(tenancy)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp public_site_options(options) do
      if options[:public_site] == true,
        do:
          {:error,
           "A new install adds the CMS public site unless given --no-public-site; add it to an installed application with mix brando.gen.site."},
        else: :ok
    end

    # Only a new install gets the public site: a rerun keeps what the
    # application has, like the tenancy mode. Without it, also when the site
    # skips itself, phx.new's robots.txt moves to the frontend's public/
    # folder; `public_robots/1` reads the `:page_html_module` the site plans.
    defp public_site(igniter, project, options, fresh?) do
      if fresh? and options[:public_site] != false,
        do:
          igniter
          |> Mix.Brando.Igniter.Site.plan(project, Keyword.put(options, :installing, true))
          |> PhoenixStatic.public_robots(),
        else: PhoenixStatic.public_robots(igniter)
    end

    defp preflight(igniter, project) do
      {:ok, {igniter, _, router}} = ProjectModule.find_module(igniter, project.router)
      routes = RouteInventory.read(router)

      cond do
        Enum.any?(routes, &(&1.kind == :admin_routes)) ->
          {:ok, igniter, false}

        Enum.any?(routes, &(&1.kind == :unknown || &1.path == "/admin" || String.starts_with?(&1.path, "/admin/"))) ->
          {:error,
           "The router already owns /admin routes or uses dynamic paths. Review that ownership and integrate Brando's admin_routes block explicitly before installing; existing routes cannot be silently shadowed."}

        true ->
          {:ok, igniter, true}
      end
    end

    defp resolve_tenancy(options, existing, project) do
      guided? = (options[:interactive] || options[:tenancy_prompt]) && options[:tenancy_prompt] != false

      if guided? && (existing == nil || options[:tenancy_mode]) do
        {:ok, Options.resolve_tenancy_options!(options, project.otp_app |> to_string() |> String.replace("_", "-"))}
      else
        Options.tenancy(options, existing || %{mode: :none, site_key: nil})
      end
    rescue
      error in Mix.Error -> {:error, Exception.message(error)}
    end

    # Guided questions only for what is left to generate.
    defp resolve_hosts(options, project, deployment) do
      Hosts.resolve(options, project.otp_app, if(options[:interactive] == true, do: Deployment.guided(deployment)))
    rescue
      error in Mix.Error -> {:error, Exception.message(error)}
    end

    defp dependencies(igniter, options) do
      # Preserve the user's package/git/path selection, including local Brando.
      deps = [{:gettext, "~> 1.0"}, {:jason, "~> 1.0"}] ++ if(options[:ai], do: [Brando.AI.dependency()], else: [])
      Enum.reduce(deps, igniter, &Dependencies.add_new(&2, &1))
    end

    # Brando's .formatter.exs exports the Blueprint DSL's locals_without_parens.
    # This is Igniter.Project.Formatter.import_dep/2 without its formatting:
    # Igniter reformats every loaded source after any .formatter.exs update.
    defp formatter(igniter) do
      if Igniter.exists?(igniter, ".formatter.exs") do
        igniter
        |> Igniter.include_existing_file(".formatter.exs")
        |> Igniter.update_file(".formatter.exs", &import_brando/1)
      else
        Igniter.add_notice(igniter, "There is no .formatter.exs; add import_deps: [:brando] to the one you create.")
      end
    end

    defp import_brando(source) do
      zipper = source |> Rewrite.Source.get(:quoted) |> Zipper.zip()

      with %Zipper{} = options <- Zipper.down(zipper),
           false <- imports_brando?(Zipper.rightmost(options)),
           {:ok, options} <-
             options
             |> Zipper.rightmost()
             |> CodeKeyword.put_in_keyword([:import_deps], [:brando], &Igniter.Code.List.prepend_new_to_list(&1, :brando)) do
        Rewrite.Source.update(source, :quoted, Zipper.topmost_root(options), by: :configure)
      else
        true ->
          source

        _ ->
          {:notice,
           "Add :brando to import_deps in .formatter.exs, so mix format keeps Blueprint DSL calls without parentheses."}
      end
    end

    defp imports_brando?(options) do
      case CodeKeyword.get_key(options, :import_deps) do
        {:ok, deps} -> Igniter.Code.List.find_list_item_index(deps, &Common.nodes_equal?(&1, :brando)) != nil
        :error -> false
      end
    end

    defp support_files(igniter, project) do
      igniter =
        Templates.manifest()
        |> Enum.filter(fn {_format, source, _target} -> source in @support_templates end)
        |> Enum.reduce(igniter, &copy(&2, &1, project))

      # Phoenix already owns Web.Gettext. The admin backend is a separate module.
      igniter =
        Files.create(igniter, module_path(Module.concat(project.admin_module, Gettext)), """
        defmodule #{inspect(project.admin_module)}.Gettext do
          use Gettext.Backend, otp_app: #{inspect(project.otp_app)}, priv: "priv/gettext/backend"
        end
        """)

      preview = Module.concat(project.web_module, LivePreview)

      case ProjectModule.find_module(igniter, preview) do
        {:ok, {igniter, _, _}} ->
          igniter

        {:error, igniter} ->
          Files.create(igniter, module_path(preview), Mix.Brando.Igniter.Site.LivePreview.bare(preview))
      end
    end

    def copy(igniter, {format, source, target}, project) do
      target = target_path(target, project)

      case format do
        :keep -> Files.create(igniter, Path.join(target, ".keep"), "")
        _ -> Files.create(igniter, target, render(format, source, project))
      end
    end

    @doc "A `:copy` or `:eex` template's contents as `copy/3` writes them."
    def render(:copy, source, _project), do: Templates.contents(:copy, source)

    def render(:eex, source, project) do
      contents = EEx.eval_string(Templates.contents(:eex, source), template_binding(project), file: source)
      rename_namespaces(contents, project)
    end

    def template_binding(project) do
      [application_name: to_string(project.otp_app), application_module: inspect(project.app_module)]
    end

    def rename_namespaces(contents, project) do
      contents
      |> String.replace("#{inspect(project.app_module)}Web", inspect(project.web_module))
      |> String.replace("#{inspect(project.app_module)}Admin", inspect(project.admin_module))
    end

    defp target_path(path, project) do
      path
      |> String.replace("application_name_web/villain/parser.ex", "application_name/villain/parser.ex")
      |> String.replace("application_name_admin/live/dashboard_live.ex", "application_name_admin/dashboard_live.ex")
      |> String.replace("application_name_web", Macro.underscore(project.web_module))
      |> String.replace("application_name_admin", Macro.underscore(project.admin_module))
      |> String.replace("application_name", Macro.underscore(project.app_module))
    end

    defp module_path(module), do: "lib/#{Macro.underscore(module)}.ex"

    defp application(igniter, project) do
      igniter
      |> ProjectApplication.add_new_child(Module.concat(project.app_module, Presence), after: fn _ -> true end)
      |> ProjectApplication.add_new_child(Brando, after: fn _ -> true end)
      |> Mix.Brando.Igniter.SourceUpgrade.start_endpoint_last(project.application_module, project.endpoint)
      |> ProjectModule.find_and_update_module!(project.application_module, &initialize/1)
      |> require_supervision()
    end

    # With several sites the admin answers on the endpoint's host only, and its
    # socket takes connections from there only, whatever the endpoint's own
    # `check_origin` accepts for the sites' pages.
    defp admin_socket(:multi) do
      """
      socket "/admin/socket", BrandoAdmin.AdminSocket,
        websocket: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}],
        longpoll: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}]
      """
    end

    defp admin_socket(_tenancy_mode) do
      """
      socket "/admin/socket", BrandoAdmin.AdminSocket, websocket: true, longpoll: true
      """
    end

    # An existing socket line is the application's: a notice says what it lacks
    defp admin_socket_origin_notice(igniter, endpoint, :multi) do
      with {:ok, {igniter, _source, zipper}} <- ProjectModule.find_module(igniter, endpoint),
           {:ok, body} <- Common.move_to_do_block(zipper),
           {:ok, socket} <- Source.find_call(body, :socket, [2, 3], "/admin/socket"),
           false <- admin_host_origin_check?(socket.node) do
        Igniter.add_notice(igniter, """
        With several sites the admin socket takes connections from the endpoint's host only.
        Give `socket "/admin/socket"` in #{inspect(endpoint)} this origin check, on both transports:
            websocket: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}],
            longpoll: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}]
        """)
      else
        _ -> igniter
      end
    end

    defp admin_socket_origin_notice(igniter, _endpoint, _tenancy_mode), do: igniter

    # Whether every transport the socket opens (Phoenix's defaults: websocket
    # on, longpoll off) checks the origin with BrandoAdmin.AdminHost. Options
    # that are not a literal keyword list cannot be read, so they do not.
    defp admin_host_origin_check?(socket) do
      options =
        case socket do
          {_call, _meta, [_path, _module, options]} -> options |> Sourceror.to_string() |> Code.string_to_quoted!()
          _no_options -> []
        end

      Keyword.keyword?(options) and
        Enum.all?([websocket: true, longpoll: false], fn {transport, default} ->
          case Keyword.get(options, transport, default) do
            false ->
              true

            config when is_list(config) ->
              config |> Keyword.get(:check_origin) |> Macro.to_string() =~ "BrandoAdmin.AdminHost"

            _open ->
              false
          end
        end)
    end

    # With several sites an admin LiveView's join and a site's LiveView read
    # the host from the `/live` socket's `:uri` connect info. Each transport's
    # literal `connect_info` list gets it; options the installer cannot read
    # as literals stay as they are, with a notice.
    defp live_socket_uri(igniter, endpoint, :multi) do
      with {:ok, {igniter, _source, zipper}} <- ProjectModule.find_module(igniter, endpoint),
           {:ok, body} <- Common.move_to_do_block(zipper),
           {:ok, socket} <- Source.find_call(body, :socket, [2, 3], "/live"),
           {:ok, transports} <- transports_without_uri(socket.node) do
        if transports == [],
          do: igniter,
          else: ProjectModule.find_and_update_module!(igniter, endpoint, &add_uri(&1, transports))
      else
        _ ->
          Igniter.add_notice(igniter, """
          With several sites the `/live` socket must give its URI, so an admin LiveView refuses a join
          from a socket on a site's host and a site's LiveView finds its site by the real host.
          Add `:uri` to the `connect_info` list of each transport of `socket "/live"` in #{inspect(endpoint)}:
              websocket: [connect_info: [:uri, session: @session_options]],
              longpoll: [connect_info: [:uri, session: @session_options]]
          """)
      end
    end

    defp live_socket_uri(igniter, _endpoint, _tenancy_mode), do: igniter

    # The transports the socket opens whose literal options lack `:uri`, or
    # :error when an open transport's options are not literal lists.
    defp transports_without_uri({_call, _meta, [_path, _module, options]}) do
      options = options |> Sourceror.to_string() |> Code.string_to_quoted!()

      if Keyword.keyword?(options) do
        transports = Keyword.take(options, [:websocket, :longpoll])
        states = Enum.map(transports, fn {_transport, config} -> transport_uri(config) end)

        if :error in states,
          do: :error,
          else: {:ok, for({{transport, _}, :missing} <- Enum.zip(transports, states), do: transport)}
      else
        :error
      end
    end

    defp transports_without_uri(_socket), do: :error

    defp transport_uri(false), do: :ok

    defp transport_uri(config) when is_list(config) do
      with true <- Keyword.keyword?(config),
           {:ok, info} when is_list(info) <- Keyword.fetch(config, :connect_info) do
        if :uri in info, do: :ok, else: :missing
      else
        :error -> :missing
        _ -> :error
      end
    end

    defp transport_uri(_config), do: :error

    defp add_uri(zipper, transports) do
      with {:ok, socket} <- Source.find_call(zipper, :socket, [2, 3], "/live"),
           {:ok, options} <- CodeFunction.move_to_nth_argument(socket, 2) do
        Enum.reduce_while(transports, {:ok, options}, &add_transport_uri/2)
      else
        _ -> {:error, "Could not locate the options of socket \"/live\" to add :uri."}
      end
    end

    defp add_transport_uri(transport, {:ok, options}) do
      case CodeKeyword.set_keyword_key(options, transport, nil, &prepend_uri/1) do
        {:ok, options} -> {:cont, {:ok, options}}
        _ -> {:halt, {:error, "Could not add :uri to the #{transport} connect_info of socket \"/live\"."}}
      end
    end

    defp prepend_uri(config) do
      CodeKeyword.set_keyword_key(config, :connect_info, [:uri], &IgniterList.prepend_new_to_list(&1, :uri))
    end

    defp initialize(zipper) do
      with :error <- CodeFunction.move_to_function_call(zipper, {Brando.System, :initialize}, 0),
           {:ok, start} <- CodeFunction.move_to_def(zipper, :start, 2),
           {:ok, supervisor} <- CodeFunction.move_to_function_call(start, {Supervisor, :start_link}, 2) do
        node = supervisor.node

        {:ok,
         Zipper.replace(
           supervisor,
           quote do
             case unquote(node) do
               {:ok, _pid} = result ->
                 Brando.System.initialize()
                 result

               error ->
                 error
             end
           end
         )}
      else
        {:ok, _} -> {:ok, zipper}
        _ -> {:error, "Could not locate Supervisor.start_link/2 in application start/2 to initialize Brando."}
      end
    end

    defp require_supervision(igniter) do
      # Missing supervision must block installation instead of leaving a broken app.
      {missing, other} = Enum.split_with(igniter.warnings, &String.contains?(&1, "Could not find a `children = [...]`"))
      Enum.reduce(missing, %{igniter | warnings: other}, &Igniter.add_issue(&2, &1))
    end

    defp endpoint(igniter, project, tenancy_mode) do
      endpoint = project.endpoint
      before_router = [before: {:plug, [1, 2], project.router}]

      igniter
      |> Source.ensure_call(endpoint, :socket, [2, 3], "/admin/socket", admin_socket(tenancy_mode), before_router)
      |> admin_socket_origin_notice(endpoint, tenancy_mode)
      |> live_socket_uri(endpoint, tenancy_mode)
      |> Source.ensure_call(
        endpoint,
        :socket,
        [2, 3],
        "/__livepreview/socket",
        BrandoAdmin.LivePreviewSocket.endpoint_line(),
        before_router
      )
      |> Source.ensure_call(endpoint, :plug, [1, 2], Brando.Plug.SiteAssets, "plug Brando.Plug.SiteAssets",
        before: {:plug, [1, 2], Plug.Static}
      )
      |> Source.ensure_call(
        endpoint,
        :plug,
        [1, 2],
        Brando.Plug.Media,
        "plug Brando.Plug.Media, at: \"/media\"",
        before_router
      )
      |> Source.ensure_call(
        endpoint,
        :plug,
        [1, 2],
        Brando.Plug.LivePreview,
        "plug Brando.Plug.LivePreview",
        before_router
      )
      |> Source.ensure_call(
        endpoint,
        :plug,
        [1, 2],
        Brando.Plug.Markdown,
        "plug Brando.Plug.Markdown",
        before_router
      )
      |> Source.ensure_call(
        endpoint,
        :plug,
        [1, 2],
        Brando.Plug.IndexNow,
        "plug Brando.Plug.IndexNow",
        before_router
      )
      |> Source.ensure_call(endpoint, :plug, [1, 2], Brando.Plug.Health, "plug Brando.Plug.Health", before_router)
      |> request_log(endpoint)
    end

    # Phoenix logs each request's path; `Brando.Plug.RequestLog` filters the
    # tokens out of the paths that carry one. A `log:` of the application's
    # own is kept.
    defp request_log(igniter, endpoint) do
      ProjectModule.find_and_update_module!(igniter, endpoint, fn zipper ->
        with {:ok, call} <- Source.find_call(zipper, :plug, [2], Plug.Telemetry),
             {:ok, call} <- CodeFunction.update_nth_argument(call, 1, &put_request_log/1) do
          {:ok, call}
        else
          _ -> {:ok, zipper}
        end
      end)
    end

    defp put_request_log(options),
      do: CodeKeyword.set_keyword_key(options, :log, quote(do: {Brando.Plug.RequestLog, :level, []}))

    defp router(igniter, project) do
      igniter
      |> router_helpers(project)
      |> Source.ensure_call(project.router, :import, [1, 2], Brando.Router, "import Brando.Router", placement: :before)
      |> ProjectModule.find_and_update_module!(project.router, fn zipper ->
        case CodeFunction.move_to_function_call_in_current_scope(zipper, :admin_routes, [1, 2, 3]) do
          {:ok, _} ->
            {:ok, zipper}

          :error ->
            code = """
            admin_routes "/admin", api_pipeline: :brando_api do
              live "/", #{inspect(project.admin_module)}.DashboardLive
            end
            """

            RouteInventory.insert_before_routes(zipper, code)
        end
      end)
    end

    defp router_helpers(igniter, project) do
      ProjectModule.find_and_update_module!(igniter, project.web_module, fn zipper ->
        with {:ok, router} <- CodeFunction.move_to_def(zipper, :router, 0),
             {:ok, use_call} <-
               CodeFunction.move_to_function_call(
                 router,
                 :use,
                 [1, 2],
                 &CodeFunction.argument_equals?(&1, 0, Phoenix.Router)
               ) do
          enable_helpers(use_call)
        else
          _ ->
            {:error,
             "Could not enable Phoenix router helpers in #{inspect(project.web_module)}.router/0. Brando requires named route helpers."}
        end
      end)
    end

    defp enable_helpers(use_call) do
      case CodeFunction.move_to_nth_argument(use_call, 1) do
        {:ok, options} -> CodeKeyword.set_keyword_key(options, :helpers, true, &{:ok, Common.replace_code(&1, "true")})
        :error -> {:ok, use_call}
      end
    end

    defp setup_content(:single), do: "creates the site, with its default content"
    defp setup_content(:multi), do: "seeds no content: sites, with theirs, are created at /admin/sites"
    defp setup_content(_none), do: "seeds default content"

    defp instructions(igniter, tenancy) do
      brando = AgentFiles.package_link(igniter)

      Igniter.add_notice(igniter, """
      Brando source setup prepared (tenancy: #{tenancy.mode}). Review the diff before applying it.
      No database, account, asset build, or deployment was run.

      Next, in this application:
        mix deps.get
        mix compile --warnings-as-errors
        mix brando.setup
        mix phx.server

      mix brando.setup builds assets, creates and migrates the database, prompts
      for a superuser and #{setup_content(tenancy.mode)}. Each step is skipped when its
      result already exists; run the individual tasks instead to control them.

      Review migrations before applying them. Asset setup uses the selected Brando
      checkout's JS via Yalc; pass --source /path/to/matching/brando/assets when
      using an Elixir package without JS sources. No directory layout is assumed.
      Brando's admin is available at /admin.

      For deploying with Florist the plan adds what the release build needs: a Dockerfile
      and .dockerignore when there are none, ReleaseTasks and a release that writes the
      tarball. See Brando's deployment guide (#{brando}/guides/deployment.md).

      For coding agents, AGENTS.md links Brando's usage rules
      (#{brando}/usage-rules.md), and .claude/skills has Brando's site skills.

      #{igniter |> Igniter.Project.Deps.has_dep?(:req_llm) |> ai_instructions(brando) |> String.trim_trailing()}
      #{site_frontend_instructions(tenancy.mode)}\
      """)
    end

    defp site_frontend_instructions(:multi) do
      """

      Each site can render in its own layouts and page templates. Once a site is
      provisioned, generate its frontend: mix brando.gen.site --site KEY
      """
    end

    defp site_frontend_instructions(_mode), do: ""

    # From mix.exs as planned: with --ai, or a req_llm the application had.
    defp ai_instructions(true, brando) do
      """
      AI: mix.exs has the req_llm dependency. Set a model and an API key in
      config :brando, Brando.AI to turn on AI actions, alt text drafts and the
      Assistant (#{brando}/guides/content_assistant.md).
      """
    end

    defp ai_instructions(false, brando) do
      """
      AI (field actions, alt text drafts, the Assistant) needs the req_llm
      dependency, which was not added. To use it later, run
      mix brando.install --ai, or add #{inspect(Brando.AI.dependency())} to deps in mix.exs,
      then set a model and an API key in config :brando, Brando.AI
      (#{brando}/guides/content_assistant.md).
      """
    end
  end
else
  defmodule Mix.Brando.Igniter.Install do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
