defmodule Brando.Blueprint.Verifier do
  @moduledoc false

  use Spark.Dsl.Verifier

  alias Brando.Blueprint.AssociationKey
  alias Brando.Blueprint.AttributeOptions
  alias Brando.Blueprint.Config
  alias Brando.Blueprint.DatabaseIdentifier
  alias Brando.Blueprint.RelationOptions
  alias Brando.Blueprint.UniqueFields
  alias Spark.Dsl.Entity
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @attribute_constraint_keys [:acceptance, :confirmation, :format, :length, :max_length, :min_length]
  @asset_option_keys [:cfg, :module, :required]
  @gallery_asset_option_keys [:force_update_on_change, :invalid_message, :required_message]
  @non_string_collision_types [
    :array,
    :boolean,
    :date,
    :datetime,
    :decimal,
    :enum,
    :file,
    :float,
    :i18n_string,
    :id,
    :integer,
    :language,
    :map,
    :naive_datetime,
    :status,
    :time,
    :timestamp,
    :uuid
  ]
  @relation_constraint_keys [:length, :max_length, :min_length, :require_blocks]
  @unique_keys [:message, :prevent_collision, :with]

  @impl true
  def verify(dsl_state) do
    attributes = Verifier.get_entities(dsl_state, [:attributes])
    relations = Verifier.get_entities(dsl_state, [:relations])
    assets = Verifier.get_entities(dsl_state, [:assets])
    storage_columns = storage_column_names(dsl_state, attributes, relations, assets)

    with :ok <- verify_blueprint_config(dsl_state),
         :ok <- verify_attributes(dsl_state, attributes, storage_columns),
         :ok <- verify_relations(dsl_state, relations, storage_columns),
         :ok <- verify_assets(dsl_state, assets),
         :ok <- verify_storage_field_collisions(dsl_state, attributes, relations, assets) do
      verify_storage_source_collisions(dsl_state, attributes, relations, assets)
    end
  end

  defp verify_blueprint_config(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    options = [
      application: Module.get_attribute(module, :application),
      domain: Module.get_attribute(module, :domain),
      schema: Module.get_attribute(module, :schema),
      singular: Module.get_attribute(module, :singular),
      plural: Module.get_attribute(module, :plural),
      router_scope: Module.get_attribute(module, :router_scope),
      gettext_module: Module.get_attribute(module, :gettext_module),
      data_layer: Module.get_attribute(module, :data_layer),
      table_name: Module.get_attribute(module, :table_name),
      primary_key: Module.get_attribute(module, :primary_key),
      allow_mark_as_deleted: Module.get_attribute(module, :allow_mark_as_deleted),
      factory: Module.get_attribute(module, :factory)
    ]

    case Config.validate_compiled_options(options) do
      :ok -> :ok
      {:error, message} -> root_error(dsl_state, message)
    end
  end

  defp verify_attributes(dsl_state, attributes, storage_columns) do
    case verify_renames(dsl_state, attributes) do
      :ok -> validate_entities(attributes, &verify_attribute(dsl_state, &1, storage_columns))
      error -> error
    end
  end

  defp verify_relations(dsl_state, relations, storage_columns) do
    validate_entities(relations, &verify_relation(dsl_state, &1, storage_columns))
  end

  defp verify_assets(dsl_state, assets) do
    validate_entities(assets, &verify_asset(dsl_state, &1))
  end

  defp verify_asset(dsl_state, asset) do
    with :ok <- verify_asset_options(dsl_state, asset),
         :ok <- verify_boolean_option(dsl_state, :assets, asset, :required) do
      verify_gallery_asset_options(dsl_state, asset)
    end
  end

  defp verify_asset_options(dsl_state, %{type: type, opts: opts} = asset) do
    allowed_options =
      if type == :gallery do
        @asset_option_keys ++ @gallery_asset_option_keys
      else
        @asset_option_keys
      end

    case opts |> Map.keys() |> Enum.sort() |> Kernel.--(allowed_options) do
      [] -> :ok
      unknown -> error(dsl_state, :assets, asset, "contains unsupported options #{inspect(unknown)}")
    end
  end

  defp verify_gallery_asset_options(dsl_state, %{type: :gallery} = asset) do
    with :ok <- verify_boolean_option(dsl_state, :assets, asset, :force_update_on_change),
         :ok <- verify_string_option(dsl_state, :assets, asset, :required_message) do
      verify_string_option(dsl_state, :assets, asset, :invalid_message)
    end
  end

  defp verify_gallery_asset_options(_dsl_state, _asset), do: :ok

  defp verify_attribute(dsl_state, attribute, storage_columns) do
    with :ok <- verify_attribute_options(dsl_state, attribute),
         :ok <- verify_attribute_type(dsl_state, attribute),
         :ok <- verify_attribute_source(dsl_state, attribute),
         :ok <- verify_boolean_option(dsl_state, :attributes, attribute, :required),
         :ok <- verify_boolean_option(dsl_state, :attributes, attribute, :virtual),
         :ok <- verify_unique(dsl_state, :attribute, attribute),
         :ok <- verify_persisted_unique(dsl_state, :attribute, attribute),
         :ok <- verify_collision_type(dsl_state, attribute),
         :ok <- verify_unique_references(dsl_state, :attribute, attribute, storage_columns) do
      verify_constraints(dsl_state, :attribute, attribute)
    end
  end

  defp verify_attribute_type(dsl_state, %{type: :array} = attribute) do
    error(dsl_state, :attributes, attribute, "bare `:array` is invalid; use `{:array, element_type}`")
  end

  defp verify_attribute_type(_dsl_state, _attribute), do: :ok

  defp verify_attribute_options(dsl_state, attribute) do
    case AttributeOptions.validate(attribute) do
      :ok -> :ok
      {:error, message} -> error(dsl_state, :attributes, attribute, message)
    end
  end

  defp verify_attribute_source(_dsl_state, %{opts: opts} = _attribute)
       when not is_map_key(opts, :source),
       do: :ok

  defp verify_attribute_source(_dsl_state, %{opts: %{source: nil}}), do: :ok

  defp verify_attribute_source(dsl_state, %{name: name, opts: %{source: _source}} = attribute)
       when name in [:inserted_at, :updated_at] do
    error(dsl_state, :attributes, attribute, "timestamp attributes do not support `:source`")
  end

  defp verify_attribute_source(dsl_state, %{opts: %{source: _source, virtual: true}} = attribute) do
    error(dsl_state, :attributes, attribute, "virtual attributes cannot declare a database `:source`")
  end

  defp verify_attribute_source(_dsl_state, %{opts: %{source: source}}) when is_atom(source), do: :ok

  defp verify_attribute_source(dsl_state, %{opts: %{source: source}} = attribute) do
    error(dsl_state, :attributes, attribute, "`:source` must be an atom, got: #{inspect(source)}")
  end

  defp verify_relation(dsl_state, relation, storage_columns) do
    with :ok <- verify_relation_module(dsl_state, relation),
         :ok <- verify_relation_options(dsl_state, relation),
         :ok <- verify_manual_belongs_to_field(dsl_state, relation, storage_columns),
         :ok <- verify_relation_cast(dsl_state, relation),
         :ok <- verify_relation_unique(dsl_state, relation),
         :ok <- verify_relation_unique_references(dsl_state, relation, storage_columns) do
      verify_constraints(dsl_state, :relation, relation)
    end
  end

  defp verify_manual_belongs_to_field(
         dsl_state,
         %Brando.Blueprint.Relations.Relation{
           name: name,
           type: :belongs_to,
           opts: %{define_field: false} = opts
         } = relation,
         storage_columns
       ) do
    field = Map.get(opts, :foreign_key, :"#{name}_id")
    misplaced_options = opts |> Map.keys() |> Enum.filter(&(&1 in [:null, :source])) |> Enum.sort()

    cond do
      misplaced_options != [] ->
        error(
          dsl_state,
          :relations,
          relation,
          "uses `define_field: false`; configure #{inspect(misplaced_options)} on foreign-key attribute #{inspect(field)}"
        )

      MapSet.member?(storage_columns, field) ->
        :ok

      true ->
        error(
          dsl_state,
          :relations,
          relation,
          "uses `define_field: false` but no persisted field #{inspect(field)} is declared"
        )
    end
  end

  defp verify_manual_belongs_to_field(_dsl_state, _relation, _storage_columns), do: :ok

  defp verify_boolean_option(dsl_state, section, %{opts: opts} = entity, option) do
    case Map.get(opts, option) do
      value when value in [nil, false, true] ->
        :ok

      value ->
        error(dsl_state, section, entity, "`:#{option}` must be a boolean, got: #{inspect(value)}")
    end
  end

  defp validate_entities(entities, validator) do
    Enum.reduce_while(entities, :ok, fn entity, :ok ->
      case validator.(entity) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_renames(dsl_state, attributes) do
    renamed = Enum.filter(attributes, &Map.has_key?(&1.opts, :rename_from))

    storage_names =
      MapSet.new(attributes, fn attribute -> Map.get(attribute.opts, :source) || attribute.name end)

    Enum.reduce_while(renamed, MapSet.new(), &verify_rename(dsl_state, &1, &2, storage_names))
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  defp verify_rename(dsl_state, attribute, sources, storage_names) do
    source = attribute.opts.rename_from
    target = Map.get(attribute.opts, :source) || attribute.name

    cond do
      not is_atom(source) ->
        {:halt, error(dsl_state, :attributes, attribute, "`:rename_from` must be an atom")}

      source == target ->
        {:halt, error(dsl_state, :attributes, attribute, "`:rename_from` cannot equal the database column name")}

      MapSet.member?(storage_names, source) ->
        {:halt,
         error(
           dsl_state,
           :attributes,
           attribute,
           "`:rename_from` points at declared attribute #{inspect(source)}; remove the old declaration when renaming"
         )}

      MapSet.member?(sources, source) ->
        {:halt, error(dsl_state, :attributes, attribute, "multiple attributes rename the same column #{inspect(source)}")}

      true ->
        {:cont, MapSet.put(sources, source)}
    end
  end

  defp verify_relation_module(dsl_state, %{opts: opts} = relation) do
    with :ok <- verify_relation_module_value(dsl_state, relation),
         :ok <- verify_special_relation_module(dsl_state, relation) do
      verify_many_to_many_join(dsl_state, relation, opts)
    end
  end

  defp verify_relation_module_value(dsl_state, %{opts: opts} = relation) do
    case Map.fetch(opts, :module) do
      :error ->
        error(dsl_state, :relations, relation, "requires a `:module` option")

      {:ok, module} when is_atom(module) and module not in [nil, false, true] ->
        :ok

      {:ok, _invalid_module} ->
        error(dsl_state, :relations, relation, "`:module` must be a module atom")
    end
  end

  defp verify_special_relation_module(dsl_state, %{type: type, opts: %{module: :blocks}} = relation)
       when type != :has_many,
       do: error(dsl_state, :relations, relation, "`:blocks` modules are only valid for has-many relations")

  defp verify_special_relation_module(
         dsl_state,
         %{name: name, type: type, opts: %{module: :alternates}} = relation
       )
       when type != :has_many or name != :alternates do
    error(
      dsl_state,
      :relations,
      relation,
      "`:alternates` is only valid for a has-many relation named `:alternates`"
    )
  end

  defp verify_special_relation_module(_dsl_state, _relation), do: :ok

  defp verify_many_to_many_join(dsl_state, %{type: :many_to_many} = relation, opts) do
    if is_nil(Map.get(opts, :join_through)) do
      error(dsl_state, :relations, relation, "many-to-many relations require `:join_through`")
    else
      :ok
    end
  end

  defp verify_many_to_many_join(_dsl_state, _relation, _opts), do: :ok

  defp verify_relation_options(dsl_state, relation) do
    case RelationOptions.validate(relation) do
      :ok -> :ok
      {:error, message} -> error(dsl_state, :relations, relation, message)
    end
  end

  defp verify_string_option(dsl_state, section, %{opts: opts} = entity, option) do
    case Map.get(opts, option) do
      nil -> :ok
      value when is_binary(value) -> :ok
      value -> error(dsl_state, section, entity, "`:#{option}` must be a string, got: #{inspect(value)}")
    end
  end

  defp verify_relation_cast(dsl_state, %{opts: opts} = relation) do
    case Map.get(opts, :cast) do
      cast when cast in [nil, false, true] ->
        :ok

      :with_user when relation.type == :belongs_to ->
        :ok

      cast when relation.type == :belongs_to and is_list(cast) ->
        verify_cast_callback(dsl_state, relation, cast)

      _ ->
        invalid_cast(dsl_state, relation)
    end
  end

  defp verify_cast_callback(_dsl_state, _relation, with: {module, function})
       when is_atom(module) and is_atom(function),
       do: :ok

  defp verify_cast_callback(_dsl_state, _relation, with: {module, function, [with_user: true]})
       when is_atom(module) and is_atom(function),
       do: :ok

  defp verify_cast_callback(dsl_state, relation, _cast), do: invalid_cast(dsl_state, relation)

  defp invalid_cast(dsl_state, relation) do
    error(
      dsl_state,
      :relations,
      relation,
      "has an unsupported `:cast` option; use a boolean or a belongs-to `with: {Module, :function}` callback"
    )
  end

  defp verify_relation_unique(_dsl_state, %{type: :many_to_many}), do: :ok
  defp verify_relation_unique(dsl_state, relation), do: verify_unique(dsl_state, :relation, relation)

  defp verify_relation_unique_references(_dsl_state, %{type: :many_to_many}, _storage_columns), do: :ok

  defp verify_relation_unique_references(dsl_state, relation, storage_columns) do
    verify_unique_references(dsl_state, :relation, relation, storage_columns)
  end

  defp verify_unique(dsl_state, kind, %{opts: opts} = entity) do
    case Map.get(opts, :unique) do
      unique when unique in [nil, false] ->
        :ok

      true ->
        verify_unique_scope(dsl_state, kind, entity, [])

      unique when is_list(unique) ->
        verify_unique_options(dsl_state, kind, entity, unique)

      _ ->
        error(dsl_state, section(kind), entity, "`:unique` must be a boolean or keyword list")
    end
  end

  defp verify_persisted_unique(dsl_state, :attribute, %{opts: %{virtual: true, unique: unique}} = entity)
       when unique not in [nil, false] do
    error(dsl_state, :attributes, entity, "virtual attributes cannot be unique")
  end

  defp verify_persisted_unique(_dsl_state, _kind, _entity), do: :ok

  defp verify_collision_type(dsl_state, %{type: type, opts: opts} = attribute) do
    unique = Map.get(opts, :unique)

    if collision_configured?(unique) and not string_collision_type?(type) do
      error(
        dsl_state,
        :attributes,
        attribute,
        "`prevent_collision` requires a string, text, slug, or string-backed custom type"
      )
    else
      :ok
    end
  end

  defp collision_configured?(unique) when is_list(unique), do: Keyword.has_key?(unique, :prevent_collision)
  defp collision_configured?(_unique), do: false

  defp string_collision_type?(type) when type in [:slug, :string, :text], do: true

  defp string_collision_type?(type) do
    not (type in @non_string_collision_types or match?({:array, _}, type))
  end

  defp verify_unique_references(dsl_state, kind, %{opts: opts} = entity, storage_columns) do
    referenced_fields = unique_reference_fields(Map.get(opts, :unique))

    unknown_fields =
      referenced_fields
      |> Enum.reject(&MapSet.member?(storage_columns, &1))
      |> Enum.uniq()

    case unknown_fields do
      [] ->
        verify_unique_field_repetition(dsl_state, kind, entity, referenced_fields)

      unknown ->
        error(
          dsl_state,
          section(kind),
          entity,
          "`:unique` references unknown persisted fields #{inspect(unknown)}"
        )
    end
  end

  defp verify_unique_field_repetition(dsl_state, kind, entity, referenced_fields) do
    repeated_fields =
      [unique_base_field(kind, entity) | referenced_fields]
      |> Enum.frequencies()
      |> Enum.filter(fn {_field, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case repeated_fields do
      [] ->
        :ok

      repeated ->
        error(
          dsl_state,
          section(kind),
          entity,
          "`:unique` repeats persisted fields #{inspect(repeated)}; " <>
            "scope fields must be distinct and cannot repeat the unique field"
        )
    end
  end

  defp unique_base_field(:attribute, %{name: name}), do: name

  defp unique_base_field(:relation, %{type: type, name: name, opts: opts}) when is_atom(type),
    do: AssociationKey.for(%{type: type, name: name, opts: opts})

  defp unique_reference_fields(unique) when is_list(unique) do
    UniqueFields.scope(unique, Keyword.get(unique, :prevent_collision))
  end

  defp unique_reference_fields(_unique), do: []

  defp verify_unique_options(dsl_state, kind, entity, unique) do
    if Keyword.keyword?(unique) do
      do_verify_unique_options(dsl_state, kind, entity, unique)
    else
      error(dsl_state, section(kind), entity, "`:unique` must be a keyword list")
    end
  end

  defp do_verify_unique_options(dsl_state, kind, entity, unique) do
    with :ok <- verify_unique_keys(dsl_state, kind, entity, unique),
         :ok <- verify_unique_scope(dsl_state, kind, entity, unique),
         :ok <- verify_collision_combination(dsl_state, kind, entity, unique),
         :ok <- verify_unique_message(dsl_state, kind, entity, unique),
         :ok <- verify_unique_fields(dsl_state, kind, entity, unique) do
      verify_collision_value(dsl_state, kind, entity, unique)
    end
  end

  defp verify_unique_keys(dsl_state, kind, entity, unique) do
    case Keyword.keys(unique) -- @unique_keys do
      [] -> :ok
      unknown -> error(dsl_state, section(kind), entity, "`:unique` contains unsupported options #{inspect(unknown)}")
    end
  end

  defp verify_unique_scope(dsl_state, :relation, %{type: type} = entity, _unique) when type != :belongs_to,
    do: error(dsl_state, :relations, entity, "only belongs-to relations can be unique")

  defp verify_unique_scope(dsl_state, :relation, entity, unique) do
    if Keyword.has_key?(unique, :prevent_collision) do
      error(dsl_state, :relations, entity, "relations do not support `unique: [prevent_collision: ...]`")
    else
      :ok
    end
  end

  defp verify_unique_scope(_dsl_state, _kind, _entity, _unique), do: :ok

  defp verify_collision_combination(dsl_state, kind, entity, unique) do
    case Keyword.fetch(unique, :prevent_collision) do
      {:ok, collision_callback} when is_function(collision_callback, 1) ->
        verify_collision_keys(dsl_state, kind, entity, unique, [:prevent_collision, :with, :message])

      {:ok, _collision_scope} ->
        verify_collision_keys(dsl_state, kind, entity, unique, [:prevent_collision])

      :error ->
        :ok
    end
  end

  defp verify_collision_keys(dsl_state, kind, entity, unique, allowed_keys) do
    case Keyword.keys(unique) -- allowed_keys do
      [] ->
        :ok

      _unsupported ->
        error(
          dsl_state,
          section(kind),
          entity,
          "`prevent_collision` can only be combined with `:with` and `:message` for an arity-one callback"
        )
    end
  end

  defp verify_unique_message(dsl_state, kind, entity, unique) do
    if valid_message?(Keyword.get(unique, :message)) do
      :ok
    else
      error(dsl_state, section(kind), entity, "the unique `:message` must be a string")
    end
  end

  defp verify_unique_fields(dsl_state, kind, entity, unique) do
    if valid_fields?(Keyword.get(unique, :with)) do
      :ok
    else
      error(dsl_state, section(kind), entity, "the unique `:with` option must be an atom or a list of atoms")
    end
  end

  defp verify_collision_value(dsl_state, kind, entity, unique) do
    if valid_collision?(Keyword.get(unique, :prevent_collision)) do
      :ok
    else
      error(
        dsl_state,
        section(kind),
        entity,
        "`prevent_collision` must be true, a field atom, a list of field atoms, or an arity-one function"
      )
    end
  end

  defp valid_message?(nil), do: true
  defp valid_message?(message), do: is_binary(message)

  defp valid_fields?(nil), do: true
  defp valid_fields?(field), do: is_atom(field) or (is_list(field) and field != [] and Enum.all?(field, &is_atom/1))

  defp valid_collision?(nil), do: true
  defp valid_collision?(true), do: true
  defp valid_collision?(field) when is_atom(field) and field not in [false, nil], do: true
  defp valid_collision?(fields) when is_list(fields), do: fields != [] and Enum.all?(fields, &is_atom/1)
  defp valid_collision?(function) when is_function(function, 1), do: true
  defp valid_collision?(_), do: false

  defp verify_constraints(dsl_state, kind, %{opts: opts} = entity) do
    case Map.get(opts, :constraints) do
      nil ->
        :ok

      constraints when is_list(constraints) ->
        verify_constraint_options(dsl_state, kind, entity, constraints)

      _ ->
        error(dsl_state, section(kind), entity, "`:constraints` must be a keyword list")
    end
  end

  defp verify_constraint_options(dsl_state, kind, entity, constraints) do
    if Keyword.keyword?(constraints) do
      do_verify_constraint_options(dsl_state, kind, entity, constraints)
    else
      error(dsl_state, section(kind), entity, "`:constraints` must be a keyword list")
    end
  end

  defp do_verify_constraint_options(dsl_state, kind, entity, constraints) do
    allowed = if kind == :attribute, do: @attribute_constraint_keys, else: @relation_constraint_keys
    unknown = Keyword.keys(constraints) -- allowed

    if unknown == [] do
      verify_constraint_values(dsl_state, kind, entity, constraints)
    else
      error(dsl_state, section(kind), entity, "`:constraints` contains unsupported options #{inspect(unknown)}")
    end
  end

  defp verify_constraint_values(dsl_state, kind, entity, constraints) do
    Enum.reduce_while(constraints, :ok, fn constraint, :ok ->
      if valid_constraint?(kind, entity, constraint) do
        {:cont, :ok}
      else
        {:halt, error(dsl_state, section(kind), entity, invalid_constraint_message(constraint))}
      end
    end)
  end

  defp valid_constraint?(:attribute, _, {key, value}) when key in [:length, :max_length, :min_length],
    do: is_integer(value) and value >= 0

  defp valid_constraint?(:relation, %{type: type}, {key, value})
       when type in [:has_many, :many_to_many, :embeds_many, :entries] and
              key in [:length, :max_length, :min_length],
       do: is_integer(value) and value >= 0

  defp valid_constraint?(:attribute, _, {:format, %Regex{}}), do: true
  defp valid_constraint?(:attribute, _, {key, true}) when key in [:acceptance, :confirmation], do: true

  defp valid_constraint?(:relation, %{opts: %{module: :blocks}}, {:require_blocks, classes}),
    do: is_list(classes) and Enum.all?(classes, &is_binary/1)

  defp valid_constraint?(_, _, _), do: false

  defp invalid_constraint_message({key, value}),
    do: "constraint #{inspect(key)} has an unsupported value #{inspect(value)}"

  defp verify_storage_field_collisions(dsl_state, attributes, relations, assets) do
    fields =
      Enum.map(attributes, &{&1.name, &1}) ++
        Enum.flat_map(relations, &relation_ecto_fields/1) ++
        Enum.flat_map(assets, &asset_ecto_fields/1) ++
        primary_key_field(dsl_state)

    frequencies = fields |> Enum.map(&elem(&1, 0)) |> Enum.frequencies()

    case Enum.find(fields, fn {name, _entity} -> Map.fetch!(frequencies, name) > 1 end) do
      nil ->
        :ok

      {name, :primary_key} ->
        root_error(
          dsl_state,
          "the primary key declares duplicate database source #{inspect(DatabaseIdentifier.normalize(name))}"
        )

      {name, entity} ->
        error(dsl_state, entity_section(entity), entity, "declares duplicate Ecto field #{inspect(name)}")
    end
  end

  defp verify_storage_source_collisions(dsl_state, attributes, relations, assets) do
    columns =
      attribute_database_columns(attributes) ++
        relation_database_columns(relations) ++
        Enum.map(assets, &{:"#{&1.name}_id", &1}) ++
        primary_key_database_column(dsl_state)

    frequencies =
      columns
      |> Enum.map(fn {name, _entity} -> DatabaseIdentifier.normalize(name) end)
      |> Enum.frequencies()

    case Enum.find(columns, fn {name, _entity} ->
           Map.fetch!(frequencies, DatabaseIdentifier.normalize(name)) > 1
         end) do
      nil ->
        :ok

      {name, entity} ->
        error(
          dsl_state,
          entity_section(entity),
          entity,
          "declares duplicate database source #{inspect(DatabaseIdentifier.normalize(name))}"
        )
    end
  end

  defp attribute_database_columns(attributes) do
    attributes
    |> Enum.reject(&(Map.get(&1.opts, :virtual) == true))
    |> Enum.map(&{Map.get(&1.opts, :source) || &1.name, &1})
  end

  defp relation_database_columns(relations) do
    Enum.flat_map(relations, fn
      %{type: :belongs_to, opts: %{define_field: false}} ->
        []

      %{type: :belongs_to, opts: opts} = relation ->
        [{Map.get(opts, :source) || AssociationKey.for(relation), relation}]

      %{type: type, name: name, opts: opts} = relation when type in [:embeds_one, :embeds_many] ->
        [{Map.get(opts, :source) || name, relation}]

      %{type: :has_many, name: name, opts: %{module: :blocks}} = relation ->
        [{:"rendered_#{name}", relation}, {:"rendered_#{name}_at", relation}]

      _relation ->
        []
    end)
  end

  defp primary_key_database_column(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    case Module.get_attribute(module, :primary_key) do
      false -> []
      {name, _type, opts} -> [{Keyword.get(opts, :source) || name, :primary_key}]
      _default -> [{:id, :primary_key}]
    end
  end

  defp relation_ecto_fields(%{type: :belongs_to, name: name, opts: %{define_field: false}} = relation) do
    [{name, relation}]
  end

  defp relation_ecto_fields(%{type: :belongs_to, name: name} = relation) do
    [{name, relation}, {AssociationKey.for(relation), relation}]
  end

  defp relation_ecto_fields(%{type: :has_many, name: name, opts: %{module: :blocks}} = relation) do
    [
      {String.to_atom("rendered_#{name}"), relation},
      {String.to_atom("rendered_#{name}_at"), relation},
      {String.to_atom("entry_#{name}"), relation}
    ]
  end

  defp relation_ecto_fields(%{type: :has_many, name: :alternates, opts: %{module: :alternates}} = relation) do
    [{:alternates, relation}, {:alternate_entries, relation}]
  end

  defp relation_ecto_fields(%{name: name} = relation), do: [{name, relation}]

  defp asset_ecto_fields(%{name: name} = asset),
    do: [{name, asset}, {String.to_atom("#{name}_id"), asset}]

  defp storage_column_names(dsl_state, attributes, relations, assets) do
    attribute_columns =
      attributes
      |> Enum.reject(&(Map.get(&1.opts, :virtual) == true))
      |> Enum.map(& &1.name)

    relation_columns = Enum.flat_map(relations, &relation_storage_columns/1)
    asset_columns = Enum.map(assets, &String.to_atom("#{&1.name}_id"))
    primary_key_columns = Enum.map(primary_key_field(dsl_state), &elem(&1, 0))

    MapSet.new(attribute_columns ++ relation_columns ++ asset_columns ++ primary_key_columns)
  end

  defp relation_storage_columns(%{type: :belongs_to, opts: %{define_field: false}}), do: []
  defp relation_storage_columns(%{type: :belongs_to} = relation), do: [AssociationKey.for(relation)]

  defp relation_storage_columns(%{type: type, name: name}) when type in [:embeds_one, :embeds_many],
    do: [name]

  defp relation_storage_columns(%{type: :has_many, name: name, opts: %{module: :blocks}}),
    do: [String.to_atom("rendered_#{name}"), String.to_atom("rendered_#{name}_at")]

  defp relation_storage_columns(_relation), do: []

  defp primary_key_field(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    case Module.get_attribute(module, :primary_key) do
      false -> []
      {name, _type, _opts} when is_atom(name) -> [{name, :primary_key}]
      _default -> [{:id, :primary_key}]
    end
  end

  defp entity_section(%Brando.Blueprint.Attributes.Attribute{}), do: :attributes
  defp entity_section(%Brando.Blueprint.Relations.Relation{}), do: :relations
  defp entity_section(%Brando.Blueprint.Assets.Asset{}), do: :assets

  defp section(:attribute), do: :attributes
  defp section(:relation), do: :relations

  defp error(dsl_state, section, entity, message) do
    {:error,
     DslError.exception(
       module: Verifier.get_persisted(dsl_state, :module),
       path: [section, entity.name],
       location: Entity.anno(entity),
       message: "#{inspect(entity.name)} #{message}"
     )}
  end

  defp root_error(dsl_state, message) do
    {:error,
     DslError.exception(
       module: Verifier.get_persisted(dsl_state, :module),
       path: [:blueprint],
       message: message
     )}
  end
end
