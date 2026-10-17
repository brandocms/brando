if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.BlueprintCompileFixes do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Blueprint declarations that compiled on 0.54 and that 0.55 refuses:
    #
    #   * an `identifier` on an embedded Blueprint (`data_layer :embedded`),
    #     which identifies nothing: written `identifier false`;
    #   * `default_srcset:` in an asset config, which 0.53 and 0.54 ignored
    #     there (it is a `Brando.Images` setting): written as the asset's
    #     `srcset: %{default: …}`, or removed beside a `srcset:`, which the
    #     asset used;
    #   * `from:` or `for:` on a slug input, which no slug input read: written
    #     `source:`, or removed beside a `source:`. The 0.55-dev generator
    #     wrote `from:`; the application's copy of its template
    #     (`priv/templates/brando.gen.blueprint/blueprint.ex`) is EEx, which
    #     Igniter cannot write as an `.ex` file, so its lines are listed.
    #
    # Run it before the other Blueprint rewrites, so the lines it reports are
    # the file's.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Mix.Brando.Igniter.SourceUpgrade.ModuleScope
    alias Mix.Brando.Igniter.Template
    alias Rewrite.Source
    alias Sourceror.Zipper

    @scopes [:def, :defp, :defmacro, :defmacrop, :fn]

    @slug_source_keys [:from, :for]
    @generator_template "priv/templates/brando.gen.blueprint/blueprint.ex"
    # The template is EEx, not Elixir: a slug input's options are read as
    # text, from the end of this match to the end of the call.
    @template_slug_input ~r/^\s*input\(?\s*:\w+\s*,\s*:slug\s*,\s*\[?/
    @template_strings ~r/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/

    @srcset_note """
    `default_srcset` was never an asset config field, and Brando ignored it
    there: the asset used its `srcset:`, or the default config's. Now the list
    applies to the asset; check that each size it names is in its `sizes`.
    """

    @doc "Rewrites them, noting each change with file and line."
    def rewrite(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)

      {igniter, changes} =
        Enum.reduce(blueprints, {igniter, []}, fn module, {igniter, changes} ->
          {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)
          path = Source.get(source, :path)

          case findings(Zipper.subtree(zipper)) do
            [] ->
              {igniter, changes}

            found ->
              igniter = ProjectModule.find_and_update_module!(igniter, module, &update_body/1)

              {igniter, changes ++ Enum.map(found, fn {line, text} -> "#{path}:#{line}: #{text}" end)}
          end
        end)

      igniter
      |> notice(changes)
      |> warn_generator_template()
    end

    # `{line, change}` for what `update/1` changes.
    defp findings(zipper) do
      identifiers =
        for identifier <- embedded_identifiers(zipper),
            do: {line(identifier), "`identifier false` on an embedded Blueprint"}

      srcsets =
        for {key, sibling_srcset?} <- default_srcsets(zipper) do
          if sibling_srcset?,
            do: {line(key), "`default_srcset:` removed; the `srcset:` beside it stays"},
            else: {line(key), "`default_srcset:` is now `srcset: %{default: …}`"}
        end

      slug_sources =
        for {key, source_beside?} <- slug_sources(zipper) do
          if source_beside?,
            do: {line(key), "`#{literal(key)}:` removed; the `source:` beside it stays"},
            else: {line(key), "`#{literal(key)}:` on a slug input is now `source:`"}
        end

      Enum.sort(identifiers ++ srcsets ++ slug_sources)
    end

    # Within the module's body: the file may hold other modules.
    defp update_body(zipper), do: Common.within(zipper, &{:ok, update(&1)})

    # `zipper` is the module's body, as a subtree: the file may hold other
    # modules.
    defp update(zipper) do
      # By line and column: two declarations can share a line.
      identifier_lines = zipper |> embedded_identifiers() |> MapSet.new(&position/1)
      srcset_lines = zipper |> default_srcsets() |> MapSet.new(fn {key, _sibling_srcset?} -> position(key) end)

      slug_keys =
        zipper
        |> slug_sources()
        |> Map.new(fn {key, source_beside?} -> {position(key), if(source_beside?, do: :drop, else: :rename)} end)

      Zipper.traverse(zipper, &update_node(&1, identifier_lines, srcset_lines, slug_keys))
    end

    defp update_node(zipper, identifier_lines, srcset_lines, slug_keys) do
      case Zipper.node(zipper) do
        {:identifier, meta, [_template]} = node ->
          if MapSet.member?(identifier_lines, position(node)),
            do: Zipper.replace(zipper, {:identifier, meta, [{:__block__, [], [false]}]}),
            else: zipper

        node ->
          case pairs(node) do
            {:ok, pairs} -> update_pairs(zipper, node, pairs, srcset_lines, slug_keys)
            :error -> zipper
          end
      end
    end

    defp update_pairs(zipper, node, pairs, srcset_lines, slug_keys) do
      cond do
        Enum.any?(pairs, fn {key, _value} -> Map.has_key?(slug_keys, position(key)) end) ->
          Zipper.replace(zipper, rewrite_slug_sources(node, pairs, slug_keys))

        srcset_key?(pairs, srcset_lines) ->
          Zipper.replace(zipper, rewrite_pairs(node, pairs))

        true ->
          zipper
      end
    end

    defp srcset_key?(pairs, srcset_lines) do
      case default_srcset(pairs) do
        {key, _value} -> MapSet.member?(srcset_lines, position(key))
        nil -> false
      end
    end

    ## Embedded identifiers

    defp embedded_identifiers(zipper) do
      if embedded?(zipper) do
        zipper
        |> ModuleScope.find_all(&(CodeFunction.function_call?(&1, :identifier, 1) and declaration?(&1)))
        |> Enum.map(&call_node/1)
        |> Enum.reject(fn {:identifier, _meta, [template]} -> literal(template) in [false, nil] end)
      else
        []
      end
    end

    defp embedded?(zipper) do
      zipper
      |> ModuleScope.find_all(&(CodeFunction.function_call?(&1, :data_layer, 1) and declaration?(&1)))
      |> Enum.any?(&embedded_layer?(call_node(&1)))
    end

    defp embedded_layer?({:data_layer, _, [layer]}), do: literal(layer) == :embedded
    defp embedded_layer?(_node), do: false

    defp call_node(zipper), do: zipper |> Common.maybe_move_to_single_child_block() |> Zipper.node()

    # A Blueprint declaration, not a call inside a function.
    defp declaration?(zipper) do
      case Zipper.up(zipper) do
        nil -> true
        parent -> not match?({scope, _, _} when scope in @scopes, Zipper.node(parent)) and declaration?(parent)
      end
    end

    ## default_srcset

    # `{key_node, sibling_srcset?}` of each `default_srcset:` in an asset's
    # `cfg:`: given inline, or as a module attribute the module defines.
    defp default_srcsets(zipper) do
      {inline, attributes} =
        zipper
        |> ModuleScope.find_all(&CodeFunction.function_call?(&1, :asset, 3))
        |> Enum.flat_map(&asset_cfg(call_node(&1)))
        |> Enum.split_with(&(not match?({:attribute, _name}, &1)))

      attribute_names = for {:attribute, name} <- attributes, do: name

      attribute_values =
        for attribute <- ModuleScope.find_all(zipper, &match?({:@, _, [{_name, _, [_value]}]}, Zipper.node(&1))),
            {:@, _, [{name, _, [value]}]} = Zipper.node(attribute),
            name in attribute_names,
            do: value

      for config <- inline ++ attribute_values,
          {:ok, pairs} <- [config |> unwrap() |> pairs()],
          {key, _value} <- [default_srcset(pairs)],
          do: {key, Enum.any?(pairs, &(key(&1) == :srcset))}
    end

    defp asset_cfg({:asset, _, [_name, _type, options]}) do
      case options |> unwrap() |> pairs() do
        {:ok, pairs} ->
          for {key, value} <- pairs, literal(key) == :cfg, do: cfg_value(value)

        :error ->
          []
      end
    end

    defp asset_cfg(_node), do: []

    defp cfg_value({:@, _, [{name, _, context}]}) when is_atom(context), do: {:attribute, name}
    defp cfg_value(config), do: config

    defp unwrap({:__block__, _meta, [value]}) when is_list(value), do: value
    defp unwrap(value), do: value

    defp default_srcset(pairs), do: Enum.find(pairs, &(key(&1) == :default_srcset))

    defp rewrite_pairs(node, pairs) do
      pairs =
        if Enum.any?(pairs, &(key(&1) == :srcset)) do
          Enum.reject(pairs, &(key(&1) == :default_srcset))
        else
          Enum.map(pairs, fn
            {{:__block__, meta, [:default_srcset]}, value} ->
              {{:__block__, meta, [:srcset]}, {:%{}, [], [{{:__block__, [format: :keyword], [:default]}, value}]}}

            pair ->
              pair
          end)
        end

      put_pairs(node, pairs)
    end

    ## Slug source

    # `{key_node, source_beside?}` of each `from:` or `for:` on a slug input.
    # A second one beside the first counts as beside a `source:`.
    defp slug_sources(zipper) do
      for input <- ModuleScope.find_all(zipper, &(CodeFunction.function_call?(&1, :input, 3) and declaration?(&1))),
          {:input, _meta, [_name, type, options]} <- [call_node(input)],
          literal(type) == :slug,
          {:ok, pairs} <- [options |> unwrap() |> pairs()],
          source? <- [Enum.any?(pairs, &(key(&1) == :source))],
          {{key, _value}, index} <- pairs |> Enum.filter(&(key(&1) in @slug_source_keys)) |> Enum.with_index(),
          do: {key, source? or index > 0}
    end

    defp rewrite_slug_sources(node, pairs, slug_keys) do
      {pairs, comments} =
        Enum.flat_map_reduce(pairs, [], fn {{:__block__, meta, [_key]} = key, value} = pair, comments ->
          case Map.get(slug_keys, position(key)) do
            nil -> {[put_leading_comments(pair, comments)], []}
            :drop -> {[], comments ++ Keyword.get(meta, :leading_comments, [])}
            :rename -> {[put_leading_comments({{:__block__, meta, [:source]}, value}, comments)], []}
          end
        end)

      # A dropped last option's comments go on the option before it.
      pairs =
        case {comments, Enum.split(pairs, -1)} do
          {[], _split} -> pairs
          {comments, {before, [last]}} -> before ++ [put_leading_comments(last, comments)]
        end

      put_pairs(node, pairs)
    end

    defp put_leading_comments(pair, []), do: pair

    defp put_leading_comments({{:__block__, meta, key}, value}, comments),
      do: {{:__block__, Keyword.update(meta, :leading_comments, comments, &(comments ++ &1)), key}, value}

    defp warn_generator_template(igniter) do
      if Igniter.exists?(igniter, @generator_template) do
        {igniter, content} = Template.read(igniter, @generator_template)

        original = content |> String.split("\n") |> List.to_tuple()

        lines =
          for number <- template_slug_sources(content),
              do: "  #{@generator_template}:#{number}: #{original |> elem(number - 1) |> String.trim()}"

        if lines == [] do
          igniter
        else
          Igniter.add_warning(igniter, """
          #{@generator_template}, this application's copy of the `mix brando.gen.blueprint`
          template, is EEx, so the task read it as text and did not change it. These lines
          look like a slug input given `from:` or `for:`, which fails to compile on 0.55.
          Check the slug inputs in the template, and change the option to `source:` by hand.

          #{Enum.join(lines, "\n")}
          """)
        end
      else
        igniter
      end
    end

    # Line numbers of a `from:` or `for:` among a slug input's own options in
    # the template, a call that may continue over the following lines. Not in
    # a string or comment, nor in an option's nested list.
    defp template_slug_sources(content) do
      lines = content |> String.split("\n") |> Enum.map(&template_code/1) |> Enum.with_index(1)

      lines
      |> Enum.with_index()
      |> Enum.flat_map(fn {{text, number}, index} ->
        case Regex.run(@template_slug_input, text, return: :index) do
          [{0, length}] ->
            options = binary_part(text, length, byte_size(text) - length)
            option_keys([{options, number} | Enum.drop(lines, index + 1)], 0, true, [])

          nil ->
            []
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()
    end

    defp template_code(line) do
      line
      |> String.replace(@template_strings, ~s(""))
      |> String.replace(~r/#.*$/, "")
    end

    defp option_keys([], _depth, _start?, found), do: found

    defp option_keys([{text, number} | lines], depth, start?, found) do
      case scan_options(text, number, depth, start?, found) do
        {:done, found} ->
          found

        {:open, depth, start?, found} ->
          # Without parentheses, the call goes on past a line that ends in a comma.
          if depth == 0 and not start?,
            do: found,
            else: option_keys(lines, depth, start?, found)
      end
    end

    # `start?`: at the start of an option, where a key can be.
    defp scan_options("", _number, depth, start?, found), do: {:open, depth, start?, found}

    defp scan_options(<<char, rest::binary>>, number, depth, start?, found) when char in ~c" \t",
      do: scan_options(rest, number, depth, start?, found)

    defp scan_options(<<char, rest::binary>>, number, depth, _start?, found) when char in ~c"([{",
      do: scan_options(rest, number, depth + 1, false, found)

    defp scan_options(<<char, _rest::binary>>, _number, 0, _start?, found) when char in ~c")]}", do: {:done, found}

    defp scan_options(<<char, rest::binary>>, number, depth, _start?, found) when char in ~c")]}",
      do: scan_options(rest, number, depth - 1, false, found)

    defp scan_options(<<?,, rest::binary>>, number, depth, _start?, found),
      do: scan_options(rest, number, depth, depth == 0, found)

    defp scan_options(<<_char, rest::binary>> = text, number, depth, start?, found) do
      found = if start? and depth == 0 and String.starts_with?(text, ["from:", "for:"]), do: [number | found], else: found
      scan_options(rest, number, depth, false, found)
    end

    # The key/value pairs of a keyword list or a map literal.
    defp pairs({:%{}, _meta, pairs}) when is_list(pairs),
      do: if(Enum.all?(pairs, &pair?/1), do: {:ok, pairs}, else: :error)

    defp pairs([_ | _] = list), do: if(Enum.all?(list, &pair?/1), do: {:ok, list}, else: :error)
    defp pairs(_node), do: :error

    defp put_pairs({:%{}, meta, _pairs}, pairs), do: {:%{}, meta, pairs}
    defp put_pairs(list, pairs) when is_list(list), do: pairs

    defp pair?({{:__block__, _meta, [key]}, _value}) when is_atom(key), do: true
    defp pair?(_node), do: false

    defp key({{:__block__, _meta, [key]}, _value}), do: key

    defp literal({:__block__, _meta, [value]}), do: value
    defp literal(value), do: value

    defp line({{:__block__, meta, _}, _value}), do: meta[:line]
    defp line({_form, meta, _args}), do: meta[:line]

    defp position({_form, meta, _args}), do: {meta[:line], meta[:column]}

    defp notice(igniter, []), do: igniter

    defp notice(igniter, changes) do
      srcset? = Enum.any?(changes, &String.contains?(&1, "default_srcset"))

      Igniter.add_notice(igniter, """
      Blueprint declarations 0.55 no longer compiles were changed:

      #{Enum.map_join(changes, "\n", &("  " <> &1))}
      #{if srcset?, do: "\n" <> @srcset_note, else: ""}\
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.BlueprintCompileFixes do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
