if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.PageVars do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # 0.54 page vars are an association, and `Brando.Pages.get_var/2` and
    # `has_var?/2` raise when it is not loaded. When a template reads vars on
    # the page assign (`@page`, `assigns[:page]`, `assigns.page`), each
    # `Pages.get_page/1` call (or pipe into it) whose options are a literal
    # map, or a variable the same function assigns one, gets `:vars` in its
    # `preload` list. Reads on anything else, and every read when a load
    # cannot be updated or none is found, stay listed. When no read is on the
    # page assign, the loads are listed beside the reads, unchanged.

    alias Rewrite.Source

    @read ~r/(?:\bPages\.|(?<![\w.]))(get_var|has_var\?)\(/
    @page_read ~r/(?:\bPages\.|(?<![\w.]))(?:get_var|has_var\?)\(\s*(?:@page\b|assigns\[:page\]|assigns\.page\b)/

    @doc """
    Adds `:vars` to the page loads in `sources` (`{path, content}`) when a
    template reads `@page`'s vars. Returns the igniter and the warning
    sections (`{text, findings}`) for what is left.
    """
    def preload(igniter, sources) do
      reads = for {path, content} <- sources, {line, number} <- lines(content), line =~ @read, do: {path, number, line}

      loads = for {path, content} <- sources, Path.extname(path) == ".ex", content =~ ~r/\bget_page\b/, do: path

      cond do
        Enum.any?(reads, fn {_path, _number, line} -> line =~ @page_read end) ->
          {igniter, results} = Enum.reduce(loads, {igniter, []}, &update_loads(&1, &2, :update))
          report(igniter, reads, results)

        reads == [] ->
          {igniter, []}

        true ->
          {igniter, results} = Enum.reduce(loads, {igniter, []}, &update_loads(&1, &2, :list))
          {igniter, sections(reads, []) ++ unchanged_loads(results)}
      end
    end

    # The loads beside reads that are not on the page assign: which page
    # reaches them is the application's to tell.
    defp unchanged_loads(results) do
      findings =
        for {path, line, result} <- results, result != :has_vars do
          case result do
            :added -> "#{path}:#{line}: `Pages.get_page/1`"
            {:unknown, reason} -> "#{path}:#{line}: `Pages.get_page/1`, #{reason}"
          end
        end

      [
        {"""
         Page loads the task left alone, since no read above is on the page
         assign. Add `preload: [:vars]` to the options of each one whose page
         reaches those reads:
         """, findings}
      ]
      |> Enum.reject(fn {_text, findings} -> findings == [] end)
    end

    defp lines(content), do: content |> String.split("\n") |> Enum.with_index(1)

    defp report(igniter, reads, results) do
      added = for {path, line, :added} <- results, do: {path, line}
      unknown = for {path, line, {:unknown, reason}} <- results, do: {path, line, reason}

      # Once every load preloads `:vars`, the `@page` reads are fine.
      listed =
        if results == [] or unknown != [],
          do: reads,
          else: Enum.reject(reads, fn {_path, _number, line} -> line =~ @page_read end)

      igniter =
        case added do
          [] ->
            igniter

          added ->
            Igniter.add_notice(igniter, """
            Templates read page vars on `@page`, so the task added `:vars` to the
            `preload` of these page loads:

            #{Enum.map_join(added, "\n", fn {path, line} -> "  #{path}:#{line}" end)}
            """)
        end

      {igniter, sections(listed, unknown)}
    end

    defp sections(reads, unknown) do
      [
        {"""
         Page vars. They are an association: load the page with
         `preload: [:alternate_entries, :vars]` (or `Brando.Repo.preload(page, :vars)`)
         before `get_var/2` or `has_var?/2`, which raise otherwise. The task adds
         `:vars` to `Pages.get_page/1` options written as a map; these calls are
         matched by name, so a line stays listed after you add the preload:
         """, for({path, number, line} <- reads, do: "#{path}:#{number}: #{String.trim(line)}")},
        {"""
         Page loads the task could not give `:vars` (add it to their `preload`
         if their page reaches a template that reads vars):
         """, for({path, line, reason} <- unknown, do: "#{path}:#{line}: #{reason}")}
      ]
      |> Enum.reject(fn {_text, findings} -> findings == [] end)
    end

    ## Loads

    defp update_loads(path, {igniter, results}, mode) do
      source = Rewrite.source!(igniter.rewrite, path)
      ast = Source.get(source, :quoted)
      {updated, found} = Macro.prewalk(ast, [], &update_definition/2)
      found = Enum.map(found, fn {line, result} -> {path, line, result} end) ++ unread(path, source, found)

      if updated == ast or mode == :list,
        do: {igniter, results ++ found},
        else: {Igniter.update_elixir_file(igniter, path, &{:ok, Sourceror.Zipper.replace(&1, updated)}), results ++ found}
    end

    # Lines naming `get_page` that hold no call the task read: a pipe into it,
    # an imported call, a function of the application's own.
    defp unread(path, source, found) do
      read = MapSet.new(found, &elem(&1, 0))

      for {line, number} <- source |> Source.get(:content) |> lines(),
          line =~ ~r/\bget_page\b/,
          not (line =~ ~r/^\s*(#|import\b|alias\b|require\b)/),
          not MapSet.member?(read, number),
          do: {path, number, {:unknown, "a `get_page` call the task cannot read"}}
    end

    # Within one function: the `get_page/1` calls and the maps they load with.
    defp update_definition({kind, meta, [head, body]}, found) when kind in [:def, :defp] do
      calls = calls(body)
      assigned = for {_line, {:variable, name}} <- calls, uniq: true, do: name
      targets = Map.new(assigned, &{&1, assignments(body, &1)})

      results =
        Enum.map(calls, fn
          {line, {:map, map}} -> {line, status(map)}
          {line, {:variable, name}} -> {line, variable_status(targets[name], name)}
          {line, :other} -> {line, {:unknown, "its options are neither a map nor a variable assigned one"}}
        end)

      body =
        Macro.prewalk(body, fn
          {:=, assign_meta, [{name, _, context} = variable, {:%{}, _, _} = map]}
          when is_atom(name) and is_atom(context) and is_map_key(targets, name) ->
            if match?([_], targets[name]),
              do: {:=, assign_meta, [variable, with_vars(map)]},
              else: {:=, assign_meta, [variable, map]}

          {:|>, pipe_meta, [{:%{}, _, _} = map, call]} = node ->
            if get_page?(node), do: {:|>, pipe_meta, [with_vars(map), call]}, else: node

          {call, call_meta, [{:%{}, _, _} = map]} = node ->
            if get_page?(node), do: {call, call_meta, [with_vars(map)]}, else: node

          node ->
            node
        end)

      {{kind, meta, [head, body]}, found ++ results}
    end

    defp update_definition(node, found), do: {node, found}

    defp calls(body) do
      {_body, calls} =
        Macro.prewalk(body, [], fn node, calls ->
          if get_page?(node), do: {node, [{Sourceror.get_line(node), argument(node)} | calls]}, else: {node, calls}
        end)

      Enum.reverse(calls)
    end

    defp get_page?({{:., _, [{:__aliases__, _, parts}, :get_page]}, _, [_options]}),
      do: parts in [[:Pages], [:Brando, :Pages]]

    defp get_page?({:|>, _, [_options, {{:., _, [{:__aliases__, _, parts}, :get_page]}, _, []}]}),
      do: parts in [[:Pages], [:Brando, :Pages]]

    defp get_page?(_node), do: false

    defp argument({:|>, meta, [options, _call]}), do: argument({:get_page, meta, [options]})
    defp argument({_call, _, [{:%{}, _, _} = map]}), do: {:map, map}
    defp argument({_call, _, [{name, _, context}]}) when is_atom(name) and is_atom(context), do: {:variable, name}
    defp argument(_call), do: :other

    # Every value the function assigns to `name`.
    defp assignments(body, name) do
      {_body, values} =
        Macro.prewalk(body, [], fn
          {:=, _, [{^name, _, context}, value]} = node, values when is_atom(context) -> {node, [value | values]}
          node, values -> {node, values}
        end)

      values
    end

    defp variable_status([{:%{}, _, _} = map], _name), do: status(map)

    defp variable_status(_values, name),
      do: {:unknown, "`#{name}` is not assigned one map in the same function"}

    defp status({:%{}, _, pairs} = map) do
      cond do
        not Enum.all?(pairs, &atom_key?/1) -> {:unknown, "its options are not a map with atom keys"}
        preload(map) == :other -> {:unknown, "its `preload` is not a list"}
        match?({:list, entries} when is_list(entries), preload(map)) and has_vars?(map) -> :has_vars
        true -> :added
      end
    end

    defp atom_key?({{:__block__, _, [key]}, _value}), do: is_atom(key)
    defp atom_key?(_pair), do: false

    defp has_vars?(map) do
      {:list, entries} = preload(map)
      Enum.any?(entries, &vars?/1)
    end

    defp preload({:%{}, _, pairs}) do
      Enum.find_value(pairs, fn
        {{:__block__, _, [:preload]}, {:__block__, _, [entries]}} when is_list(entries) -> {:list, entries}
        {{:__block__, _, [:preload]}, _value} -> :other
        _pair -> nil
      end)
    end

    defp vars?({:__block__, _, [:vars]}), do: true
    defp vars?({{:__block__, _, [:vars]}, _value}), do: true
    defp vars?(_entry), do: false

    defp with_vars({:%{}, meta, pairs} = map) do
      cond do
        not Enum.all?(pairs, &atom_key?/1) ->
          map

        preload(map) == nil ->
          {:%{}, meta, pairs ++ [{{:__block__, [format: :keyword], [:preload]}, {:__block__, [], [[vars()]]}}]}

        true ->
          {:%{}, meta, Enum.map(pairs, &pair_with_vars/1)}
      end
    end

    defp pair_with_vars({{:__block__, _, [:preload]} = key, {:__block__, list_meta, [entries]}}) when is_list(entries) do
      if Enum.any?(entries, &vars?/1) do
        {key, {:__block__, list_meta, [entries]}}
      else
        # Keyword entries close a list, so `:vars` goes before them.
        {atoms, keywords} = Enum.split_while(entries, &(not match?({_key, _value}, &1)))
        {key, {:__block__, list_meta, [atoms ++ [vars()] ++ keywords]}}
      end
    end

    defp pair_with_vars(pair), do: pair

    defp vars, do: {:__block__, [], [:vars]}
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.PageVars do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
