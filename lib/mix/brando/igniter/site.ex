if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Site do
    @moduledoc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Config
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.RouteInventory
    alias Mix.Brando.Igniter.Template

    def plan(igniter, project, options) do
      controller = Module.concat(project.web_module, CMS.PageController)
      html = Module.concat(project.web_module, CMS.PageHTML)

      with {:ok, igniter, configured} <- Configuration.read(igniter, :page_html_module),
           :ok <- configured_html(configured, html),
           {:ok, {igniter, _, router}} <- ProjectModule.find_module(igniter, project.router),
           {:ok, state} <- ownership(router, project, controller),
           :ok <- replace_home(state.home?, options) do
        igniter
        |> files(project)
        |> Config.configure_new("brando.exs", :brando, [:page_html_module], html)
        |> routes(project, state, controller)
        |> home_test(project, state)
        |> Igniter.add_notice("""
        CMS pages are prepared under #{inspect(project.web_module)}.CMS.
        The root page and unmatched public paths use published Brando pages.
        Phoenix controllers, templates and layouts remain available in your application.
        No content was created by this plan: mix brando.setup seeds a published
        index page, or create one yourself in /admin/pages with URI index and
        template index.html. Until then / has no page to render.
        """)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp configured_html(nil, _), do: :ok
    defp configured_html(html, html), do: :ok

    defp configured_html(configured, _),
      do:
        {:error,
         "Existing :page_html_module #{inspect(configured)} owns page rendering. Integrate CMS templates explicitly."}

    defp ownership(router, project, controller) do
      routes = RouteInventory.read(router)
      owned = Enum.filter(routes, &(&1.module == controller))
      expected = declarations(controller)
      others = if owned == [], do: routes, else: routes -- expected
      home = %{kind: :get, path: "/", module: Module.concat(project.web_module, PageController), action: :home}
      home? = home in others

      cond do
        not Enum.any?(routes, &(&1.kind == :admin_routes)) ->
          {:error, "Run mix brando.install first, or use mix brando.install --public-site to compose CMS setup."}

        Enum.any?(others -- [home], &conflicting_route?/1) ->
          {:error,
           "Existing public routes own the homepage, a catch-all or a CMS support path. Review/remove those declarations explicitly before generating the CMS site. --replace-phoenix-home only replaces the Phoenix PageController.home route at /."}

        owned != [] &&
            (Enum.sort(owned) != Enum.sort(Enum.take(expected, -2)) || not Enum.all?(expected, &(&1 in routes))) ->
          {:error, "CMS page routes are partially configured or customized. Integrate them explicitly before rerunning."}

        true ->
          {:ok, %{home?: home?, home: home, present?: owned != []}}
      end
    end

    defp conflicting_route?(route) do
      route.kind == :unknown || String.contains?(route.path, "*") ||
        Enum.any?(
          ["/", "/robots.txt", "/__p__/:preview_key", "/__ssg_preview__/:token/*path", "/sitemaps/:file"],
          fn path ->
            RouteInventory.covers?(route, path)
          end
        )
    end

    defp replace_home(false, _), do: :ok

    defp replace_home(true, options) do
      cond do
        options[:replace_phoenix_home] == true ->
          :ok

        options[:replace_phoenix_home] == false ->
          {:error, "The Phoenix homepage was kept. CMS root routing requires --replace-phoenix-home."}

        options[:interactive] ->
          confirm_home()

        true ->
          {:error,
           "Phoenix already owns /. Use --replace-phoenix-home to explicitly replace that route, or keep the current public site. Its controller and templates will be preserved."}
      end
    end

    defp confirm_home do
      case Mix.Brando.prompt("+ Replace the Phoenix homepage route with CMS pages? [y/N]") |> String.downcase() do
        answer when answer in ["y", "yes"] ->
          :ok

        answer when answer in ["", "n", "no"] ->
          {:error, "The Phoenix homepage was kept. No CMS site changes were accepted."}

        _ ->
          {:error, "Expected yes or no for homepage ownership. Supply --replace-phoenix-home for unattended use."}
      end
    rescue
      error in [Mix.Error, ErlangError] -> {:error, Exception.message(error)}
    end

    defp home_test(igniter, _project, %{home?: false}), do: igniter

    defp home_test(igniter, project, _state) do
      path = "test/#{Macro.underscore(project.web_module)}/controllers/page_controller_test.exs"

      if Igniter.exists?(igniter, path) do
        igniter = Igniter.include_existing_file(igniter, path)
        contents = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

        if generated_home_test?(contents, project) do
          igniter
          |> Igniter.rm(path)
          |> Igniter.add_notice("""
          Removed #{path}. It asserted the Phoenix homepage that CMS pages now own.
          Its controller, templates and layouts remain; write request tests against
          published pages when your content setup is in place.
          """)
        else
          Igniter.add_notice(igniter, """
          #{path} was preserved and still expects the replaced Phoenix homepage.
          Update its expectations for CMS pages before running the test suite.
          """)
        end
      else
        igniter
      end
    end

    # Recognizes the unmodified `mix phx.new` homepage request test, which cannot
    # pass once CMS pages own `/`. Customized tests are preserved with a notice.
    defp generated_home_test?(contents, project) do
      case Sourceror.parse_string(contents) do
        {:ok, ast} ->
          {_ast, %{module: module, tests: tests}} =
            Macro.prewalk(ast, %{module: nil, tests: []}, fn
              {:defmodule, _, [{:__aliases__, _, segments} | _]} = node, acc ->
                {node, %{acc | module: acc.module || Module.concat(segments)}}

              # Sourceror wraps literals in :__block__ nodes, so a test name
              # arrives as {:__block__, meta, ["GET /"]} rather than a binary.
              {:test, _, [{:__block__, _, [name]} | _]} = node, acc when is_binary(name) ->
                {node, %{acc | tests: [name | acc.tests]}}

              node, acc ->
                {node, acc}
            end)

          module == Module.concat(project.web_module, PageControllerTest) and
            length(tests) == 1 and String.contains?(contents, ~s(~p"/")) and
            String.contains?(contents, "html_response(conn, 200)")

        _ ->
          false
      end
    end

    defp files(igniter, project) do
      Enum.reduce(
        [
          {"controller.ex", CMS.PageController},
          {"html.ex", CMS.PageHTML},
          {"layouts.ex", CMS.Layouts},
          {"context.ex", CMS.SiteContext}
        ],
        igniter,
        fn {template, suffix}, igniter ->
          path = "lib/#{Macro.underscore(Module.concat(project.web_module, suffix))}.ex"

          case Template.render(igniter, "brando.gen.site", template, web_module: inspect(project.web_module)) do
            {:ok, igniter, source} -> Files.create(igniter, path, source)
            {:error, message} -> Igniter.add_issue(igniter, message)
          end
        end
      )
    end

    defp routes(igniter, project, state, controller) do
      ProjectModule.find_and_update_module!(igniter, project.router, fn router ->
        router
        |> remove_homepage(state)
        |> ensure_site_routes(project, controller, state.present?)
      end)
    end

    defp remove_homepage(router, %{home?: false}), do: router

    defp remove_homepage(router, state) do
      Common.remove_all_matches(router, fn call ->
        CodeFunction.function_call?(call, :get, [3, 4]) && RouteInventory.at(call) == [state.home]
      end)
    end

    defp ensure_site_routes(router, _project, _controller, true), do: {:ok, router}

    defp ensure_site_routes(router, project, controller, false) do
      case CodeFunction.move_to_function_call(router, :pipeline, 2, &CodeFunction.argument_equals?(&1, 0, :brando_site)) do
        :error ->
          {:ok,
           Common.add_code(router, """
           pipeline :brando_site do
             plug #{inspect(project.web_module)}.CMS.SiteContext
           end

           scope "/" do
             pipe_through [:browser, :brando_site]
             get "/robots.txt", Brando.SEOController, :robots
             get "/__p__/:preview_key", Brando.PreviewController, :show
             get "/__ssg_preview__/:token/*path", Brando.SSG.PreviewController, :show
             get "/sitemaps/:file", Brando.SitemapController, :show
             get "/", #{inspect(controller)}, :index, as: :page
             get "/*path", #{inspect(controller)}, :show, as: :page
           end
           """)}

        {:ok, _} ->
          {:error, "An existing :brando_site pipeline requires explicit integration."}
      end
    end

    defp declarations(controller) do
      Enum.map(
        [
          {"/robots.txt", Brando.SEOController, :robots},
          {"/__p__/:preview_key", Brando.PreviewController, :show},
          {"/__ssg_preview__/:token/*path", Brando.SSG.PreviewController, :show},
          {"/sitemaps/:file", Brando.SitemapController, :show},
          {"/", controller, :index},
          {"/*path", controller, :show}
        ],
        fn {path, module, action} ->
          %{kind: :get, path: path, module: module, action: action}
        end
      )
    end
  end
else
  defmodule Mix.Brando.Igniter.Site do
    @moduledoc false
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
