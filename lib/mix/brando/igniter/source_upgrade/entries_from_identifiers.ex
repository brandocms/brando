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
      content_alias? = content =~ ~r/\balias Brando\.Content\b(?!\.)(?!\s*,\s*as:)/

      case Sourceror.parse_string(content) do
        {:ok, ast} ->
          calls = calls(ast, content_alias?)
          unknown = for {line, :unknown} <- calls, do: "#{path}:#{line}"

          igniter =
            if Enum.any?(calls, &match?({_line, :list}, &1)),
              do: Igniter.update_elixir_file(igniter, path, &rewrite_calls(&1, content_alias?)),
              else: igniter

          {igniter, listed ++ unknown}

        _error ->
          {igniter, listed}
      end
    end

    # `{line, :list | :map | :unknown}` for each call, by its preloads.
    defp calls(ast, content_alias?) do
      {_ast, calls} =
        Macro.prewalk(ast, [], fn node, calls ->
          case preloads(node, content_alias?) do
            nil -> {node, calls}
            preloads -> {node, calls ++ [{Sourceror.get_line(node), form(preloads)}]}
          end
        end)

      calls
    end

    defp rewrite_calls(zipper, content_alias?) do
      Common.update_all_matches(zipper, &(form(preloads(Zipper.node(&1), content_alias?)) == :list), fn zipper ->
        {:ok, Zipper.update(zipper, &with_preload_map/1)}
      end)
    end

    # The preloads argument of a call to `Brando.Content.get_entries_from_identifiers/2`.
    defp preloads({:|>, _, [_identifiers, call]}, content_alias?) do
      with {_call, _meta, [preloads]} <- content_call(call, content_alias?), do: preloads
    end

    defp preloads(node, content_alias?) do
      with {_call, _meta, [_identifiers, preloads]} <- content_call(node, content_alias?), do: preloads
    end

    defp content_call({{:., _, [{:__aliases__, _, receiver}, :get_entries_from_identifiers]}, _, _args} = call, alias?) do
      if receiver == [:Brando, :Content] or (alias? and receiver == [:Content]), do: call
    end

    defp content_call(_node, _alias?), do: nil

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
