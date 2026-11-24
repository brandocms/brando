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
  alias Brando.Blueprint.Attributes
  alias Brando.Blueprint.Collision
  alias Brando.Blueprint.DatabaseIdentifier
  alias Brando.Blueprint.Relations
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

  @doc """
  Adds the unique constraints `module` declares, without collision handling.

  For an insert built from a struct rather than cast params, such as a
  duplicate: a value another row already holds comes back as a changeset
  error instead of raising.
  """
  @spec put_unique_constraints(Changeset.t(), module()) :: Changeset.t()
  def put_unique_constraints(changeset, module) do
    changeset =
      module
      |> Attributes.__attributes__()
      |> Enum.reduce(changeset, fn
        %{name: field, opts: %{unique: true}}, acc ->
          add_unique_constraint(acc, field, true)

        %{name: field, opts: %{unique: unique_opts}}, acc when is_list(unique_opts) ->
          add_unique_constraint(acc, field, unique_opts, Keyword.get(unique_opts, :prevent_collision))

        _attribute, acc ->
          acc
      end)

    run_unique_relation_constraints(changeset, module, Relations.__relations__(module))
  end

  @doc """
  Prepares `changeset` so each of `fields` gets a value no other live row of
  `module` holds, in the scope a save checks (`prevent_collision`, `:with`):
  its value, or the first free of `value-1` … `value-29`, else an error on
  the field. A field `module` doesn't declare unique is checked across the
  table. Unlike a save, a draft is checked too, unless `drafts: false`.

  Adds the unique constraints `module` declares, so a value taken all the
  same is a changeset error rather than a raise. For a restore from the
  trash (`Brando.SoftDelete.Repo.restore_changeset/2`).
  """
  @spec avoid_collisions(Changeset.t(), module(), [atom()], keyword()) :: Changeset.t()
  def avoid_collisions(changeset, module, fields, opts \\ []) do
    changeset =
      if Keyword.get(opts, :drafts, true) or Changeset.get_field(changeset, :status) != :draft,
        do: Enum.reduce(fields, changeset, &avoid_field_collision(&2, module, &1)),
        else: changeset

    put_unique_constraints(changeset, module)
  end

  defp avoid_field_collision(changeset, module, field) do
    case collision_source(changeset, module, unique_opts(module, field)) do
      nil -> changeset
      source -> Collision.do_avoid_field_collision([field], changeset, source)
    end
  end

  defp unique_opts(module, field) do
    module
    |> Attributes.__attributes__()
    |> Enum.find_value(fn
      %{name: ^field, opts: opts} -> Map.get(opts, :unique)
      _attribute -> nil
    end)
  end

  # The rows a value collides with: none (`nil`) when a scope field is NULL,
  # which the index treats as distinct
  defp collision_source(changeset, module, unique_opts) when is_list(unique_opts) do
    case Keyword.get(unique_opts, :prevent_collision) do
      filter_fn when is_function(filter_fn, 1) ->
        scope_fields = Keyword.get(unique_opts, :with)
        unless nil_scope?(changeset, scope_fields), do: scope_callback(filter_fn, scope_fields).(changeset)

      collision_scope ->
        scope_fields = UniqueFields.scope(unique_opts, collision_scope)
        unless nil_scope?(changeset, scope_fields), do: filter_by_fields(module, scope_fields, changeset)
    end
  end

  defp collision_source(_changeset, module, _unique), do: module

  @doc """
  Returns `value`, or the first of `value-2`, `value-3`, … that no other row
  of `module` holds for the unique attribute `field`. A field that isn't
  unique gets `value` back.

  The attribute's scope fields (`prevent_collision: :language`, `:with`) take
  their values from `entry`, so a copy into another language keeps its value
  when that language has it free. `entry` itself is never counted as taken.
  Soft-deleted rows count: the unique index covers them too.
  """
  @spec free_value(module(), atom(), String.t(), struct()) :: String.t()
  def free_value(module, field, value, entry) when is_binary(value) do
    scope =
      module
      |> Attributes.__attributes__()
      |> Enum.find_value(:not_unique, fn
        %{name: ^field, opts: %{unique: true}} ->
          []

        %{name: ^field, opts: %{unique: unique_opts}} when is_list(unique_opts) ->
          unique_opts
          |> UniqueFields.scope(Keyword.get(unique_opts, :prevent_collision))
          |> Enum.map(&{&1, Map.get(entry, &1)})

        _ ->
          nil
      end)

    # The index treats NULLs as distinct: a row with a NULL scope collides with nothing.
    if scope == :not_unique or Enum.any?(scope, fn {_scope_field, scope_value} -> is_nil(scope_value) end) do
      value
    else
      query =
        Enum.reduce(scope, from(q in module, select: true, limit: 1), fn {scope_field, scope_value}, query ->
          from q in query, where: field(q, ^scope_field) == ^scope_value
        end)

      query =
        case Map.get(entry, :id) do
          nil -> query
          id -> from q in query, where: q.id != ^id
        end

      first_free(query, field, value, 1)
    end
  end

  defp first_free(query, field, base, n) do
    candidate = if n == 1, do: base, else: "#{base}-#{n}"

    if Brando.Repo.one(from(q in query, where: field(q, ^field) == ^candidate)),
      do: first_free(query, field, base, n + 1),
      else: candidate
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
