defmodule Brando.Blueprint.Verifier do
  @moduledoc false

  use Spark.Dsl.Verifier

  alias Brando.Blueprint.AssociationKey
  alias Brando.Blueprint.Config
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
  @relation_option_scopes [
    constraint_name: [:belongs_to],
    define_field: [:belongs_to],
    foreign_key: [:belongs_to, :has_many, :has_one],
    join_defaults: [:many_to_many],
    join_keys: [:many_to_many],
    join_through: [:many_to_many],
    join_where: [:many_to_many],
    references: [:belongs_to, :has_many, :has_one],
    through: [:has_many],
    type: [:belongs_to]
  ]
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
         :ok <- verify_assets(dsl_state, assets) do
      verify_storage_field_collisions(dsl_state, attributes, relations, assets)
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
    with :ok <- verify_attribute_type(dsl_state, attribute),
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

  defp verify_relation(dsl_state, relation, storage_columns) do
    with :ok <- verify_relation_module(dsl_state, relation),
         :ok <- verify_relation_options(dsl_state, relation),
         :ok <- verify_relation_cast(dsl_state, relation),
         :ok <- verify_unique(dsl_state, :relation, relation),
         :ok <- verify_unique_references(dsl_state, :relation, relation, storage_columns) do
      verify_constraints(dsl_state, :relation, relation)
    end
  end

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
    names = MapSet.new(attributes, & &1.name)

    Enum.reduce_while(renamed, MapSet.new(), fn attribute, sources ->
      source = attribute.opts.rename_from

      cond do
        not is_atom(source) ->
          {:halt, error(dsl_state, :attributes, attribute, "`:rename_from` must be an atom")}

        source == attribute.name ->
          {:halt, error(dsl_state, :attributes, attribute, "`:rename_from` cannot equal the attribute name")}

        MapSet.member?(names, source) ->
          {:halt,
           error(
             dsl_state,
             :attributes,
             attribute,
             "`:rename_from` points at declared attribute #{inspect(source)}; remove the old declaration when renaming"
           )}

        MapSet.member?(sources, source) ->
          {:halt,
           error(dsl_state, :attributes, attribute, "multiple attributes rename the same column #{inspect(source)}")}

        true ->
          {:cont, MapSet.put(sources, source)}
      end
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
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
    with :ok <- verify_boolean_option(dsl_state, :relations, relation, :required),
         :ok <- verify_boolean_option(dsl_state, :relations, relation, :define_field),
         :ok <- verify_atom_option(dsl_state, relation, :foreign_key),
         :ok <- verify_atom_option(dsl_state, relation, :references),
         :ok <- verify_string_option(dsl_state, relation, :constraint_name),
         :ok <- verify_string_option(dsl_state, relation, :required_message),
         :ok <- verify_string_option(dsl_state, relation, :invalid_message),
         :ok <- verify_boolean_option(dsl_state, :relations, relation, :force_update_on_change),
         :ok <- verify_atom_option(dsl_state, relation, :sort_param),
         :ok <- verify_atom_option(dsl_state, relation, :drop_param),
         :ok <- verify_relation_option_scopes(dsl_state, relation),
         :ok <- verify_through(dsl_state, relation) do
      verify_join_through(dsl_state, relation)
    end
  end

  defp verify_relation_option_scopes(dsl_state, %{type: type, opts: opts} = relation) do
    case Enum.find(@relation_option_scopes, fn {option, allowed_types} ->
           Map.has_key?(opts, option) and type not in allowed_types
         end) do
      nil ->
        :ok

      {option, allowed_types} ->
        error(
          dsl_state,
          :relations,
          relation,
          "`:#{option}` is only valid for #{format_relation_types(allowed_types)} relations"
        )
    end
  end

  defp format_relation_types([type]), do: inspect(type)
  defp format_relation_types(types), do: Enum.map_join(types, ", ", &inspect/1)

  defp verify_atom_option(dsl_state, %{opts: opts} = relation, option) do
    case Map.get(opts, option) do
      nil -> :ok
      value when is_atom(value) -> :ok
      value -> error(dsl_state, :relations, relation, "`:#{option}` must be an atom, got: #{inspect(value)}")
    end
  end

  defp verify_string_option(dsl_state, relation, option) do
    verify_string_option(dsl_state, :relations, relation, option)
  end

  defp verify_string_option(dsl_state, section, %{opts: opts} = entity, option) do
    case Map.get(opts, option) do
      nil -> :ok
      value when is_binary(value) -> :ok
      value -> error(dsl_state, section, entity, "`:#{option}` must be a string, got: #{inspect(value)}")
    end
  end

  defp verify_through(dsl_state, %{opts: opts} = relation) do
    case Map.get(opts, :through) do
      nil ->
        :ok

      through when relation.type == :has_many and is_list(through) and through != [] ->
        if Enum.all?(through, &is_atom/1) do
          :ok
        else
          error(dsl_state, :relations, relation, "`:through` must contain only relation atoms")
        end

      _through ->
        error(dsl_state, :relations, relation, "`:through` must be a non-empty atom list on a has-many relation")
    end
  end

  defp verify_join_through(dsl_state, %{opts: opts} = relation) do
    case Map.get(opts, :join_through) do
      nil ->
        :ok

      join_through when is_atom(join_through) or is_binary(join_through) ->
        :ok

      value ->
        error(dsl_state, :relations, relation, "`:join_through` must be a module or table name, got: #{inspect(value)}")
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
        :ok

      unknown ->
        error(
          dsl_state,
          section(kind),
          entity,
          "`:unique` references unknown persisted fields #{inspect(unknown)}"
        )
    end
  end

  defp unique_reference_fields(unique) when is_list(unique) do
    List.wrap(Keyword.get(unique, :with)) ++ collision_fields(Keyword.get(unique, :prevent_collision))
  end

  defp unique_reference_fields(_unique), do: []

  defp collision_fields(field) when is_atom(field) and field not in [nil, false, true], do: [field]
  defp collision_fields(fields) when is_list(fields), do: fields
  defp collision_fields(_value), do: []

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
    keys = Keyword.keys(unique)

    if Keyword.has_key?(unique, :prevent_collision) and keys != [:prevent_collision] do
      error(dsl_state, section(kind), entity, "`prevent_collision` cannot be combined with other unique options")
    else
      :ok
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

      {name, entity} ->
        error(dsl_state, entity_section(entity), entity, "declares duplicate Ecto field #{inspect(name)}")
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
