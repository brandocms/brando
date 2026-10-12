if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.FormInputs do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Blueprint form input options that 0.53 accepted and that crash the 0.54
    # admin form, which `Brando.Blueprint.SecondaryVerifier.FormInputs` now
    # rejects when a Blueprint compiles:
    #
    #   * a `:multi_select` on a has_many needs `relation:`, the join schema's
    #     belongs_to whose foreign key is `relation_key`;
    #   * an `:entries` input's `for:`/`sources:` options run on the
    #     identifiers the picker lists, so options identifiers do not have
    #     (`preload:`, an order by `sequence`) are dropped.
    #
    # It runs before the Blueprint rewrite, so the file and line it reports
    # are the 0.53 source's.

    alias Brando.Blueprint.SecondaryVerifier.FormInputs, as: Check
    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Rewrite.Source
    alias Sourceror.Zipper

    @doc """
    Adds `relation:` to multi selects and drops `sources:` options identifiers
    do not take, noting each change with file and line, and lists those it
    cannot read.
    """
    def rewrite(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)

      {igniter, changes, unresolved} =
        Enum.reduce(blueprints, {igniter, [], []}, fn module, {igniter, changes, unresolved} ->
          {igniter, module_changes, module_unresolved} = rewrite_blueprint(igniter, module)
          {igniter, changes ++ module_changes, unresolved ++ module_unresolved}
        end)

      igniter
      |> notice(changes)
      |> warning(unresolved)
    end

    defp rewrite_blueprint(igniter, module) do
      {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)
      path = Source.get(source, :path)
      blueprint = %{module: module, zipper: zipper}

      {relations, multi_unresolved} = multi_select_relations(igniter, blueprint, path)
      {sources, sources_changes, sources_unresolved} = entries_sources(zipper, path)

      multi_changes =
        for {line, name, relation} <- relations,
            do: "#{path}:#{line}: `relation: #{inspect(relation)}` on input #{inspect(name)}, :multi_select"

      igniter =
        if relations == [] and sources == %{} do
          igniter
        else
          renames = Map.new(relations, fn {line, _name, relation} -> {line, relation} end)

          ProjectModule.find_and_update_module!(igniter, module, fn zipper ->
            Common.within(zipper, &{:ok, Zipper.traverse(&1, fn input -> update_input(input, renames, sources) end)})
          end)
        end

      {igniter, multi_changes ++ sources_changes, multi_unresolved ++ sources_unresolved}
    end

    defp update_input(zipper, relations, sources) do
      case Zipper.node(zipper) do
        {:input, meta, [name, type, options]} ->
          Zipper.replace(zipper, {:input, meta, [name, type, updated_options(options, meta[:line], relations, sources)]})

        _node ->
          zipper
      end
    end

    defp updated_options(options, line, relations, sources) do
      cond do
        Map.has_key?(relations, line) -> add_relation(options, relations[line])
        Map.has_key?(sources, line) -> put_sources(options, sources[line])
        true -> options
      end
    end

    ## Multi selects

    # A multi select in `inputs_for` edits a relation of the subform's schema.
    defp multi_select_relations(igniter, blueprint, path) do
      blueprint.zipper
      |> inputs(:multi_select)
      |> Enum.reject(fn {_line, _name, options, _subform} -> option(options, :relation) end)
      |> Enum.flat_map(fn {line, name, options, subform} ->
        relation_key = literal(option(options, :relation_key))

        case igniter |> owner(blueprint, subform) |> has_many(name) do
          {:has_many, join_module} -> [multi_select_relation(igniter, path, line, name, relation_key, join_module)]
          _not_a_has_many -> []
        end
      end)
      |> Enum.split_with(&match?({:ok, _}, &1))
      |> then(fn {resolved, unresolved} -> {Enum.map(resolved, &elem(&1, 1)), Enum.map(unresolved, &elem(&1, 1))} end)
    end

    defp multi_select_relation(_igniter, path, line, name, relation_key, _join_module) when relation_key in [nil, :id],
      do: {:unresolved, multi_select_finding(path, line, name, nil, nil)}

    defp multi_select_relation(igniter, path, line, name, relation_key, join_module) do
      case belongs_to_names(igniter, join_module, relation_key) do
        [relation] -> {:ok, {line, name, relation}}
        _none_or_many -> {:unresolved, multi_select_finding(path, line, name, relation_key, join_module)}
      end
    end

    defp multi_select_finding(path, line, name, relation_key, join_module) do
      cond do
        is_nil(relation_key) ->
          "#{path}:#{line}: input #{inspect(name)}, :multi_select needs `relation_key:` (the join schema's " <>
            "foreign key to the option) and `relation:` (its belongs_to)"

        is_nil(join_module) ->
          "#{path}:#{line}: input #{inspect(name)}, :multi_select (`relation_key: #{inspect(relation_key)}`) " <>
            "needs `relation:`, the join schema's belongs_to on that key"

        true ->
          "#{path}:#{line}: input #{inspect(name)}, :multi_select (`relation_key: #{inspect(relation_key)}`) " <>
            "needs `relation:`; no single belongs_to in #{inspect(join_module)} has that foreign key"
      end
    end

    defp owner(_igniter, blueprint, nil), do: blueprint

    defp owner(igniter, blueprint, subform) do
      with {_type, options} <- relation(blueprint, subform),
           module when is_atom(module) and not is_nil(module) <- expand_module(blueprint, option(options, :module)),
           {:ok, {_igniter, _source, zipper}} <- ProjectModule.find_module(igniter, module) do
        %{module: module, zipper: zipper}
      else
        _ -> nil
      end
    end

    # `{:has_many, join_module | nil}` for a has_many (not `through:`) relation
    # `name` of the Blueprint, or nil.
    defp has_many(nil, _name), do: nil

    defp has_many(blueprint, name) do
      with {:has_many, options} <- relation(blueprint, name),
           nil <- option(options, :through) do
        {:has_many, expand_module(blueprint, option(options, :module))}
      else
        _ -> nil
      end
    end

    # `{type, options}` of the Blueprint's relation `name`, or nil.
    defp relation(blueprint, name) do
      blueprint.zipper
      |> Zipper.subtree()
      |> Common.find_all(&CodeFunction.function_call?(&1, :relation, 3))
      |> Enum.find_value(fn relation_zipper ->
        with {:relation, _, [relation_name, type, options]} <- single_child_node(relation_zipper),
             ^name <- literal(relation_name) do
          {literal(type), options}
        else
          _ -> nil
        end
      end)
    end

    # The module an alias names where the Blueprint declares it.
    defp expand_module(blueprint, {:__aliases__, _, [{:__MODULE__, _, _} | parts]}) do
      if Enum.all?(parts, &is_atom/1), do: Module.concat([blueprint.module | parts])
    end

    defp expand_module(blueprint, {:__aliases__, _, parts} = module) do
      expanded =
        case Zipper.find(blueprint.zipper, &(&1 == module)) do
          nil -> module
          module_zipper -> module_zipper |> Common.expand_alias() |> Zipper.node()
        end

      case expanded do
        {:__aliases__, _, expanded_parts} -> if Enum.all?(expanded_parts, &is_atom/1), do: Module.concat(expanded_parts)
        _ -> if Enum.all?(parts, &is_atom/1), do: Module.concat(parts)
      end
    end

    defp expand_module(_blueprint, module) do
      case literal(module) do
        module when is_atom(module) and module not in [nil, :blocks] -> module
        _ -> nil
      end
    end

    # The belongs_to names in `join_module` whose foreign key is `key`, from
    # its Blueprint `relation :name, :belongs_to` or its Ecto `belongs_to`.
    defp belongs_to_names(_igniter, nil, _key), do: []

    defp belongs_to_names(igniter, join_module, key) do
      case ProjectModule.find_module(igniter, join_module) do
        {:ok, {_igniter, _source, zipper}} ->
          zipper
          |> Zipper.subtree()
          |> Common.find_all(
            &(CodeFunction.function_call?(&1, :relation, 3) or CodeFunction.function_call?(&1, :belongs_to))
          )
          |> Enum.flat_map(&belongs_to(single_child_node(&1)))
          |> Enum.filter(fn {_name, foreign_key} -> foreign_key == key end)
          |> Enum.map(&elem(&1, 0))
          |> Enum.uniq()

        _not_in_project ->
          []
      end
    end

    defp belongs_to({:relation, _, [name, type, options]}) do
      with :belongs_to <- literal(type), name when is_atom(name) and not is_nil(name) <- literal(name) do
        [{name, literal(option(options, :foreign_key)) || :"#{name}_id"}]
      else
        _ -> []
      end
    end

    defp belongs_to({:belongs_to, _, [name, _module | options]}) do
      case literal(name) do
        name when is_atom(name) and not is_nil(name) ->
          [{name, literal(option(List.first(options), :foreign_key)) || :"#{name}_id"}]

        _ ->
          []
      end
    end

    defp belongs_to(_node), do: []

    defp add_relation(options, relation) do
      {before, rest} = options |> keyword_entries() |> Enum.split_while(&(entry_key(&1) != :relation_key))
      {relation_key, rest} = Enum.split(rest, 1)
      entry = {{:__block__, [format: :keyword], [:relation]}, {:__block__, [], [relation]}}
      set_keyword_entries(options, before ++ relation_key ++ [entry | rest])
    end

    ## Entries sources

    # `{line => sources_ast}` for the inputs whose sources change, the changes,
    # and the sources it cannot read.
    defp entries_sources(zipper, path) do
      zipper
      |> inputs(:entries)
      |> Enum.flat_map(fn {line, name, options, _subform} ->
        case Enum.find(keyword_entries(options), &(entry_key(&1) in [:for, :sources])) do
          nil -> []
          option -> [{line, entries_source(path, line, name, option)}]
        end
      end)
      |> Enum.reduce({%{}, [], []}, fn {line, {update, input_changes, input_unresolved}},
                                       {updates, changes, unresolved} ->
        updates = if update, do: Map.put(updates, line, update), else: updates
        {updates, changes ++ input_changes, unresolved ++ input_unresolved}
      end)
    end

    # `{update | nil, changes, unresolved}` for one input's `for:`/`sources:`.
    defp entries_source(path, line, name, {key, value}) do
      location = "#{path}:#{line}: input #{inspect(name)}, :entries"

      case rewrite_sources(value) do
        {:ok, _sources, [], unreadable} ->
          {nil, [], Enum.map(unreadable, &"#{location}: #{&1}")}

        {:ok, sources, dropped, unreadable} ->
          {{key, sources}, ["#{location} dropped #{Enum.join(dropped, ", ")}"],
           Enum.map(unreadable, &"#{location}: #{&1}")}

        :error ->
          {nil, [], ["#{location}: `#{entry_key({key, value})}:` is not a literal list"]}
      end
    end

    defp rewrite_sources(value) do
      case unwrap(value) do
        sources when is_list(sources) ->
          {sources, {dropped, unreadable}} = Enum.map_reduce(sources, {[], []}, &rewrite_listed_source/2)

          {:ok, rewrap(value, sources), dropped, unreadable}

        _ ->
          :error
      end
    end

    defp rewrite_listed_source(source, {dropped, unreadable}) do
      case rewrite_source(source) do
        {:ok, source, source_dropped} -> {source, {dropped ++ source_dropped, unreadable}}
        :error -> {source, {dropped, unreadable ++ [Sourceror.to_string(source)]}}
      end
    end

    defp rewrite_source(source) do
      case unwrap(source) do
        {module, {:%{}, meta, pairs}} ->
          {pairs, dropped} =
            Enum.flat_map_reduce(pairs, [], fn pair, dropped ->
              {kept, reasons} = rewrite_option(pair)
              {kept, dropped ++ reasons}
            end)

          {:ok, rewrap(source, {module, {:%{}, meta, pairs}}), dropped}

        _ ->
          :error
      end
    end

    # `{pairs_kept, what_was_dropped}`
    defp rewrite_option({key_ast, value_ast} = pair) do
      key = literal(key_ast)
      shown = "`#{key}: #{Sourceror.to_string(value_ast)}`"

      case {key, evaluate(value_ast)} do
        {:preload, {:ok, []}} ->
          {[pair], []}

        {:order, {:ok, order}} ->
          rewrite_order(pair, order)

        {_key, {:ok, value}} ->
          if Check.source_option_problems({key, value}) == [], do: {[pair], []}, else: {[], [shown]}

        {key, :error} ->
          if key in Check.identifier_source_keys() and key != :preload, do: {[pair], []}, else: {[], [shown]}
      end
    end

    defp rewrite_order({key_ast, _value_ast} = pair, order) do
      dropped = Enum.map(Check.unknown_order_fields(order), &"`order` by #{&1}")

      case Check.identifier_order(order) do
        [order: ^order] -> {[pair], []}
        [order: kept] -> {[{key_ast, Sourceror.parse_string!(inspect(kept))}], dropped}
        [] -> {[], dropped}
      end
    end

    ## Notices

    defp notice(igniter, []), do: igniter

    defp notice(igniter, changes) do
      Igniter.add_notice(igniter, """
      Form inputs that crash the 0.54 admin form were changed:

      #{Enum.map_join(changes, "\n", &("  " <> &1))}

      A `:multi_select` on a has_many relation needs `relation:`, the join
      schema's belongs_to that `relation_key` points at; the task named it.
      An `:entries` input's `sources:` (0.53 `for:`) options filter and order
      the identifiers the entry picker lists, not the source schema, and
      identifiers have no associations and only the columns id, entry_id,
      schema, title, status, language, cover, url and updated_at. The task
      dropped the options identifiers do not have.
      """)
    end

    defp warning(igniter, []), do: igniter

    defp warning(igniter, unresolved) do
      Igniter.add_warning(igniter, """
      Form inputs the task could not complete; they fail the compile until fixed:

      #{Enum.map_join(unresolved, "\n", &("  " <> &1))}

      A `:multi_select` on a has_many relation takes `relation_key:` and
      `relation:`, as in `relation_key: :category_id, relation: :category`.
      An `:entries` input's `sources:` options apply to the identifiers it
      lists: `order:` by their columns, `status:`, `language:`, `limit:`.
      """)
    end

    ## AST helpers

    # `{line, name, options, subform}` of each `input name, type, options` in
    # the module, `subform` naming the `inputs_for` it is in, or nil.
    defp inputs(zipper, type) do
      zipper
      |> Zipper.subtree()
      |> Common.find_all(&CodeFunction.function_call?(&1, :input, 3))
      |> Enum.flat_map(fn input_zipper ->
        with {:input, meta, [name, input_type, options]} <- single_child_node(input_zipper),
             ^type <- literal(input_type),
             name when is_atom(name) and not is_nil(name) <- literal(name),
             true <- keyword_list?(options) do
          [{meta[:line], name, options, subform(input_zipper)}]
        else
          _ -> []
        end
      end)
    end

    defp subform(zipper) do
      case Zipper.up(zipper) do
        nil -> nil
        parent -> subform_name(Zipper.node(parent)) || subform(parent)
      end
    end

    defp subform_name({:inputs_for, _, [name | _]}), do: literal(name)
    defp subform_name(_node), do: nil

    defp single_child_node(zipper), do: zipper |> Common.maybe_move_to_single_child_block() |> Zipper.node()

    defp option(options, key) do
      if keyword_list?(options) do
        Enum.find_value(keyword_entries(options), fn {entry_key, value} -> literal(entry_key) == key && value end)
      end
    end

    defp entry_key({key, _value}), do: literal(key)

    defp keyword_list?(options) do
      entries = keyword_entries(options)
      is_list(entries) and Enum.all?(entries, &match?({_key, _value}, &1))
    end

    defp keyword_entries({:__block__, _, [entries]}) when is_list(entries), do: entries
    defp keyword_entries(entries) when is_list(entries), do: entries
    defp keyword_entries(_other), do: nil

    defp set_keyword_entries({:__block__, meta, [_entries]}, entries), do: {:__block__, meta, [entries]}
    defp set_keyword_entries(_entries, entries), do: entries

    defp unwrap({:__block__, _, [value]}), do: value
    defp unwrap(value), do: value

    defp rewrap({:__block__, meta, [_value]}, value), do: {:__block__, meta, [value]}
    defp rewrap(_original, value), do: value

    defp literal({:__block__, _, [value]}) when is_atom(value), do: value
    defp literal(value) when is_atom(value), do: value
    defp literal(_value), do: nil

    defp put_sources(options, {key, sources}) do
      entries =
        Enum.map(keyword_entries(options), fn {entry_key, _value} = entry ->
          if literal(entry_key) == literal(key), do: {entry_key, sources}, else: entry
        end)

      set_keyword_entries(options, entries)
    end

    # A literal value, read without running the application's code.
    defp evaluate(ast) do
      quoted = ast |> Sourceror.to_string() |> Code.string_to_quoted!()

      if Macro.quoted_literal?(quoted), do: {:ok, quoted |> Code.eval_quoted() |> elem(0)}, else: :error
    rescue
      _error -> :error
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.FormInputs do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
