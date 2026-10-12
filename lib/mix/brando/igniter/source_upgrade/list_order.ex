if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.ListOrder do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Finds calls to the application's generated `list_<plural>/1` queries
    # (`Brando.Query`'s `query :list`) whose options leave the row order to
    # Postgres. The 0.55 migrations rewrite rows, which changes that order.
    #
    # Only a literal options map is read: in the call, or bound to a variable
    # earlier in the same function and passed as it is. The rewrite edits that
    # map's text, so `.heex` templates and unformatted code keep their layout.

    alias Mix.Brando.Igniter.TemplateCode
    alias Rewrite.Source

    @sequence_order ~s("asc sequence, desc inserted_at")
    @id_order ~s("asc sequence, asc id")
    @extensions ~w(.ex .heex)
    @limit 50

    @call ~r/(?<![\w.:])((?:[A-Z]\w*\.)*[A-Z]\w*)\.(list_\w+)!?\(/
    @local_call ~r/(?<![\w.:])(list_\w+)!?\(/

    @doc """
    Gives list queries that order only by `sequence` the admin listing's
    tiebreak, and warns about list queries without an order.
    """
    def order_list_queries(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.{ex,heex}")

      sources =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
        |> Enum.filter(fn {path, _content} -> String.starts_with?(path, "lib/") and Path.extname(path) in @extensions end)
        |> Enum.sort()

      contexts = contexts(sources)

      findings =
        for {path, content} <- sources,
            finding <- file_findings(path, content, contexts),
            uniq: true,
            do: finding

      candidates = Enum.filter(findings, &(&1.kind == :sequence_only and &1.order != nil))

      {rewrites, conflicts} =
        candidates
        |> Enum.group_by(&{&1.path, &1.span})
        |> Enum.map(fn {_span, calls} -> merge_calls(calls) end)
        |> Enum.split_with(&(&1.kind == :sequence_only))

      warnings = (findings -- candidates) ++ conflicts

      igniter
      |> rewrite(rewrites)
      |> warn(warnings)
    end

    # One options map passed to several calls is rewritten once, and only
    # when every call needs the same tiebreak.
    defp merge_calls([finding | _] = calls) do
      merged = Map.put(finding, :call, calls |> Enum.map(& &1.call) |> Enum.uniq() |> Enum.join(" and "))

      case calls |> Enum.map(& &1.order) |> Enum.uniq() do
        [_order] -> merged
        orders -> Map.merge(merged, %{kind: :mixed_order, orders: orders})
      end
    end

    ## Contexts and Blueprints

    # `%{context_module => %{"list_<plural>" => order}}`, where `order` is
    # the tiebreak order for a Sequenced Blueprint and nil for any other.
    defp contexts(sources) do
      blueprints =
        for {_path, content} <- sources,
            {module, chunk} <- modules(content),
            chunk =~ ~r/use Brando\.Blueprint\b/,
            [_, plural] <- [Regex.run(~r/\bplural:\s*"([^"]+)"/, chunk)],
            into: %{},
            do: {module, {plural, sequence_order(chunk)}}

      for {_path, content} <- sources,
          {context, chunk} <- modules(content),
          chunk =~ ~r/use Brando\.Query\b/,
          aliases = aliases(chunk, context),
          functions = list_functions(chunk, aliases, blueprints),
          functions != %{},
          into: %{},
          do: {context, functions}
    end

    # Only Timestamped Blueprints have `inserted_at`.
    defp sequence_order(blueprint) do
      cond do
        not trait?(blueprint, "Sequenced") -> nil
        trait?(blueprint, "Timestamped") -> @sequence_order
        true -> @id_order
      end
    end

    defp trait?(blueprint, name), do: blueprint =~ ~r/^\s*trait[\s(]+Brando\.Trait\.#{name}\b/m

    defp list_functions(content, aliases, blueprints) do
      for [_, schema] <- Regex.scan(~r/^\s*query[\s(]+:list,\s*([\w.]+)/m, content),
          {plural, order} <- [Map.get(blueprints, resolve(schema, aliases))],
          into: %{},
          do: {"list_#{plural}", order}
    end

    # `[{module_name, text}]`: each `defmodule` in the file, up to the next one.
    defp modules(content) do
      for {name, start, stop} <- module_spans(content), do: {name, binary_part(content, start, stop - start)}
    end

    defp module_spans(content) do
      starts = Regex.scan(~r/^\s*defmodule\s+([\w.]+)\s+do/m, content, return: :index)
      ends = Enum.map(Enum.drop(starts, 1), fn [{start, _} | _] -> start end) ++ [byte_size(content)]

      for {[{start, _}, {name_start, name_length}], stop} <- Enum.zip(starts, ends),
          do: {binary_part(content, name_start, name_length), start, stop}
    end

    # `%{"Short" => "Full.Module"}` from the file's `alias` lines.
    defp aliases(content, current) do
      content = if current, do: String.replace(content, "__MODULE__", current), else: content

      as =
        for [_, full, short] <- Regex.scan(~r/^\s*alias\s+([\w.]+),\s*as:\s*(\w+)/m, content),
            do: {short, full}

      single =
        for [_, full] <- Regex.scan(~r/^\s*alias\s+([\w.]+)\s*$/m, content),
            do: {full |> String.split(".") |> List.last(), full}

      grouped =
        for [_, parent, names] <- Regex.scan(~r/^\s*alias\s+([\w.]+)\.\{([^}]*)\}/m, content),
            name <- String.split(names, ",", trim: true),
            name = String.trim(name),
            name != "",
            do: {name |> String.split(".") |> List.last(), "#{parent}.#{name}"}

      Map.new(single ++ grouped ++ as)
    end

    defp resolve(name, aliases) do
      [first | rest] = String.split(name, ".")

      case Map.fetch(aliases, first) do
        {:ok, full} -> Enum.join([full | rest], ".")
        :error -> name
      end
    end

    # A template has no aliases of its own: a qualifier that names no
    # context in full, and is no alias, is taken as the one context it is
    # the last part of.
    defp context_for(qualifier, aliases, contexts) do
      resolved = resolve(qualifier, aliases)
      aliased? = Map.has_key?(aliases, qualifier |> String.split(".") |> hd())

      cond do
        Map.has_key?(contexts, resolved) ->
          resolved

        aliased? ->
          nil

        true ->
          case Enum.filter(Map.keys(contexts), &String.ends_with?(&1, "." <> qualifier)) do
            [context] -> context
            _ -> nil
          end
      end
    end

    ## Call sites

    defp file_findings(path, content, contexts) do
      scope = scopes(path, content)
      code? = TemplateCode.code?(content, path)

      qualified =
        for [{start, _}, {q_start, q_length}, {f_start, f_length}] <- Regex.scan(@call, content, return: :index),
            code?.(start),
            {_module, aliases} = scope.(start),
            context = context_for(binary_part(content, q_start, q_length), aliases, contexts),
            context != nil,
            function = binary_part(content, f_start, f_length),
            Map.has_key?(contexts[context], function),
            do: {start, f_start + f_length, context, function}

      local =
        for [{start, _}, {f_start, f_length}] <- Regex.scan(@local_call, content, return: :index),
            code?.(start),
            {module, _aliases} = scope.(start),
            functions = Map.get(contexts, module),
            functions != nil,
            function = binary_part(content, f_start, f_length),
            Map.has_key?(functions, function),
            not definition?(content, start),
            do: {start, f_start + f_length, module, function}

      for {start, name_end, context, function} <- qualified ++ local,
          call = %{path: path, call: call_name(context, function), order: contexts[context][function]},
          finding <- call_findings(content, start, open_paren(content, name_end), Map.put(call, :code?, code?)),
          do: finding
    end

    # A function of an offset: the module around it and that module's
    # aliases. A template has neither.
    defp scopes(path, content) do
      # Last module first, so the first that starts before an offset holds it.
      modules =
        if Path.extname(path) == ".ex",
          do: content |> module_spans() |> Enum.map(&module_scope(content, &1)) |> Enum.reverse(),
          else: []

      fn offset ->
        {_start, name, aliases} = Enum.find(modules, {nil, nil, %{}}, &(elem(&1, 0) <= offset))
        {name, aliases}
      end
    end

    defp module_scope(content, {name, start, stop}),
      do: {start, name, aliases(binary_part(content, start, stop - start), name)}

    defp call_name(context, function), do: "#{context |> String.split(".") |> List.last()}.#{function}"

    defp definition?(content, start) do
      before = binary_part(content, max(start - 6, 0), min(start, 6))
      before =~ ~r/defp?\s+$/
    end

    defp open_paren(content, name_end) do
      {position, _} = :binary.match(content, "(", scope: {name_end, byte_size(content) - name_end})
      position
    end

    defp call_findings(content, start, paren, call) do
      rest = binary_part(content, paren + 1, byte_size(content) - paren - 1)

      cond do
        String.starts_with?(String.trim_leading(rest), "%{") ->
          map_start = paren + 1 + (byte_size(rest) - byte_size(String.trim_leading(rest)))
          map_findings(content, map_start, call)

        rest =~ ~r/^\s*\)/ ->
          if piped?(content, start), do: [], else: [finding(content, start, :missing, call)]

        match = Regex.run(~r/^\s*([a-z_]\w*)\s*\)/, rest) ->
          variable_findings(content, start, Enum.at(match, 1), call)

        true ->
          []
      end
    end

    defp piped?(content, start), do: binary_part(content, 0, start) =~ ~r/\|>\s*$/

    # The options map bound to `variable` last before the call, in the same
    # function and not rebound since.
    defp variable_findings(content, call_start, variable, call) do
      before = binary_part(content, 0, call_start)
      escaped = Regex.escape(variable)

      assignments =
        for [{start, _}] = match <- Regex.scan(~r/(?<![\w.])#{escaped}\s*=(?!=)\s*%\{/, before, return: :index),
            call.code?.(start),
            do: match

      case List.last(assignments) do
        [{assignment, length}] ->
          between = binary_part(before, assignment + length, byte_size(before) - assignment - length)

          if between =~ ~r/^\s*defp?\s/m or between =~ ~r/(?<![\w.])#{escaped}\s*=(?!=)/ do
            []
          else
            map_findings(content, assignment + length - 2, Map.put(call, :variable, variable))
          end

        nil ->
          []
      end
    end

    defp map_findings(content, map_start, call) do
      with {:ok, close} <- closing_brace(content, map_start + 2),
           inner = binary_part(content, map_start + 2, close - map_start - 2),
           false <- map_update?(inner) do
        order_findings(content, map_start, order_entry(inner), call)
      else
        _ -> []
      end
    end

    defp order_findings(content, map_start, nil, call), do: [finding(content, map_start, :missing, call)]

    defp order_findings(content, map_start, {offset, value}, call) do
      if sequence_only?(value) do
        span = {map_start + 2 + offset, byte_size(value)}
        [content |> finding(map_start, :sequence_only, call) |> Map.put(:span, span)]
      else
        []
      end
    end

    defp map_update?(inner), do: inner =~ ~r/^\s*[\w@.]+\s*\|(?![|>])/

    # `{offset, value}` of the `order:` value in the map's text.
    defp order_entry(inner) do
      inner
      |> top_level_entries()
      |> Enum.find_value(fn {offset, entry} ->
        case Regex.run(~r/^(\s*(?:order:|:order\s*=>)\s*)(.*?)\s*$/s, entry) do
          [_, key, value] -> {offset + byte_size(key), value}
          nil -> nil
        end
      end)
    end

    defp sequence_only?(value) do
      case Code.string_to_quoted(value) do
        {:ok, order} when is_binary(order) -> String.split(order) == ["asc", "sequence"]
        {:ok, {:asc, :sequence}} -> true
        {:ok, [{:asc, :sequence}]} -> true
        _ -> false
      end
    end

    defp finding(content, offset, kind, call) do
      line = content |> binary_part(0, offset) |> String.split("\n") |> length()
      text = content |> String.split("\n") |> Enum.at(line - 1) |> String.trim()
      call |> Map.delete(:code?) |> Map.merge(%{kind: kind, line: line, text: text, span: nil, offset: offset})
    end

    ## Scanning Elixir source text

    # The index of the brace that closes the map whose inside starts at `from`.
    defp closing_brace(content, from) do
      case walk(content, from, 0, []) do
        {:ok, close, _commas} -> {:ok, close}
        :error -> :error
      end
    end

    # Splits a map's inside at its top-level commas: `[{offset, entry}]`.
    defp top_level_entries(inner) do
      {:ok, _close, commas} = walk(inner <> "}", 0, 0, [])
      bounds = [-1 | commas] ++ [byte_size(inner)]

      bounds
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] -> {from + 1, binary_part(inner, from + 1, to - from - 1)} end)
    end

    # Walks from `index` to the bracket that closes the enclosing one,
    # skipping strings and comments, and collects the commas at its level.
    defp walk(content, index, _depth, _commas) when index >= byte_size(content), do: :error

    defp walk(content, index, depth, commas) do
      case :binary.at(content, index) do
        ?" -> walk(content, skip_string(content, index + 1), depth, commas)
        ?# -> walk(content, skip_comment(content, index), depth, commas)
        char when char in [?{, ?[, ?(] -> walk(content, index + 1, depth + 1, commas)
        char when char in [?}, ?], ?)] and depth == 0 -> {:ok, index, Enum.reverse(commas)}
        char when char in [?}, ?], ?)] -> walk(content, index + 1, depth - 1, commas)
        ?, when depth == 0 -> walk(content, index + 1, depth, [index | commas])
        _char -> walk(content, index + 1, depth, commas)
      end
    end

    defp skip_string(content, index) when index >= byte_size(content), do: index

    defp skip_string(content, index) do
      case :binary.at(content, index) do
        ?\\ -> skip_string(content, index + 2)
        ?" -> index + 1
        _ -> skip_string(content, index + 1)
      end
    end

    defp skip_comment(content, index) do
      case :binary.match(content, "\n", scope: {index, byte_size(content) - index}) do
        {newline, _} -> newline
        :nomatch -> byte_size(content)
      end
    end

    ## Output

    defp rewrite(igniter, []), do: igniter

    defp rewrite(igniter, findings) do
      igniter =
        findings
        |> Enum.group_by(& &1.path)
        |> Enum.reduce(igniter, fn {path, findings}, igniter ->
          spans =
            findings
            |> Enum.map(fn %{span: {start, length}, order: order} -> {start, length, order} end)
            |> Enum.uniq()
            |> Enum.sort(:desc)

          Igniter.update_file(igniter, path, &Source.update(&1, :content, fn content -> replace(content, spans) end))
        end)

      Igniter.add_notice(igniter, """
      These list queries ordered only by `sequence`, so entries with equal
      `sequence` came back in storage order, which the 0.55 data migrations
      change. They now break ties as the admin listing does, with
      #{@sequence_order}, or with #{@id_order} for a schema without
      timestamps, which keeps every order they defined:

      #{format(findings, &" → #{&1.order}")}
      """)
    end

    # `spans` run from the end of the file, so earlier offsets stay valid; a
    # span overlapping one already replaced is left alone.
    defp replace(content, spans) do
      {content, _limit} =
        Enum.reduce(spans, {content, byte_size(content)}, fn {start, length, order}, {content, limit} ->
          if start + length <= limit do
            rest = binary_part(content, start + length, byte_size(content) - start - length)
            {binary_part(content, 0, start) <> order <> rest, start}
          else
            {content, limit}
          end
        end)

      content
    end

    defp warn(igniter, []), do: igniter

    defp warn(igniter, findings) do
      Igniter.add_warning(igniter, """
      These list queries leave the order of their rows to Postgres, which
      returns them as stored. The 0.55 data migrations rewrite rows, so the
      order on the site can change (the first tab of a menu, or entries with
      equal `sequence`):

      #{format(findings, &hint/1)}

      Give each an explicit `order:`: the order named for a Sequenced schema
      (#{@sequence_order} is the admin listing's), or a column order such as
      `order: "asc title"`. Adding one is a visible change from the old
      accidental order, so check the pages that show these lists.
      """)
    end

    defp format(findings, note) do
      shown = findings |> Enum.sort_by(&{&1.path, &1.line}) |> Enum.take(@limit)
      more = length(findings) - length(shown)

      Enum.map_join(shown, "\n", &("  " <> describe(&1) <> note.(&1))) <>
        if more > 0, do: "\n  … and #{more} more", else: ""
    end

    defp describe(finding) do
      passed = if finding[:variable], do: ", passed to #{finding.call}", else: ""
      "#{finding.path}:#{finding.line}: #{finding.text}#{passed}"
    end

    defp hint(%{kind: :missing, order: order}) when is_binary(order), do: " (Sequenced: order: #{order})"

    defp hint(%{kind: :sequence_only, order: nil}),
      do: " (orders by `sequence` without the Sequenced trait; add a tiebreak)"

    defp hint(%{kind: :mixed_order, orders: orders}),
      do: " (they need different tiebreaks: #{Enum.join(orders, ", ")})"

    defp hint(_finding), do: ""
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.ListOrder do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
