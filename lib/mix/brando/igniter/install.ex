if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Igniter.Project.Application, as: ProjectApplication
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.AgentFiles
    alias Mix.Brando.Igniter.Assets
    alias Mix.Brando.Igniter.Dependencies
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Install.Deployment
    alias Mix.Brando.Igniter.Install.Docker
    alias Mix.Brando.Igniter.Install.Version
    alias Mix.Brando.Igniter.Project
    alias Mix.Brando.Igniter.Release
    alias Mix.Brando.Igniter.RouteInventory
    alias Mix.Brando.Igniter.Source
    alias Mix.Brando.Install.Hosts
    alias Mix.Brando.Install.Options
    alias Mix.Brando.Install.Templates
    alias Sourceror.Zipper

    @support_templates ~w(
      lib/application_name/tuple.ex
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
           {:ok, igniter} <- preflight(igniter, project),
           {:ok, igniter} <- Mix.Brando.Igniter.Install.Migrations.preflight(igniter),
           {:ok, igniter, existing} <- Configuration.existing_tenancy(igniter),
           {:ok, tenancy} <- resolve_tenancy(options, existing, project),
           {igniter, deployment} = Deployment.existing(igniter),
           {:ok, hosts} <- resolve_hosts(options, project, deployment) do
        igniter
        |> Configuration.configure(project, tenancy)
        |> dependencies()
        |> Version.plan()
        |> Deployment.plan(project, hosts, deployment)
        |> Docker.plan(project)
        |> Release.plan(project, existing: :keep)
        |> support_files(project)
        |> AgentFiles.plan()
        |> Assets.plan(project)
        |> Mix.Brando.Igniter.Install.Migrations.plan(project)
        |> application(project)
        |> endpoint(project)
        |> router(project)
        |> public_site(project, options)
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
      if options[:replace_phoenix_home] && !options[:public_site],
        do: {:error, "--replace-phoenix-home requires --public-site."},
        else: :ok
    end

    defp public_site(igniter, project, options) do
      if options[:public_site], do: Mix.Brando.Igniter.Site.plan(igniter, project, options), else: igniter
    end

    defp preflight(igniter, project) do
      {:ok, {igniter, _, router}} = ProjectModule.find_module(igniter, project.router)
      routes = RouteInventory.read(router)

      cond do
        Enum.any?(routes, &(&1.kind == :admin_routes)) ->
          {:ok, igniter}

        Enum.any?(routes, &(&1.kind == :unknown || &1.path == "/admin" || String.starts_with?(&1.path, "/admin/"))) ->
          {:error,
           "The router already owns /admin routes or uses dynamic paths. Review that ownership and integrate Brando's admin_routes block explicitly before installing; existing routes cannot be silently shadowed."}

        true ->
          {:ok, igniter}
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

    defp dependencies(igniter) do
      # Preserve the user's package/git/path selection, including local Brando.
      Enum.reduce([{:gettext, "~> 1.0"}, {:jason, "~> 1.0"}], igniter, fn dep, igniter ->
        Dependencies.add_new(igniter, dep)
      end)
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
        :keep ->
          Files.create(igniter, Path.join(target, ".keep"), "")

        :copy ->
          Files.create(igniter, target, Templates.contents(:copy, source))

        :eex ->
          contents = EEx.eval_string(Templates.contents(:eex, source), template_binding(project), file: source)
          Files.create(igniter, target, rename_namespaces(contents, project))
      end
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

    defp endpoint(igniter, project) do
      endpoint = project.endpoint
      before_router = [before: {:plug, [1, 2], project.router}]

      igniter
      |> Source.ensure_call(
        endpoint,
        :socket,
        [2, 3],
        "/admin/socket",
        """
        socket "/admin/socket", BrandoAdmin.AdminSocket, websocket: true, longpoll: true
        """,
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
    end

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

    defp instructions(igniter, tenancy) do
      Igniter.add_notice(igniter, """
      Brando source setup prepared (tenancy: #{tenancy.mode}). Review the diff before applying it.
      No database, account, asset build, or deployment was run.

      Next, in this application:
        mix deps.get
        mix compile --warnings-as-errors
        mix brando.setup
        mix phx.server

      mix brando.setup builds assets, creates and migrates the database, prompts
      for a superuser and seeds default content. Each step is skipped when its
      result already exists; run the individual tasks instead to control them.

      Review migrations before applying them. Asset setup uses the selected Brando
      checkout's JS via Yalc; pass --source /path/to/matching/brando/assets when
      using an Elixir package without JS sources. No directory layout is assumed.
      For single/multi tenancy, provision a site/environment after public migrations;
      see the tenancy guide before initializing tenant content.
      Brando's admin is available at /admin.

      For deploying with Florist the plan adds what the release build needs: a Dockerfile
      and .dockerignore when there are none, ReleaseTasks and a release that writes the
      tarball. See Brando's deployment guide (deps/brando/guides/deployment.md).

      For coding agents, AGENTS.md links Brando's usage rules
      (deps/brando/usage-rules.md), and .claude/skills has Brando's site skills.
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.Install do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
