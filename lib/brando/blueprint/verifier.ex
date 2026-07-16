defmodule Brando.Blueprint.Verifier do
  @moduledoc false

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Entity
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @attribute_constraint_keys [:acceptance, :confirmation, :format, :length, :max_length, :min_length]
  @relation_constraint_keys [:length, :max_length, :min_length, :require_blocks]
  @unique_keys [:message, :prevent_collision, :with]

  @impl true
  def verify(dsl_state) do
    attributes = Verifier.get_entities(dsl_state, [:attributes])
    relations = Verifier.get_entities(dsl_state, [:relations])
    assets = Verifier.get_entities(dsl_state, [:assets])

    with :ok <- verify_attributes(dsl_state, attributes),
         :ok <- verify_relations(dsl_state, relations) do
      verify_storage_field_collisions(dsl_state, attributes, relations, assets)
    end
  end

  defp verify_attributes(dsl_state, attributes) do
    case verify_renames(dsl_state, attributes) do
      :ok -> validate_entities(attributes, &verify_attribute(dsl_state, &1))
      error -> error
    end
  end

  defp verify_relations(dsl_state, relations) do
    validate_entities(relations, &verify_relation(dsl_state, &1))
  end

  defp verify_attribute(dsl_state, attribute) do
    with :ok <- verify_unique(dsl_state, :attribute, attribute) do
      verify_constraints(dsl_state, :attribute, attribute)
    end
  end

  defp verify_relation(dsl_state, relation) do
    with :ok <- verify_relation_module(dsl_state, relation),
         :ok <- verify_relation_cast(dsl_state, relation),
         :ok <- verify_unique(dsl_state, :relation, relation) do
      verify_constraints(dsl_state, :relation, relation)
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
    cond do
      not Map.has_key?(opts, :module) ->
        error(dsl_state, :relations, relation, "requires a `:module` option")

      relation.type == :many_to_many and not Map.has_key?(opts, :join_through) ->
        error(dsl_state, :relations, relation, "many-to-many relations require `:join_through`")

      true ->
        :ok
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
      unique when unique in [nil, false, true] ->
        :ok

      unique when is_list(unique) ->
        verify_unique_options(dsl_state, kind, entity, unique)

      _ ->
        error(dsl_state, section(kind), entity, "`:unique` must be a boolean or keyword list")
    end
  end

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
        "`prevent_collision` must be true, a field atom, a list of field atoms, or a function"
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
  defp valid_collision?(function) when is_function(function), do: true
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

  defp valid_constraint?(_, _, {key, value}) when key in [:length, :max_length, :min_length],
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
        Enum.flat_map(assets, &asset_ecto_fields/1)

    frequencies = fields |> Enum.map(&elem(&1, 0)) |> Enum.frequencies()

    case Enum.find(fields, fn {name, _entity} -> Map.fetch!(frequencies, name) > 1 end) do
      nil ->
        :ok

      {name, entity} ->
        error(dsl_state, entity_section(entity), entity, "declares duplicate Ecto field #{inspect(name)}")
    end
  end

  defp relation_ecto_fields(%{type: :belongs_to, name: name, opts: opts} = relation) do
    foreign_key = Map.get(opts, :foreign_key, String.to_atom("#{name}_id"))
    [{name, relation}, {foreign_key, relation}]
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
end
