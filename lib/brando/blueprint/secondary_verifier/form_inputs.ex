defmodule Brando.Blueprint.SecondaryVerifier.FormInputs do
  @moduledoc false
  # Input options the admin form needs, and that can be checked from the
  # Blueprint's own declarations while it compiles. Checks that need the
  # related schemas compiled are in `Brando.Blueprint.Forms.Verifier`.

  alias Brando.Blueprint.Forms
  alias Brando.Blueprint.SecondaryVerifier.Support
  alias Spark.Dsl.Verifier

  # `Brando.Content.Identifier`'s columns. Not read from the schema here: this
  # runs while every Blueprint compiles, so it depends on nothing it need not.
  @identifier_columns ~w(id entry_id schema title status language cover url updated_at)
  @orderable ["random" | @identifier_columns]
  # The keys of `sources:` options the identifier list query runs. It
  # crashes on the rest (`filter:`, `cache:`, …): identifiers have no filters,
  # no associations and no `deleted_at`.
  @identifier_source_keys [:order, :status, :language, :exclude_language, :limit, :offset, :preload]

  @doc "The columns of `Brando.Content.Identifier`, which `sources:` options can order by."
  def identifier_columns, do: @identifier_columns

  @doc "The `sources:` option keys the identifier list query runs."
  def identifier_source_keys, do: @identifier_source_keys

  @doc "The columns an `order` names that identifiers do not have."
  def unknown_order_fields(order), do: Enum.uniq(order_fields(order) -- @orderable)

  @doc false
  def verify(dsl_state) do
    relations = Verifier.get_entities(dsl_state, [:relations])

    for form <- Verifier.get_entities(dsl_state, [:forms]),
        tab <- form.tabs,
        fieldset <- tab.fields,
        %Forms.Input{} = input <- fieldset.fields do
      {[:forms, form.name, input.name], input}
    end
    |> Support.validate_entities(fn {path, input} ->
      with :ok <- verify_multi_select(dsl_state, path, relations, input) do
        verify_entries_sources(dsl_state, path, input)
      end
    end)
  end

  defp verify_multi_select(dsl_state, path, relations, %Forms.Input{type: :multi_select, name: name} = input) do
    with %{type: :has_many, opts: opts} <- Enum.find(relations, &(&1.name == name)),
         false <- Map.has_key?(opts, :through),
         problem when is_binary(problem) <- multi_select_problem(input, Map.get(opts, :module)) do
      Support.error(dsl_state, path, input, problem)
    else
      _ -> :ok
    end
  end

  defp verify_multi_select(_dsl_state, _path, _relations, _input), do: :ok

  @doc """
  What a multi select on the has_many relation to `join_schema` is missing,
  or nil. It writes the picked option's id to the join row's `relation_key`
  and reads the option through `relation`, the join schema's belongs_to.
  """
  def multi_select_problem(%Forms.Input{name: name, opts: opts}, join_schema) do
    relation_key = Keyword.get(opts || [], :relation_key)
    relation = Keyword.get(opts || [], :relation)
    subject = "input #{inspect(name)}, :multi_select on the :has_many relation #{inspect(name)} needs"

    case missing_multi_select_option(relation_key, relation) do
      nil -> nil
      missing -> "#{subject} #{missing_multi_select_hint(missing, relation_key, relation, join_belongs_to(join_schema))}"
    end
  end

  defp missing_multi_select_option(relation_key, relation) do
    case {relation_key in [nil, :id], is_nil(relation)} do
      {true, true} -> :both
      {true, false} -> :relation_key
      {false, true} -> :relation
      {false, false} -> nil
    end
  end

  defp missing_multi_select_hint(:both, _relation_key, _relation, belongs_to) do
    {key, field} = List.first(belongs_to) || {:category_id, :category}

    "`relation_key:` and `relation:`, the join schema's foreign key to the option " <>
      "and its belongs_to. Add them, as in `relation_key: #{inspect(key)}, relation: #{inspect(field)}`."
  end

  defp missing_multi_select_hint(:relation_key, _relation_key, relation, belongs_to) do
    key = Enum.find_value(belongs_to, fn {key, field} -> field == relation && key end) || "#{relation}_id"
    "`relation_key:`, the join schema's foreign key to the option. Add `relation_key: :#{key}`."
  end

  defp missing_multi_select_hint(:relation, relation_key, _relation, belongs_to) do
    field =
      Enum.find_value(belongs_to, fn {key, field} -> key == relation_key && field end) ||
        relation_key |> Atom.to_string() |> String.replace_suffix("_id", "")

    "`relation:`, the join schema's belongs_to that `relation_key: #{inspect(relation_key)}` " <>
      "points at. Add `relation: :#{field}`."
  end

  # `{foreign_key, name}` of each belongs_to. A join schema still compiling
  # gives none, and the hint follows the `<relation>_id` convention.
  defp join_belongs_to(join_schema) do
    if is_atom(join_schema) and Code.ensure_loaded?(join_schema) and function_exported?(join_schema, :__schema__, 2) do
      for association <- join_schema.__schema__(:associations),
          %Ecto.Association.BelongsTo{owner_key: key, field: field} <- [join_schema.__schema__(:association, association)],
          do: {key, field}
    else
      []
    end
  end

  # `sources:` options do not load the source schema's entries: the picker
  # lists their identifiers, and `Brando.Content.list_identifiers/2` runs the
  # options on `Brando.Content.Identifier`.
  defp verify_entries_sources(dsl_state, path, %Forms.Input{type: :entries, name: name, opts: opts} = input) do
    subject = "input #{inspect(name)}, :entries"
    example = ~s(`sources: [{MyApp.Articles.Article, %{order: "asc title"}}]`)

    case Keyword.get(opts || [], :sources) do
      sources when is_list(sources) ->
        if Enum.all?(sources, &match?({module, options} when is_atom(module) and is_map(options), &1)) do
          Support.validate_entities(sources, &verify_entries_source(dsl_state, path, input, subject, &1))
        else
          Support.error(
            dsl_state,
            path,
            input,
            "#{subject} `sources:` takes a list of {module, options} pairs, as in #{example}, got: #{inspect(sources)}"
          )
        end

      _missing ->
        Support.error(
          dsl_state,
          path,
          input,
          "#{subject} needs `sources:`, the schemas it offers entries of, as in #{example}"
        )
    end
  end

  defp verify_entries_sources(_dsl_state, _path, _input), do: :ok

  defp verify_entries_source(dsl_state, path, input, subject, {module, options}) do
    case Enum.flat_map(options, &identifier_source_problem/1) do
      [] ->
        :ok

      problems ->
        Support.error(dsl_state, path, input, """
        #{subject} has `sources:` options for #{inspect(module)} that the identifiers it lists do not take: \
        #{Enum.join(problems, ", ")}. The options filter and order the identifiers the entry picker offers \
        (`Brando.Content.Identifier`, with the columns #{Enum.join(@identifier_columns, ", ")}), \
        not #{inspect(module)} entries. Write `{#{inspect(module)}, #{inspect(identifier_source_options(options))}}`.\
        """)
    end
  end

  @doc "Why identifiers do not take the `sources:` option, or `[]` when they do."
  def source_option_problems(option), do: identifier_source_problem(option)

  # The list query reducer skips a nil option, and these ones.
  defp identifier_source_problem({_key, nil}), do: []
  defp identifier_source_problem({key, true}) when key in [:paginate, :with_deleted], do: []
  defp identifier_source_problem({key, _value}) when key in [:current_user, :status_counts], do: []
  defp identifier_source_problem({:preload, []}), do: []

  defp identifier_source_problem({:preload, preload}),
    do: ["`preload: #{inspect(preload)}` (identifiers have no associations)"]

  defp identifier_source_problem({:order, order}) do
    for field <- unknown_order_fields(order), do: "`order` by #{field} (not an identifier column)"
  end

  defp identifier_source_problem({key, _value}) when key in @identifier_source_keys, do: []
  defp identifier_source_problem({key, value}), do: ["`#{key}: #{inspect(value)}`"]

  # The options without what identifiers do not take.
  defp identifier_source_options(options) do
    options
    |> Enum.flat_map(fn
      {:preload, _preload} -> []
      {:order, order} -> identifier_order(order)
      {key, _value} = option -> if key in @identifier_source_keys, do: [option], else: []
    end)
    |> Map.new()
  end

  @doc "`[order: order]` without the columns identifiers do not have, or `[]` when none is left."
  def identifier_order(order) when is_binary(order) do
    case Enum.filter(order_segments(order), fn {_segment, field} -> field in @orderable end) do
      [] -> []
      kept -> [order: Enum.map_join(kept, ", ", &elem(&1, 0))]
    end
  end

  def identifier_order(order) when is_list(order) do
    case Enum.filter(order, &(order_fields(&1) -- @orderable == [])) do
      [] -> []
      kept -> [order: kept]
    end
  end

  def identifier_order({_direction, _field} = order) do
    case identifier_order([order]) do
      [order: [kept]] -> [order: kept]
      [] -> []
    end
  end

  def identifier_order(order), do: [order: order]

  # The columns an order names, as `Brando.Query`'s order reducer reads it.
  # An association path (`"asc category.name"`, `{:asc, {:category, :name}}`)
  # counts as its first segment, which identifiers do not have either.
  defp order_fields(order) when is_binary(order), do: Enum.map(order_segments(order), &elem(&1, 1))
  defp order_fields(order) when is_list(order), do: Enum.flat_map(order, &order_fields/1)
  defp order_fields({_direction, :random}), do: []
  defp order_fields({_direction, {:array_position, _ids}}), do: []
  defp order_fields({:array_position, _ids}), do: []
  defp order_fields({_modulo, :modulo}), do: ["inserted_at"]
  defp order_fields({_direction, field}) when is_atom(field), do: [Atom.to_string(field)]
  defp order_fields({_direction, path}) when is_tuple(path), do: [path |> elem(0) |> to_string()]
  defp order_fields(_order), do: []

  # `{segment, column}` of each comma-separated `"asc title"`.
  defp order_segments(order) do
    for segment <- String.split(order, ","),
        segment = String.trim(segment),
        segment != "" do
      field = segment |> String.split(~r/\s+/) |> List.last() |> String.split(".") |> hd()
      {segment, field}
    end
  end
end
