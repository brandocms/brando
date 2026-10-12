if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.ViewHelpers do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # phoenix_html 4 raises on `use Phoenix.HTML`, so the first compile of a
    # site generated before Phoenix 1.7 stops in its `<App>Web.ErrorHelpers`
    # or the `view_helpers/0` of `<App>Web`. When nothing outside them uses
    # `use <App>Web, :view`, `<App>Web.view` or `ErrorHelpers`, the three are
    # Phoenix.View leftovers and are deleted. Otherwise their
    # `use Phoenix.HTML` becomes what it used to bring in:
    # `import Phoenix.HTML`, `import Phoenix.HTML.Form` and
    # `use PhoenixHTMLHelpers` (the `phoenix_html_helpers` package).

    alias Igniter.Code.Common
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Source, as: IgniterSource
    alias Rewrite.Source
    alias Sourceror.Zipper

    @use_phoenix_html ~r/^([ \t]*)use Phoenix\.HTML[ \t]*$/m
    @replacement "\\1import Phoenix.HTML\n\\1import Phoenix.HTML.Form\n\\1use PhoenixHTMLHelpers"

    def upgrade(igniter) do
      igniter = Igniter.include_glob(igniter, "{lib,test}/**/*.{ex,exs,heex,eex,leex}")
      web = Igniter.Libs.Phoenix.web_module(igniter)
      {igniter, web_path} = module_path(igniter, web)
      {igniter, helpers_path} = module_path(igniter, Module.concat(web, ErrorHelpers))

      targets = Enum.reject([web_path, helpers_path], &is_nil/1)

      if Enum.any?(targets, &(content(igniter, &1) =~ @use_phoenix_html)) do
        upgrade(igniter, web, web_path, helpers_path)
      else
        warn_other_uses(igniter, [])
      end
    end

    defp upgrade(igniter, web, web_path, helpers_path) do
      paths = Enum.uniq(Enum.reject([web_path, helpers_path], &is_nil/1))

      case references(igniter, web, web_path, helpers_path) ++ shared_file(igniter, web_path, helpers_path) do
        [] ->
          igniter
          |> remove_helpers(helpers_path)
          |> remove_view(web_path)
          |> removed_notice(web, web_path, helpers_path)
          |> warn_other_uses(Enum.reject([helpers_path], &is_nil/1))

        references ->
          igniter
          |> replace_uses(paths, references)
          |> warn_other_uses([])
      end
    end

    defp removed_notice(igniter, web, web_path, helpers_path) do
      removed =
        Enum.reject(
          [
            helpers_path && "  #{helpers_path} (#{inspect(Module.concat(web, ErrorHelpers))})",
            web_path && "  #{web_path}: `view/0` and `view_helpers/0`"
          ],
          &is_nil/1
        )

      Igniter.add_notice(igniter, """
      Removed the Phoenix.View-era view helpers nothing used, which phoenix_html 4
      no longer compiles (`use Phoenix.HTML`):

      #{Enum.join(removed, "\n")}
      """)
    end

    defp module_path(_igniter, nil), do: {nil, nil}

    defp module_path(igniter, module) do
      case ProjectModule.find_module(igniter, module) do
        {:ok, {igniter, source, _zipper}} -> {igniter, Source.get(source, :path)}
        {:error, igniter} -> {igniter, nil}
      end
    end

    defp content(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)

    ## References

    # The helpers are deleted with their file, so they need one of their own.
    defp shared_file(_igniter, _web_path, nil), do: []

    defp shared_file(igniter, web_path, helpers_path) do
      if helpers_path == web_path or length(Regex.scan(~r/^\s*defmodule\s/m, content(igniter, helpers_path))) > 1,
        do: ["#{helpers_path}: defines other modules too, so the task does not delete it"],
        else: []
    end

    # Uses of the view or the helpers outside `view/0`, `view_helpers/0` and
    # the ErrorHelpers module, templates included, as `path:line: text` for
    # the line each starts on. A use may span lines (`use MyAppWeb,\n :view`),
    # and any alias of the web module counts, since `use Web, :view` through
    # it cannot be told apart.
    defp references(igniter, web, web_path, helpers_path) do
      name = Regex.escape(inspect(web))

      pattern =
        ~r/\b#{name}\s*,\s*:view\b|\b#{name}\.view\b|\bErrorHelpers\b|\bview_helpers\b|\balias\s+#{name}\s*(?:,|$)/m

      for {path, content} <- IgniterSource.project_sources(igniter),
          path != helpers_path,
          lines = code_lines(path, content, web_path),
          code = Enum.join(lines, "\n"),
          [{start, _length}] <-
            Regex.scan(pattern, code, return: :index, capture: :first) ++ local_view(path, web_path, code),
          number = line_number(code, start),
          do: "#{path}:#{number}: #{lines |> Enum.at(number - 1) |> String.trim()}"
    end

    defp local_view(web_path, web_path, code), do: Regex.scan(~r/\bview\(\)/, code, return: :index)
    defp local_view(_path, _web_path, _code), do: []

    defp line_number(code, offset), do: code |> binary_part(0, offset) |> String.split("\n") |> length()

    # `<App>Web` itself counts without the view functions and its moduledoc
    # (`use MyAppWeb, :view` there is an example). Their lines are blanked so
    # the rest keep their numbers.
    defp code_lines(web_path, content, web_path) do
      {:ok, ast} = Sourceror.parse_string(content)
      ranges = view_ranges(ast)

      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map(fn {line, number} -> if Enum.any?(ranges, &(number in &1)), do: "", else: line end)
    end

    defp code_lines(_path, content, _web_path), do: String.split(content, "\n")

    defp view_ranges(ast) do
      ast
      |> Zipper.zip()
      |> Common.find_all(&(view_definition?(&1) or moduledoc?(&1)))
      |> Enum.map(fn zipper ->
        %{start: start, end: finish} = zipper |> Zipper.node() |> Sourceror.get_range()
        start[:line]..finish[:line]
      end)
    end

    defp view_definition?(zipper) do
      match?(
        {kind, _, [{name, _, args}, _body]}
        when kind in [:def, :defp] and name in [:view, :view_helpers] and args in [nil, []],
        Zipper.node(zipper)
      )
    end

    defp moduledoc?(zipper), do: match?({:@, _, [{:moduledoc, _, _}]}, Zipper.node(zipper))

    ## Removal

    defp remove_helpers(igniter, nil), do: igniter
    defp remove_helpers(igniter, path), do: Igniter.rm(igniter, path)

    defp remove_view(igniter, nil), do: igniter

    defp remove_view(igniter, path) do
      Igniter.update_elixir_file(igniter, path, fn zipper ->
        zipper
        |> Common.remove_all_matches(&view_definition?/1)
        |> Common.update_all_matches(&moduledoc?/1, &without_view_example/1)
      end)
    end

    defp without_view_example(zipper) do
      zipper
      |> Zipper.update(fn
        {:@, meta, [{:moduledoc, doc_meta, [{:__block__, string_meta, [doc]}]}]} when is_binary(doc) ->
          doc = Regex.replace(~r/^[ \t]*use [\w.]+,\s*:view[ \t]*\n/m, doc, "")
          {:@, meta, [{:moduledoc, doc_meta, [{:__block__, string_meta, [doc]}]}]}

        node ->
          node
      end)
      |> then(&{:ok, &1})
    end

    ## Replacement

    defp replace_uses(igniter, paths, references) do
      rewritten =
        for path <- paths,
            {line, number} <- igniter |> content(path) |> String.split("\n") |> Enum.with_index(1),
            line =~ @use_phoenix_html,
            do: "#{path}:#{number}"

      igniter =
        Enum.reduce(paths, igniter, fn path, igniter ->
          Igniter.update_file(
            igniter,
            path,
            &Source.update(&1, :content, Regex.replace(@use_phoenix_html, Source.get(&1, :content), @replacement))
          )
        end)

      Igniter.add_warning(igniter, """
      phoenix_html 4 no longer supports `use Phoenix.HTML`. The view helpers that
      used it are still in use, so the task replaced it with `import Phoenix.HTML`,
      `import Phoenix.HTML.Form` and `use PhoenixHTMLHelpers` at:

      #{Enum.map_join(rewritten, "\n", &"  #{&1}")}

      #{dependency_note(igniter)} (`PhoenixHTMLHelpers` keeps `content_tag/3`,
      `link/2` and the form input helpers). Delete the helpers instead once these
      stop using them:

      #{Enum.map_join(references, "\n", &"  #{&1}")}
      """)
    end

    defp dependency_note(igniter) do
      if Igniter.Project.Deps.has_dep?(igniter, :phoenix_html_helpers),
        do: "`mix.exs` already depends on `phoenix_html_helpers`",
        else: "Add `{:phoenix_html_helpers, \"~> 1.0\"}` to the dependencies in `mix.exs`"
    end

    defp warn_other_uses(igniter, removed) do
      findings =
        for {path, content} <- IgniterSource.project_sources(igniter),
            String.starts_with?(path, "lib/"),
            path not in removed,
            {line, number} <- content |> String.split("\n") |> Enum.with_index(1),
            line =~ @use_phoenix_html,
            do: "  #{path}:#{number}"

      case findings do
        [] ->
          igniter

        findings ->
          Igniter.add_warning(igniter, """
          phoenix_html 4 raises on `use Phoenix.HTML`. Replace it with what the
          module uses: `import Phoenix.HTML`, `import Phoenix.HTML.Form`, or
          `use PhoenixHTMLHelpers` with the `{:phoenix_html_helpers, "~> 1.0"}`
          dependency for `content_tag/3`, `link/2` and the input helpers:

          #{Enum.join(findings, "\n")}
          """)
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.ViewHelpers do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
