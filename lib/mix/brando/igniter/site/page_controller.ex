if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Site.PageController do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Site.ErrorPages
    alias Mix.Brando.Igniter.Template
    alias Rewrite.Source

    @template "controller.ex"

    # The lines the template gained for Brando.Site.Frontend: without them it is
    # the controller this task wrote before.
    @frontend_lines [
      ~r/^[ \t]*plug Brando\.Plug\.SiteFrontend\n/m,
      ~r/^[ \t]*\|> Brando\.Site\.Frontend\.put_page_assigns\(page\)\n/m
    ]

    @doc """
    Plans `Web.CMS.PageController`. One as generated before it rendered the
    site's frontend becomes the current template; any other existing one must
    be the template (`Mix.Brando.Igniter.Files.create/3`).
    """
    def plan(igniter, project) do
      with_generated(igniter, project, fn igniter, generated ->
        case find(igniter, project) do
          {:ok, igniter, source} -> plan_existing(igniter, source, generated)
          {:error, igniter} -> Files.create(igniter, path(project), generated)
        end
      end)
    end

    defp plan_existing(igniter, source, generated) do
      if same_code?(Source.get(source, :content), previous(generated)),
        do: replace(igniter, source, generated),
        else: Files.create(igniter, Source.get(source, :path), generated)
    end

    @doc """
    Makes sure the existing page controller renders the site's frontend: one
    as generated, now or before, gets the template; one with the plug and the
    page assigns is kept; any other is kept with a notice of the steps to take
    by hand.
    """
    def ensure_frontend(igniter, project) do
      with_generated(igniter, project, fn igniter, generated ->
        case find(igniter, project) do
          {:ok, igniter, source} -> ensure_existing(igniter, project, source, generated)
          {:error, igniter} -> igniter
        end
      end)
    end

    defp ensure_existing(igniter, project, source, generated) do
      current = Source.get(source, :content)

      cond do
        same_code?(current, generated) -> igniter
        same_code?(current, previous(generated)) -> replace(igniter, source, generated)
        renders_frontend?(current) -> igniter
        true -> steps_notice(igniter, project, Source.get(source, :path))
      end
    end

    @doc "The page controller module, `Web.CMS.PageController`."
    def module(project), do: Module.concat(project.web_module, CMS.PageController)

    defp path(project), do: "lib/#{Macro.underscore(module(project))}.ex"

    defp find(igniter, project) do
      case ProjectModule.find_module(igniter, module(project)) do
        {:ok, {igniter, source, _zipper}} -> {:ok, igniter, source}
        {:error, igniter} -> {:error, igniter}
      end
    end

    defp with_generated(igniter, project, fun) do
      case Template.render(igniter, "brando.gen.site", @template, web_module: inspect(project.web_module)) do
        {:ok, igniter, generated} -> fun.(igniter, generated)
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp previous(generated), do: Enum.reduce(@frontend_lines, generated, &String.replace(&2, &1, ""))

    defp replace(igniter, source, generated),
      do: Igniter.update_file(igniter, Source.get(source, :path), &Source.update(&1, :content, generated))

    defp same_code?(left, right), do: ErrorPages.same_code?(left, right)

    defp renders_frontend?(contents) do
      with {:ok, ast} <- Sourceror.parse_string(contents),
           {:ok, _} <-
             ast
             |> Sourceror.Zipper.zip()
             |> CodeFunction.move_to_function_call(
               :plug,
               [1, 2],
               &CodeFunction.argument_equals?(&1, 0, Brando.Plug.SiteFrontend)
             ) do
        String.contains?(contents, "put_page_assigns(")
      else
        _ -> false
      end
    end

    defp steps_notice(igniter, project, path) do
      Igniter.add_notice(igniter, """
      #{path} is customized, so it was left as it is. To render each site with its frontend:

        1. Add `plug Brando.Plug.SiteFrontend` to #{inspect(module(project))} as its last plug,
           after its put_view, put_layout and put_root_layout plugs.
        2. In index and show, call `Brando.Site.Frontend.put_page_assigns(conn, page)` after
           assigning the page and before rendering it.
        3. In any other controller that renders in the site's layout, add
           `plug Brando.Plug.SiteFrontend, view: false` as its last plug.

      See "Per-site layouts and templates" in the tenancy guide.
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.Site.PageController do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
