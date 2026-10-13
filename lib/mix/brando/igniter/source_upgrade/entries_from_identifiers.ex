if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.EntriesFromIdentifiers do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # `Brando.Content.get_entries_from_identifiers(identifiers, preloads)`,
    # with a list of preloads, is deprecated for
    # `get_entries_from_identifiers(identifiers, %{preload: preloads})`, and
    # warns, with a stacktrace, on every call. A literal list becomes the
    # map; a call whose second argument is neither is listed.

    alias Igniter.Code.Common
    alias Rewrite.Source
    alias Sourceror.Zipper

    @doc "Rewrites the list form of `get_entries_from_identifiers/2` under `lib/`, and lists the calls it cannot."
    def rewrite(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.ex")

      {igniter, listed} =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
        |> Enum.filter(fn {path, content} ->
          String.starts_with?(path, "lib/") and content =~ "get_entries_from_identifiers"
        end)
        |> Enum.sort()
        |> Enum.reduce({igniter, []}, &rewrite_in/2)

      warning(igniter, listed)
    end

    defp rewrite_in({path, content}, {igniter, listed}) do
      case Sourceror.parse_string(content) do
        {:ok, ast} ->
          calls = ast |> statements() |> walk(%{}, [])
          rewrite = for {line, :list, :brando} <- calls, do: line

          unsure =
            for {line, form, receiver} <- calls,
                (receiver == :brando and form == :unknown) or (receiver == :unsure and form in [:list, :unknown]),
                do: "#{path}:#{line}"

          igniter =
            if rewrite == [],
              do: igniter,
              else: Igniter.update_elixir_file(igniter, path, &rewrite_calls(&1, rewrite))

          {igniter, listed ++ unsure}

        _error ->
          {igniter, listed}
      end
    end

    defp statements({:__block__, _, statements}) when is_list(statements), do: statements
    defp statements(statement), do: [statement]

    # `{line, :list | :map | :unknown, :brando | :unsure}` for each call to a
    # `get_entries_from_identifiers/2` that may be Brando.Content's, read in
    # order with the aliases in reach where it stands.
    defp walk(statements, aliases, calls) do
      {_aliases, calls} =
        Enum.reduce(statements, {aliases, calls}, fn
          {:alias, _, _} = statement, {aliases, calls} -> {declare_alias(statement, aliases), calls}
          statement, {aliases, calls} -> {aliases, collect(statement, aliases, calls)}
        end)

      calls
    end

    defp collect(ast, aliases, calls) do
      {_ast, calls} =
        Macro.prewalk(ast, calls, fn
          {:defmodule, _, [_name, [{_do, body}]]}, calls ->
            {:skipped, walk(statements(body), aliases, calls)}

          {:|>, _, [identifiers, {_call, meta, [preloads]} = call]} = node, calls ->
            case receiver(call, aliases) do
              nil -> {node, calls}
              receiver -> {identifiers, calls ++ [{meta[:line], form(preloads), receiver}]}
            end

          {_call, meta, [_identifiers, preloads]} = node, calls ->
            case receiver(node, aliases) do
              nil -> {node, calls}
              receiver -> {node, calls ++ [{meta[:line], form(preloads), receiver}]}
            end

          node, calls ->
            {node, calls}
        end)

      calls
    end

    # `:brando` for Brando.Content's function, `:unsure` when an alias in the
    # way cannot be read, nil for any other.
    defp receiver({{:., _, [{:__aliases__, _, [first | rest]}, :get_entries_from_identifiers]}, _, _args}, aliases) do
      case Map.get(aliases, first, [first]) do
        :unknown -> :unsure
        base -> if base ++ rest == [:Brando, :Content], do: :brando
      end
    end

    defp receiver(_node, _aliases), do: nil

    defp declare_alias({:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]}, aliases) do
      Enum.reduce(children, aliases, fn
        {:__aliases__, _, parts}, aliases -> Map.put(aliases, List.last(parts), expand(base ++ parts, aliases))
        _child, aliases -> aliases
      end)
    end

    defp declare_alias({:alias, _, [{:__aliases__, _, parts} | options]}, aliases) do
      as =
        Enum.find_value(List.flatten(options), fn
          {key, {:__aliases__, _, [as]}} -> if unwrap(key) == :as, do: as
          _option -> nil
        end)

      Map.put(aliases, as || List.last(parts), expand(parts, aliases))
    end

    defp declare_alias(_statement, aliases), do: aliases

    defp expand([first | rest] = parts, aliases) do
      cond do
        not Enum.all?(parts, &is_atom/1) -> :unknown
        Map.get(aliases, first) == :unknown -> :unknown
        Map.has_key?(aliases, first) -> aliases[first] ++ rest
        true -> parts
      end
    end

    defp unwrap({:__block__, _, [value]}), do: value
    defp unwrap(value), do: value

    defp rewrite_calls(zipper, lines) do
      Common.update_all_matches(zipper, &rewritten?(Zipper.node(&1), lines), fn zipper ->
        {:ok, Zipper.update(zipper, &with_preload_map/1)}
      end)
    end

    defp rewritten?({:|>, _, [_identifiers, {_call, meta, [preloads]} = call]}, lines),
      do: meta[:line] in lines and form(preloads) == :list and content_call?(call)

    defp rewritten?({_call, meta, [_identifiers, preloads]} = call, lines),
      do: meta[:line] in lines and form(preloads) == :list and content_call?(call)

    defp rewritten?(_node, _lines), do: false

    defp content_call?({{:., _, [{:__aliases__, _, _receiver}, :get_entries_from_identifiers]}, _, _args}), do: true
    defp content_call?(_node), do: false

    defp form({:__block__, _, [list]}) when is_list(list), do: :list
    defp form({:%{}, _, _}), do: :map
    defp form(nil), do: nil
    defp form(_preloads), do: :unknown

    defp with_preload_map({:|>, meta, [identifiers, {call, call_meta, [preloads]}]}),
      do: {:|>, meta, [identifiers, {call, call_meta, [preload_map(preloads)]}]}

    defp with_preload_map({call, meta, [identifiers, preloads]}), do: {call, meta, [identifiers, preload_map(preloads)]}

    defp preload_map(preloads), do: {:%{}, [], [{{:__block__, [format: :keyword], [:preload]}, preloads}]}

    defp warning(igniter, []), do: igniter

    defp warning(igniter, listed) do
      Igniter.add_warning(igniter, """
      These calls to `Brando.Content.get_entries_from_identifiers/2` may pass
      their preloads as a list, which is deprecated (and warns, with a
      stacktrace, on every call). Pass them as options:
      `get_entries_from_identifiers(identifiers, %{preload: preloads})`.

      #{Enum.map_join(listed, "\n", &"  #{&1}")}
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.EntriesFromIdentifiers do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
