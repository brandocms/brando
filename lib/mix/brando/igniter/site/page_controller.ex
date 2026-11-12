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
    site's frontend gets the plug and the page assigns; any other existing one
    must be the template (`Mix.Brando.Igniter.Files.create/3`).
    """
    def plan(igniter, project) do
      with_generated(igniter, project, fn igniter, generated ->
        case find(igniter, project) do
          {:ok, igniter, source} -> plan_existing(igniter, project, source, generated)
          {:error, igniter} -> Files.create(igniter, path(project), generated)
        end
      end)
    end

    defp plan_existing(igniter, project, source, generated) do
      current = Source.get(source, :content)

      if same_code?(current, previous(generated)) and not same_code?(current, generated),
        do: igniter |> add_frontend(project, source, generated) |> elem(0),
        else: Files.create(igniter, Source.get(source, :path), generated)
    end

    @doc """
    Makes sure the existing page controller renders the site's frontend: one
    with the plug and the page assigns is kept; one generated before them gets
    them; any other is kept with a notice of the steps to take by hand.
    Returns `{igniter, renders_frontend?}`.
    """
    def ensure_frontend(igniter, project) do
      with {:ok, igniter, generated} <- generated(igniter, project),
           {:ok, igniter, source} <- find(igniter, project) do
        ensure_existing(igniter, project, source, generated)
      else
        {:error, igniter} -> {igniter, false}
      end
    end

    defp ensure_existing(igniter, project, source, generated) do
      current = Source.get(source, :content)

      cond do
        renders_frontend?(current) ->
          {igniter, true}

        renders_frontend?(generated) and same_code?(current, previous(generated)) ->
          add_frontend(igniter, project, source, generated)

        true ->
          {steps_notice(igniter, project, Source.get(source, :path)), false}
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
      case generated(igniter, project) do
        {:ok, igniter, generated} -> fun.(igniter, generated)
        {:error, igniter} -> igniter
      end
    end

    defp generated(igniter, project) do
      case Template.render(igniter, "brando.gen.site", @template, web_module: inspect(project.web_module)) do
        {:ok, igniter, generated} -> {:ok, igniter, generated}
        {:error, message} -> {:error, Igniter.add_issue(igniter, message)}
      end
    end

    defp previous(generated), do: Enum.reduce(@frontend_lines, generated, &String.replace(&2, &1, ""))

    # Inserts the plug and the page assigns into the controller's own text, so
    # that its comments and layout stay.
    defp add_frontend(igniter, project, source, generated) do
      path = Source.get(source, :path)

      case insert_frontend(Source.get(source, :content)) do
        {:ok, contents} ->
          if same_code?(contents, generated),
            do: {Igniter.update_file(igniter, path, &Source.update(&1, :content, contents)), true},
            else: {steps_notice(igniter, project, path), false}

        :error ->
          {steps_notice(igniter, project, path), false}
      end
    end

    defp insert_frontend(contents) do
      lines = String.split(contents, ~r/(?<=\n)/)

      {_, {plug_lines, render_lines}} =
        contents
        |> Sourceror.parse_string!()
        |> Macro.prewalk({[], []}, fn
          {:plug, _, [_ | _]} = node, {plugs, renders} ->
            range = Sourceror.get_range(node)
            {node, {[{range.start[:line], range.end[:line]} | plugs], renders}}

          {:|>, _, [_, {:render, meta, _}]} = node, {plugs, renders} ->
            {node, {plugs, [meta[:line] | renders]}}

          node, acc ->
            {node, acc}
        end)

      with {start, finish} <- Enum.max_by(plug_lines, &elem(&1, 1), fn -> nil end),
           [_, indent, paren] <- Regex.run(~r/^([ \t]*)plug(\(?)/, Enum.at(lines, start - 1)),
           {:ok, renders} <- render_insertions(lines, render_lines) do
        plug = if paren == "(", do: "plug(Brando.Plug.SiteFrontend)", else: "plug Brando.Plug.SiteFrontend"

        [{finish, "#{indent}#{plug}\n"} | renders]
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.reduce(lines, fn {at, line}, lines -> List.insert_at(lines, at, line) end)
        |> Enum.join()
        |> then(&{:ok, &1})
      else
        _ -> :error
      end
    end

    # The generated controller renders in two pipelines, index's and show's.
    defp render_insertions(lines, [_, _] = render_lines) do
      Enum.reduce_while(render_lines, {:ok, []}, fn line, {:ok, acc} ->
        case Regex.run(~r/^([ \t]*)\|> render\(/, Enum.at(lines, line - 1)) do
          [_, indent] -> {:cont, {:ok, [{line - 1, "#{indent}|> Brando.Site.Frontend.put_page_assigns(page)\n"} | acc]}}
          nil -> {:halt, :error}
        end
      end)
    end

    defp render_insertions(_lines, _render_lines), do: :error

    defp same_code?(left, right), do: ErrorPages.same_code?(left, right)

    defp renders_frontend?(contents) do
      with {:ok, ast} <- Sourceror.parse_string(contents),
           {:ok, _} <-
             ast
             |> Sourceror.Zipper.zip()
             |> CodeFunction.move_to_function_call(
               :plug,
               # `view: false` keeps the controller's own view: not the site's templates
               1,
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
