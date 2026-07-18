defmodule Brando.Blueprint.Unique do
  @moduledoc """
  Applies the runtime uniqueness contract declared by a Blueprint.

  Attribute and belongs-to constraints use the same persisted field ordering
  as Blueprint migration indexes. Collision callbacks may declare persisted
  scope fields with `:with`; those fields constrain both the callback query and
  the database constraint.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint.AssociationKey
  alias Brando.Blueprint.Collision
  alias Brando.Blueprint.DatabaseIdentifier
  alias Brando.Blueprint.UniqueFields
  alias Ecto.Changeset

  @doc """
  Adds configured unique attribute constraints and collision preparation.
  """
  @spec run_unique_attribute_constraints(Changeset.t(), module(), [map()]) :: Changeset.t()
  def run_unique_attribute_constraints(changeset, module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :unique, false))
    |> Enum.reduce(changeset, fn attribute, current_changeset ->
      apply_attribute_constraint(current_changeset, module, attribute)
    end)
  end

  @doc """
  Adds configured unique constraints for persisted belongs-to foreign keys.
  """
  @spec run_unique_relation_constraints(Changeset.t(), module(), [map()]) :: Changeset.t()
  def run_unique_relation_constraints(changeset, _module, relations) do
    relations
    |> Enum.filter(&(&1.type == :belongs_to and Map.get(&1.opts, :unique, false)))
    |> Enum.reduce(changeset, fn relation, current_changeset ->
      add_unique_constraint(
        current_changeset,
        AssociationKey.for(relation),
        relation.opts.unique
      )
    end)
  end

  defp apply_attribute_constraint(changeset, _module, %{name: field, opts: %{unique: true}}) do
    add_unique_constraint(changeset, field, true)
  end

  defp apply_attribute_constraint(changeset, module, %{name: field, opts: %{unique: unique_opts}}) do
    case Keyword.fetch(unique_opts, :prevent_collision) do
      {:ok, collision_scope} ->
        changeset
        |> avoid_collision(module, field, collision_scope, unique_opts)
        |> add_unique_constraint(field, unique_opts, collision_scope)

      :error ->
        add_unique_constraint(changeset, field, unique_opts)
    end
  end

  defp avoid_collision(changeset, module, field, true, _unique_opts) do
    Collision.avoid_field_collision(changeset, module, [field], nil)
  end

  defp avoid_collision(changeset, _module, field, filter_fn, unique_opts) when is_function(filter_fn, 1) do
    scope_fields = Keyword.get(unique_opts, :with)

    if nil_scope?(changeset, scope_fields) do
      changeset
    else
      scoped_filter_fn = scope_callback(filter_fn, scope_fields)
      Collision.avoid_field_collision(changeset, [field], scoped_filter_fn)
    end
  end

  defp avoid_collision(changeset, module, field, filter_fields, _unique_opts) do
    Collision.avoid_field_collision(
      changeset,
      module,
      [field],
      {filter_fields, &filter_by_fields/3}
    )
  end

  defp scope_callback(filter_fn, nil), do: filter_fn

  defp scope_callback(filter_fn, fields) do
    fn changeset ->
      filter_fn.(changeset)
      |> filter_by_fields(fields, changeset)
    end
  end

  defp nil_scope?(_changeset, nil), do: false

  defp nil_scope?(changeset, fields) do
    fields
    |> List.wrap()
    |> Enum.any?(&is_nil(Changeset.get_field(changeset, &1)))
  end

  defp add_unique_constraint(changeset, field, unique),
    do: add_unique_constraint(changeset, field, unique, nil)

  defp add_unique_constraint(changeset, field, true, _collision_scope) do
    Changeset.unique_constraint(changeset, field, constraint_name_opts(changeset, field))
  end

  defp add_unique_constraint(changeset, field, unique_opts, collision_scope) do
    field_or_fields =
      case UniqueFields.scope(unique_opts, collision_scope) do
        [] -> field
        scope_fields -> [field | scope_fields]
      end

    message = Keyword.get(unique_opts, :message, "has already been taken")

    opts = [message: message] ++ constraint_name_opts(changeset, field_or_fields)
    Changeset.unique_constraint(changeset, field_or_fields, opts)
  end

  defp constraint_name_opts(%Changeset{data: %{__meta__: %{source: source}, __struct__: schema}}, fields)
       when is_binary(source) do
    field_sources =
      fields
      |> List.wrap()
      |> Enum.map(&(schema.__schema__(:field_source, &1) || &1))

    [name: DatabaseIdentifier.index_name(source, field_sources)]
  end

  defp constraint_name_opts(_changeset, _fields), do: []

  defp filter_by_fields(queryable, fields, changeset) do
    fields_with_values =
      fields
      |> List.wrap()
      |> Enum.map(&{&1, Changeset.get_field(changeset, &1)})

    if Enum.any?(fields_with_values, fn {_field, value} -> is_nil(value) end) do
      from entry in queryable, where: false
    else
      Enum.reduce(fields_with_values, queryable, fn {field, value}, query ->
        from entry in query, where: field(entry, ^field) == ^value
      end)
    end
  end
end
