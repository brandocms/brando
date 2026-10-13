if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.RedundantComponentUse do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # 0.53 HTML modules often say `use BrandoWeb, :html` and then
    # `use Phoenix.Component`, which the first already does. Elixir 1.20 warns
    # about the second (`redundant clause __phoenix_component_verify__`), so
    # `--warnings-as-errors` fails. A bare `use Phoenix.Component` in a module
    # whose `use MyWeb, :kind` brings it in (BrandoWeb's `:html`, or a `def
    # kind` of the application's web module that uses Phoenix.Component,
    # LiveView or LiveComponent) is removed and listed.

    alias Igniter.Project.Module, as: ProjectModule
    alias Rewrite.Source
    alias Sourceror.Zipper

    @components [:Component, :LiveView, :LiveComponent]

    @doc "Removes the redundant `use Phoenix.Component` lines under `lib/` and lists them."
    def remove(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.ex")

      {igniter, removed} =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
        |> Enum.filter(fn {path, content} -> String.starts_with?(path, "lib/") and content =~ "use Phoenix.Component" end)
        |> Enum.sort()
        |> Enum.reduce({igniter, []}, &remove_in/2)

      notice(igniter, removed)
    end

    defp remove_in({path, content}, {igniter, removed}) do
      with {:ok, ast} <- Sourceror.parse_string(content),
           {igniter, [_ | _] = lines} <- redundant_lines(igniter, ast) do
        # The lines go as text, so the rest of the file keeps its formatting.
        igniter = Igniter.update_file(igniter, path, &Source.update(&1, :content, without_lines(content, lines)))

        {igniter, removed ++ Enum.map(lines, &"#{path}:#{&1}")}
      else
        _ -> {igniter, removed}
      end
    end

    # The lines of a bare `use Phoenix.Component` in a module whose other
    # `use` already brings it in.
    defp redundant_lines(igniter, ast) do
      {_ast, modules} =
        Macro.prewalk(ast, [], fn
          {:defmodule, _, [_name, [{_do, body}]]} = node, modules -> {node, [statements(body) | modules]}
          node, modules -> {node, modules}
        end)

      Enum.reduce(modules, {igniter, []}, fn statements, {igniter, lines} ->
        {igniter, brings?} = brings_component?(igniter, statements)
        found = for statement <- statements, brings?, bare_component_use?(statement), do: Sourceror.get_line(statement)
        {igniter, lines ++ found}
      end)
    end

    defp statements({:__block__, _, statements}) when is_list(statements), do: statements
    defp statements(statement), do: [statement]

    defp brings_component?(igniter, statements) do
      Enum.reduce(statements, {igniter, false}, fn
        _statement, {igniter, true} ->
          {igniter, true}

        {:use, _, [{:__aliases__, _, parts}, kind]}, {igniter, false} ->
          kind_brings_component?(igniter, Module.concat(parts), unwrap(kind))

        _statement, acc ->
          acc
      end)
    end

    defp kind_brings_component?(igniter, BrandoWeb, :html), do: {igniter, true}

    defp kind_brings_component?(igniter, web, kind) when is_atom(kind) do
      case ProjectModule.find_module(igniter, web) do
        {:ok, {igniter, _source, zipper}} -> {igniter, defines_component_kind?(Zipper.node(zipper), kind)}
        {:error, igniter} -> {igniter, false}
      end
    end

    defp kind_brings_component?(igniter, _web, _kind), do: {igniter, false}

    defp defines_component_kind?(ast, kind) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:def, _, [{^kind, _, args}, [{_do, body}]]} = node, found when args in [nil, []] ->
            {node, found or uses_component?(body)}

          node, found ->
            {node, found}
        end)

      found
    end

    defp uses_component?(body) do
      {_body, found} =
        Macro.prewalk(body, false, fn
          {:use, _, [{:__aliases__, _, [:Phoenix, name]} | _]} = node, found -> {node, found or name in @components}
          node, found -> {node, found}
        end)

      found
    end

    defp bare_component_use?({:use, _, [{:__aliases__, _, [:Phoenix, :Component]}]}), do: true
    defp bare_component_use?(_node), do: false

    defp without_lines(content, lines) do
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reject(fn {line, number} -> number in lines and String.trim(line) == "use Phoenix.Component" end)
      |> Enum.map_join("\n", &elem(&1, 0))
    end

    defp unwrap({:__block__, _, [value]}), do: value
    defp unwrap(value), do: value

    defp notice(igniter, []), do: igniter

    defp notice(igniter, removed) do
      Igniter.add_notice(igniter, """
      Removed `use Phoenix.Component` from modules whose `use MyAppWeb, :html`
      (or BrandoWeb's) already brings it in; Elixir 1.20 warns about the second
      one, which fails `--warnings-as-errors`:

      #{Enum.map_join(removed, "\n", &"  #{&1}: use Phoenix.Component")}
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.RedundantComponentUse do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
