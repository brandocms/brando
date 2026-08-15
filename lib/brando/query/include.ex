defmodule Brando.Query.Include do
  @moduledoc false

  import Ecto.Query, only: [exclude: 2, from: 2]

  alias Ecto.Query

  @allowed_options [:include, :order, :query, :select]

  def with_include(queryable, nil), do: Ecto.Queryable.to_query(queryable)

  def with_include(queryable, includes) do
    query = Ecto.Queryable.to_query(queryable)
    schema = query_schema!(query)
    includes = normalize_includes!(includes)

    ensure_unique_includes!(includes)
    ensure_no_preload_conflicts!(query, includes)

    Enum.reduce(includes, query, fn {name, options}, query ->
      association = association!(schema, name)
      ensure_owner_key_selected!(query, schema, name, association)
      query = add_include_to_map_selection(query, name, association.related, options)

      preload_query =
        association.related
        |> build_preload_query(name, options)

      from entry in query, preload: [{^name, ^preload_query}]
    end)
  end

  defp build_preload_query(related_schema, name, options) do
    options
    |> queryable(related_schema)
    |> Ecto.Queryable.to_query()
    |> ensure_query_schema!(related_schema, name)
    |> maybe_select(name, options)
    |> maybe_order(options)
    |> maybe_include(options)
  end

  defp queryable(%{query: nil}, related_schema), do: related_schema
  defp queryable(options, related_schema), do: Map.get(options, :query, related_schema)

  defp maybe_select(query, _name, %{select: nil}), do: query

  defp maybe_select(query, name, %{select: fields}) when is_list(fields) do
    if query.select do
      raise ArgumentError,
            "include #{inspect(name)} cannot specify :select because its custom query already has a select expression"
    end

    unless Enum.all?(fields, &is_atom/1) do
      raise ArgumentError,
            "include #{inspect(name)} expects :select to be a list of schema fields, got: #{inspect(fields)}"
    end

    from entry in query, select: ^fields
  end

  defp maybe_select(_query, name, %{select: fields}) do
    raise ArgumentError,
          "include #{inspect(name)} expects :select to be a list of schema fields, got: #{inspect(fields)}"
  end

  defp maybe_select(query, _name, _options), do: query

  defp maybe_order(query, %{order: nil}), do: query
  defp maybe_order(query, %{order: order}), do: Brando.Query.with_order(query, order)

  defp maybe_order(query, _options), do: query

  defp maybe_include(query, %{include: nil}), do: query
  defp maybe_include(query, %{include: includes}), do: with_include(query, includes)
  defp maybe_include(query, _options), do: query

  defp add_include_to_map_selection(
         %Query{select: %{expr: {:&, _, [0]}, take: %{0 => {:map, fields}}}} = query,
         name,
         related_schema,
         options
       ) do
    include_fields = include_selection_fields(related_schema, options)
    updated_fields = put_include_field(fields, name, include_fields)
    query = exclude(query, :select)

    from entry in query, select: map(entry, ^updated_fields)
  end

  defp add_include_to_map_selection(query, _name, _related_schema, _options), do: query

  defp include_selection_fields(schema, options) do
    fields = include_node_fields(schema, options)

    case Map.get(options, :include) do
      nil ->
        fields

      includes ->
        includes
        |> normalize_includes!()
        |> Enum.reduce(fields, fn {name, nested_options}, fields ->
          association = association!(schema, name)
          nested_fields = include_selection_fields(association.related, nested_options)
          put_include_field(fields, name, nested_fields)
        end)
    end
  end

  defp include_node_fields(_schema, %{select: fields}) when is_list(fields), do: fields

  defp include_node_fields(schema, %{query: queryable}) when not is_nil(queryable) do
    case queryable |> Ecto.Queryable.to_query() |> selected_source_fields() do
      :all ->
        schema.__schema__(:fields)

      {:fields, fields} ->
        fields

      :unsupported ->
        raise ArgumentError,
              "include map projections require custom queries to select their source schema"
    end
  end

  defp include_node_fields(schema, _options), do: schema.__schema__(:fields)

  defp put_include_field(fields, name, include_fields) do
    case Enum.find_index(fields, fn
           {^name, _fields} -> true
           _field -> false
         end) do
      nil ->
        fields ++ [{name, include_fields}]

      index ->
        List.update_at(fields, index, fn {^name, existing_fields} ->
          {name, merge_selection_fields(existing_fields, include_fields)}
        end)
    end
  end

  defp merge_selection_fields(existing_fields, additional_fields) do
    Enum.reduce(additional_fields, existing_fields, fn
      {name, nested_fields}, fields ->
        put_include_field(fields, name, nested_fields)

      field, fields ->
        if field in fields, do: fields, else: fields ++ [field]
    end)
  end

  defp normalize_includes!(includes) when is_map(includes) do
    includes
    |> Map.to_list()
    |> normalize_includes!()
  end

  defp normalize_includes!(includes) when is_list(includes) do
    Enum.map(includes, fn
      name when is_atom(name) ->
        {name, %{}}

      {name, options} when is_atom(name) ->
        {name, normalize_options!(name, options)}

      include ->
        raise ArgumentError,
              "include entries must be association names or {association, options} pairs, got: #{inspect(include)}"
    end)
  end

  defp normalize_includes!(includes) do
    raise ArgumentError,
          "include expects a list or map of associations, got: #{inspect(includes)}"
  end

  defp normalize_options!(name, options) when is_map(options) do
    validate_options!(options, name)
  end

  defp normalize_options!(name, options) when is_list(options) do
    if Keyword.keyword?(options) do
      options
      |> Map.new()
      |> validate_options!(name)
    else
      raise ArgumentError,
            "include #{inspect(name)} expects keyword or map options, got: #{inspect(options)}"
    end
  end

  defp normalize_options!(name, options) do
    raise ArgumentError,
          "include #{inspect(name)} expects keyword or map options, got: #{inspect(options)}"
  end

  defp validate_options!(options, name) when is_map(options) and is_atom(name) do
    unknown_options = (Map.keys(options) -- @allowed_options) |> Enum.sort()

    if unknown_options != [] do
      raise ArgumentError,
            "include #{inspect(name)} received unsupported options #{inspect(unknown_options)}; " <>
              "supported options are #{inspect(@allowed_options)}"
    end

    options
  end

  defp ensure_unique_includes!(includes) do
    names = Enum.map(includes, &elem(&1, 0))
    duplicate_names = names -- Enum.uniq(names)

    if duplicate_names != [] do
      raise ArgumentError,
            "include lists each association once; duplicated: #{inspect(Enum.uniq(duplicate_names))}"
    end
  end

  defp ensure_no_preload_conflicts!(query, includes) do
    include_names = MapSet.new(includes, &elem(&1, 0))
    existing_names = existing_preload_names(query)
    conflicts = existing_names |> MapSet.intersection(include_names) |> MapSet.to_list()

    if conflicts != [] do
      raise ArgumentError,
            "associations cannot be configured through both :preload and :include; " <>
              "conflicting associations: #{inspect(Enum.sort(conflicts))}"
    end
  end

  defp existing_preload_names(%Query{preloads: preloads, assocs: assocs}) do
    preload_names =
      Enum.map(preloads, fn
        name when is_atom(name) -> name
        {name, _preload} -> name
      end)

    assoc_names = Enum.map(assocs, &elem(&1, 0))
    MapSet.new(preload_names ++ assoc_names)
  end

  defp association!(schema, name) do
    case schema.__schema__(:association, name) do
      nil ->
        raise ArgumentError,
              "#{inspect(schema)} has no association named #{inspect(name)} for include"

      association ->
        association
    end
  end

  defp ensure_owner_key_selected!(query, schema, name, association) do
    case {Map.get(association, :owner_key), selected_source_fields(query)} do
      {nil, _fields} ->
        :ok

      {_owner_key, :all} ->
        :ok

      {owner_key, {:fields, fields}} ->
        unless owner_key in fields do
          raise ArgumentError,
                "include #{inspect(name)} requires #{inspect(owner_key)} to be selected from " <>
                  "#{inspect(schema)}"
        end

      {_owner_key, :unsupported} ->
        raise ArgumentError,
              "include #{inspect(name)} requires the parent query to select its source schema"
    end
  end

  defp selected_source_fields(%Query{select: nil}), do: :all

  defp selected_source_fields(%Query{select: %{take: take, expr: expression}}) do
    case take do
      %{0 => {_kind, fields}} when is_list(fields) ->
        {:fields, Enum.filter(fields, &is_atom/1)}

      _take ->
        if match?({:&, _, [0]}, expression), do: :all, else: :unsupported
    end
  end

  defp ensure_query_schema!(query, related_schema, name) do
    case query_schema!(query) do
      ^related_schema ->
        query

      query_schema ->
        raise ArgumentError,
              "include #{inspect(name)} expects a query for #{inspect(related_schema)}, " <>
                "got a query for #{inspect(query_schema)}"
    end
  end

  defp query_schema!(%Query{from: %{source: {_source, schema}}}) when is_atom(schema), do: schema

  defp query_schema!(query) do
    raise ArgumentError,
          "include requires a schema-backed query, got: #{inspect(query.from.source)}"
  end
end
