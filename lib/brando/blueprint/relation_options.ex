defmodule Brando.Blueprint.RelationOptions do
  @moduledoc false

  alias Brando.Blueprint.Relations.Relation

  @relation_types [:belongs_to, :embeds_many, :embeds_one, :entries, :has_many, :has_one, :many_to_many]
  @association_types [:belongs_to, :has_many, :has_one, :many_to_many]
  @has_types [:has_many, :has_one]
  @embed_types [:embeds_many, :embeds_one]

  @option_scopes [
    cast: @association_types,
    constraint_name: [:belongs_to],
    constraints: @relation_types,
    defaults: @association_types,
    defaults_to_struct: [:embeds_one],
    define_field: [:belongs_to],
    drop_param: [:embeds_many, :has_many],
    force_update_on_change: @relation_types -- [:many_to_many],
    foreign_key: [:belongs_to | @has_types],
    invalid_message: @relation_types,
    join_defaults: [:many_to_many],
    join_keys: [:many_to_many],
    join_through: [:many_to_many],
    join_where: [:many_to_many],
    load_in_query: @embed_types,
    module: @relation_types,
    null: [:belongs_to],
    on_delete: [:belongs_to, :has_many, :has_one, :many_to_many],
    on_replace: @association_types ++ @embed_types,
    preload_order: @has_types ++ [:many_to_many],
    primary_key: [:belongs_to],
    references: [:belongs_to | @has_types],
    required: @relation_types,
    required_message: @relation_types,
    sort_param: [:embeds_many, :has_many],
    source: [:belongs_to | @embed_types],
    through: @has_types,
    type: [:belongs_to],
    unique: [:belongs_to, :many_to_many],
    where: @association_types,
    with: [:belongs_to | @embed_types]
  ]
  @known_options Keyword.keys(@option_scopes)

  @has_on_delete [:delete_all, :nilify_all, :nothing]
  @many_to_many_on_delete [:delete_all, :nothing]
  @reference_on_delete [:default_all, :delete_all, :nilify_all, :nothing, :restrict]
  @many_on_replace [:delete, :delete_if_exists, :mark_as_invalid, :nilify, :raise]
  @one_on_replace [:update | @many_on_replace]
  @many_to_many_on_replace [:delete, :mark_as_invalid, :raise]
  @embed_many_on_replace [:delete, :mark_as_invalid, :raise]
  @embed_one_on_replace [:update | @embed_many_on_replace]
  @preload_directions [:asc, :asc_nulls_first, :asc_nulls_last, :desc, :desc_nulls_first, :desc_nulls_last]

  @doc false
  @spec validate(Relation.t()) :: :ok | {:error, String.t()}
  def validate(%Relation{type: type, opts: opts}) do
    with :ok <- validate_known_options(opts),
         :ok <- validate_option_scopes(type, opts),
         :ok <- validate_through_options(type, opts),
         :ok <- validate_boolean_options(type, opts),
         :ok <- validate_atom_options(opts),
         :ok <- validate_string_options(opts),
         :ok <- validate_on_delete(type, Map.get(opts, :on_delete)),
         :ok <- validate_on_replace(type, Map.get(opts, :on_replace)),
         :ok <- validate_through(type, Map.get(opts, :through)),
         :ok <- validate_join_through(Map.get(opts, :join_through)),
         :ok <- validate_join_keys(Map.get(opts, :join_keys)),
         :ok <- validate_keyword_option(opts, :where),
         :ok <- validate_keyword_option(opts, :join_where),
         :ok <- validate_defaults(opts, :defaults),
         :ok <- validate_defaults(opts, :join_defaults),
         :ok <- validate_preload_order(Map.get(opts, :preload_order)),
         :ok <- validate_with(type, Map.get(opts, :with)),
         :ok <- validate_many_to_many_unique(type, Map.get(opts, :unique)),
         :ok <- validate_required_cast(type, opts),
         :ok <- validate_cast_helper_options(type, opts),
         :ok <- validate_collection_controls(type, opts) do
      validate_through_cast(type, opts)
    end
  end

  defp validate_known_options(opts) do
    case opts |> Map.keys() |> Enum.sort() |> Kernel.--(@known_options) do
      [] -> :ok
      unknown -> {:error, "contains unsupported options #{inspect(unknown)}"}
    end
  end

  defp validate_option_scopes(type, opts) do
    case Enum.find(@option_scopes, fn {option, allowed_types} ->
           Map.has_key?(opts, option) and type not in allowed_types
         end) do
      nil ->
        :ok

      {option, allowed_types} ->
        {:error, "`:#{option}` is only valid for #{format_relation_types(allowed_types)} relations"}
    end
  end

  defp format_relation_types([type]), do: inspect(type)
  defp format_relation_types(types), do: Enum.map_join(types, ", ", &inspect/1)

  defp validate_through_options(type, %{through: _through} = opts) when type in @has_types do
    ignored_options =
      [:defaults, :foreign_key, :on_delete, :on_replace, :preload_order, :references, :where]
      |> Enum.filter(&Map.has_key?(opts, &1))

    case ignored_options do
      [] -> :ok
      options -> {:error, "`:through` relations do not support ignored Ecto options #{inspect(options)}"}
    end
  end

  defp validate_through_options(_type, _opts), do: :ok

  defp validate_boolean_options(type, opts) do
    boolean_options =
      [:force_update_on_change, :required] ++
        if(type == :belongs_to, do: [:define_field, :null, :primary_key], else: []) ++
        if(type in @embed_types, do: [:load_in_query], else: []) ++
        if(type == :embeds_one, do: [:defaults_to_struct], else: [])

    Enum.reduce_while(boolean_options, :ok, fn option, :ok ->
      case Map.get(opts, option) do
        value when value in [nil, false, true] -> {:cont, :ok}
        value -> {:halt, {:error, "`:#{option}` must be a boolean, got: #{inspect(value)}"}}
      end
    end)
  end

  defp validate_atom_options(opts) do
    Enum.reduce_while([:foreign_key, :references, :sort_param, :drop_param, :source, :type], :ok, fn option, :ok ->
      case Map.get(opts, option) do
        nil -> {:cont, :ok}
        value when is_atom(value) and value not in [false, true] -> {:cont, :ok}
        value -> {:halt, {:error, "`:#{option}` must be an atom, got: #{inspect(value)}"}}
      end
    end)
  end

  defp validate_string_options(opts) do
    Enum.reduce_while([:constraint_name, :invalid_message, :required_message], :ok, fn option, :ok ->
      case Map.get(opts, option) do
        nil -> {:cont, :ok}
        value when is_binary(value) -> {:cont, :ok}
        value -> {:halt, {:error, "`:#{option}` must be a string, got: #{inspect(value)}"}}
      end
    end)
  end

  defp validate_on_delete(_type, nil), do: :ok

  defp validate_on_delete(:belongs_to, value),
    do: enum_option(:on_delete, value, @reference_on_delete)

  defp validate_on_delete(type, value) when type in @has_types,
    do: enum_option(:on_delete, value, @has_on_delete)

  defp validate_on_delete(:many_to_many, value),
    do: enum_option(:on_delete, value, @many_to_many_on_delete)

  defp validate_on_delete(_type, _value), do: :ok

  defp validate_on_replace(_type, nil), do: :ok
  defp validate_on_replace(:belongs_to, value), do: enum_option(:on_replace, value, @one_on_replace)
  defp validate_on_replace(:has_one, value), do: enum_option(:on_replace, value, @one_on_replace)
  defp validate_on_replace(:has_many, value), do: enum_option(:on_replace, value, @many_on_replace)

  defp validate_on_replace(:many_to_many, value),
    do: enum_option(:on_replace, value, @many_to_many_on_replace)

  defp validate_on_replace(:embeds_one, value),
    do: enum_option(:on_replace, value, @embed_one_on_replace)

  defp validate_on_replace(:embeds_many, value),
    do: enum_option(:on_replace, value, @embed_many_on_replace)

  defp validate_on_replace(_type, _value), do: :ok

  defp enum_option(option, value, allowed) do
    if value in allowed do
      :ok
    else
      {:error, "`:#{option}` must be one of #{inspect(allowed)}, got: #{inspect(value)}"}
    end
  end

  defp validate_through(_type, nil), do: :ok

  defp validate_through(type, through) when type in @has_types and is_list(through) and through != [] do
    if Enum.all?(through, &valid_atom?/1) do
      :ok
    else
      {:error, "`:through` must contain only relation atoms"}
    end
  end

  defp validate_through(_type, _through),
    do: {:error, "`:through` must be a non-empty atom list on a has-one or has-many relation"}

  defp validate_join_through(nil), do: :ok
  defp validate_join_through(value) when is_binary(value) and value != "", do: :ok
  defp validate_join_through(value) when is_atom(value) and value not in [false, nil, true], do: :ok

  defp validate_join_through(value),
    do: {:error, "`:join_through` must be a module or non-empty table name, got: #{inspect(value)}"}

  defp validate_join_keys(nil), do: :ok

  defp validate_join_keys([{left_key, left_field}, {right_key, right_field}])
       when is_atom(left_key) and is_atom(left_field) and is_atom(right_key) and is_atom(right_field),
       do: :ok

  defp validate_join_keys(value) do
    {:error, "`:join_keys` must contain exactly two atom-to-atom entries, got: #{inspect(value)}"}
  end

  defp validate_keyword_option(opts, option) do
    case Map.get(opts, option) do
      nil -> :ok
      value when is_list(value) -> if(Keyword.keyword?(value), do: :ok, else: keyword_error(option, value))
      value -> keyword_error(option, value)
    end
  end

  defp keyword_error(option, value),
    do: {:error, "`:#{option}` must be a keyword list, got: #{inspect(value)}"}

  defp validate_defaults(opts, option) do
    validate_defaults_value(option, Map.get(opts, option))
  end

  defp validate_defaults_value(_option, nil), do: :ok

  defp validate_defaults_value(option, value) when is_list(value) do
    if Keyword.keyword?(value), do: :ok, else: defaults_error(option, value)
  end

  defp validate_defaults_value(_option, value) when is_atom(value) and value not in [false, true], do: :ok

  defp validate_defaults_value(_option, {module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: :ok

  defp validate_defaults_value(option, value), do: defaults_error(option, value)

  defp defaults_error(option, value) do
    {:error, "`:#{option}` must be a keyword list, function atom, or `{module, function, args}`, got: #{inspect(value)}"}
  end

  defp validate_preload_order(nil), do: :ok

  defp validate_preload_order({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: :ok

  defp validate_preload_order(order) when is_list(order) do
    if Enum.all?(order, &valid_preload_entry?/1) do
      :ok
    else
      preload_order_error(order)
    end
  end

  defp validate_preload_order(order), do: preload_order_error(order)

  defp valid_preload_entry?({direction, field}),
    do: direction in @preload_directions and valid_atom?(field)

  defp valid_preload_entry?(field) when is_atom(field), do: valid_atom?(field)
  defp valid_preload_entry?(_entry), do: false

  defp preload_order_error(order) do
    {:error,
     "`:preload_order` must be a list of fields/order pairs or `{module, function, args}`, got: #{inspect(order)}"}
  end

  defp validate_many_to_many_unique(:many_to_many, value) when value in [nil, false, true], do: :ok

  defp validate_many_to_many_unique(:many_to_many, value),
    do: {:error, "`:unique` must be a boolean for many-to-many relations, got: #{inspect(value)}"}

  defp validate_many_to_many_unique(_type, _value), do: :ok

  defp validate_with(_type, nil), do: :ok
  defp validate_with(:belongs_to, callback) when is_function(callback, 2), do: :ok
  defp validate_with(:embeds_one, callback) when is_function(callback, 2), do: :ok
  defp validate_with(:embeds_many, callback) when is_function(callback, 2) or is_function(callback, 3), do: :ok

  defp validate_with(type, callback),
    do: {:error, "`:with` has an invalid callback for #{inspect(type)}, got: #{inspect(callback)}"}

  defp validate_required_cast(type, %{required: true} = opts) when type in [:has_many, :has_one, :many_to_many] do
    if Map.get(opts, :cast) == true do
      :ok
    else
      {:error, "`:required` on #{inspect(type)} requires `cast: true` so the relation can be validated"}
    end
  end

  defp validate_required_cast(_type, _opts), do: :ok

  defp validate_cast_helper_options(type, opts) when type in @association_types do
    helper_options =
      [:force_update_on_change, :invalid_message, :required_message, :with]
      |> Enum.filter(&Map.has_key?(opts, &1))

    if helper_options == [] or Map.get(opts, :cast) == true do
      :ok
    else
      {:error, "#{inspect(helper_options)} require `cast: true` on #{inspect(type)} relations"}
    end
  end

  defp validate_cast_helper_options(_type, _opts), do: :ok

  defp validate_collection_controls(:has_many, opts) do
    controls = [:drop_param, :sort_param] |> Enum.filter(&Map.has_key?(opts, &1))

    if controls == [] or Map.get(opts, :cast) == true do
      :ok
    else
      {:error, "#{inspect(controls)} require `cast: true` on :has_many relations"}
    end
  end

  defp validate_collection_controls(_type, _opts), do: :ok

  defp validate_through_cast(type, %{through: _through, cast: true}) when type in @has_types do
    {:error, "`:through` relations cannot use `cast: true` because Ecto cannot cast through associations"}
  end

  defp validate_through_cast(_type, _opts), do: :ok

  defp valid_atom?(value), do: is_atom(value) and value not in [false, nil, true]
end
