defmodule Brando.Blueprint.Unique do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Brando.Utils

  def run_unique_attribute_constraints(changeset, module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :unique, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{unique: true}} = f, new_changeset ->
        unique_constraint(new_changeset, f.name)

      %{opts: %{unique: [prevent_collision: true]}} = f, new_changeset ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(module, [f.name], nil)
        |> unique_constraint(f.name)

      %{opts: %{unique: [prevent_collision: filter_fn]}} = f, new_changeset
      when is_function(filter_fn) ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(module, [f.name], filter_fn)
        |> unique_constraint(f.name)

      %{opts: %{unique: [prevent_collision: filter_fields]}} = f, new_changeset
      when is_list(filter_fields) ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(
          module,
          [f.name],
          {filter_fields, &filter_by_fields/3}
        )
        |> unique_constraint([f.name] ++ filter_fields)

      %{opts: %{unique: [prevent_collision: filter_field]}} = f, new_changeset ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(
          module,
          [f.name],
          {filter_field, &filter_by_field/3}
        )
        |> unique_constraint([f.name, filter_field])

      %{opts: %{unique: unique_opts}} = f, new_changeset ->
        message = Keyword.get(unique_opts, :message, "has already been taken")

        case Keyword.get(unique_opts, :with) do
          nil ->
            nil

          with_fields when is_list(with_fields) ->
            unique_constraint(new_changeset, [f.name] ++ with_fields, message: message)

          with_field ->
            unique_constraint(new_changeset, [f.name, with_field], message: message)
        end
    end)
  end

  def run_unique_relation_constraints(changeset, _, relations) do
    relations
    |> Enum.filter(&Map.get(&1.opts, :unique, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{unique: true}} = f, new_changeset ->
        unique_constraint(new_changeset, f.name)

      %{opts: %{unique: unique_opts}} = f, new_changeset ->
        message = Keyword.get(unique_opts, :message, "has already been taken")

        case Keyword.get(unique_opts, :with) do
          nil ->
            nil

          with_fields when is_list(with_fields) ->
            field = String.to_existing_atom("#{to_string(f.name)}_id")
            unique_constraint(new_changeset, [field] ++ with_fields, message: message)

          with_field ->
            field = String.to_existing_atom("#{to_string(f.name)}_id")
            unique_constraint(new_changeset, [field, with_field], message: message)
        end
    end)
  end

  @doc """
  Adds the unique constraints `module` declares, without collision handling.

  For an insert built from a struct rather than cast params, such as a
  duplicate: a value another row already holds comes back as a changeset
  error instead of raising.
  """
  def put_unique_constraints(changeset, module) do
    changeset =
      Brando.Blueprint.Attributes.__attributes__(module)
      |> Enum.filter(&Map.get(&1.opts, :unique, false))
      |> Enum.reduce(changeset, fn %{name: field, opts: %{unique: unique}}, new_changeset ->
        message = (is_list(unique) && Keyword.get(unique, :message)) || "has already been taken"

        case unique_scope(unique) do
          [] -> unique_constraint(new_changeset, field, message: message)
          scope -> unique_constraint(new_changeset, [field | scope], message: message)
        end
      end)

    run_unique_relation_constraints(changeset, module, Brando.Blueprint.Relations.__relations__(module))
  end

  @doc """
  Returns `value`, or the first of `value-2`, `value-3`, … that no other row
  of `module` holds for the unique attribute `field`. A field that isn't
  unique gets `value` back.

  The attribute's scope fields (`prevent_collision: :language`, `:with`) take
  their values from `entry`, so a copy into another language keeps its value
  when that language has it free. `entry` itself is never counted as taken.
  """
  def free_value(module, field, value, entry) when is_binary(value) do
    scope =
      Enum.find_value(Brando.Blueprint.Attributes.__attributes__(module), :not_unique, fn
        %{name: ^field, opts: %{unique: unique}} when unique not in [nil, false] ->
          Enum.map(unique_scope(unique), &{&1, Map.get(entry, &1)})

        _ ->
          nil
      end)

    # The index treats NULLs as distinct: a row with a NULL scope collides with nothing.
    if scope == :not_unique or Enum.any?(scope, fn {_, scope_value} -> is_nil(scope_value) end) do
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

  # The fields a unique attribute's index is scoped by: `:with`, otherwise the
  # `prevent_collision` field(s).
  defp unique_scope(unique) when is_list(unique) do
    case Keyword.fetch(unique, :with) do
      {:ok, fields} ->
        List.wrap(fields)

      :error ->
        case Keyword.get(unique, :prevent_collision) do
          fields when is_list(fields) -> fields
          field when is_atom(field) and field not in [nil, true, false] -> [field]
          _ -> []
        end
    end
  end

  defp unique_scope(_unique), do: []

  defp filter_by_field(module, field, changeset) do
    from(m in module,
      where: field(m, ^field) == ^get_field(changeset, field)
    )
  end

  defp filter_by_fields(module, fields, changeset) do
    Enum.reduce(fields, from(m in module), fn field, query ->
      from q in query, where: field(q, ^field) == ^get_field(changeset, field)
    end)
  end
end
