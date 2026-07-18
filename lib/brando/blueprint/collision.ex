defmodule Brando.Blueprint.Collision do
  @moduledoc """
  Resolves unique-field collisions while preparing Blueprint changesets.

  Collision checks only need the target schema and repository. They live here
  so Blueprint validation does not depend on the broader schema and
  soft-deletion maintenance utilities.
  """

  import Ecto.Query

  alias Brando.Repo
  alias Ecto.Changeset

  @max_attempts 30

  @doc """
  Prepares a valid, non-draft changeset to avoid collisions in `fields`.

  The four-argument form optionally receives a query-building filter callback
  and its field configuration.
  """
  def avoid_field_collision(%Changeset{valid?: true} = changeset, _module, fields, nil) do
    if draft?(changeset) do
      changeset
    else
      do_avoid_field_collision(fields, changeset, changeset.data.__struct__)
    end
  end

  def avoid_field_collision(%Changeset{valid?: true} = changeset, module, fields, {filter_field, filter_fn}) do
    if draft?(changeset) do
      changeset
    else
      source = filter_fn.(module, filter_field, changeset)

      do_avoid_field_collision(
        fields,
        changeset,
        source,
        scope_changed?(changeset, filter_field)
      )
    end
  end

  def avoid_field_collision(%Changeset{} = changeset, _module, _fields, _filter), do: changeset

  @doc """
  Prepares a valid, non-draft changeset using a custom query callback.
  """
  def avoid_field_collision(%Changeset{valid?: true} = changeset, fields, filter_fn) when is_list(fields) do
    if draft?(changeset) do
      changeset
    else
      do_avoid_field_collision(fields, changeset, filter_fn.(changeset), true)
    end
  end

  def avoid_field_collision(%Changeset{} = changeset, _fields, _filter_fn), do: changeset

  @doc """
  Prepares a valid, non-draft changeset using its schema as the query source.
  """
  def avoid_field_collision(%Changeset{valid?: true} = changeset, fields) when is_list(fields) do
    if draft?(changeset) do
      changeset
    else
      do_avoid_field_collision(fields, changeset, changeset.data.__struct__)
    end
  end

  def avoid_field_collision(changeset, _fields), do: changeset

  @doc false
  def do_avoid_field_collision(fields, changeset, source) do
    do_avoid_field_collision(fields, changeset, source, false)
  end

  defp do_avoid_field_collision(fields, changeset, source, check_unchanged?) do
    Changeset.prepare_changes(changeset, fn prepared_changeset ->
      Enum.reduce(fields, prepared_changeset, fn field, current_changeset ->
        ensure_unique_field(current_changeset, source, field, check_unchanged?)
      end)
    end)
  end

  defp draft?(changeset), do: Changeset.get_field(changeset, :status) == :draft

  defp ensure_unique_field(changeset, source, field, check_unchanged?) do
    field_change = Changeset.get_change(changeset, field)

    field_value =
      if is_nil(field_change) and check_unchanged?, do: Changeset.get_field(changeset, field), else: field_change

    case field_value do
      nil ->
        changeset

      field_value ->
        case get_unique_field_value(changeset, source, field, field_value, 0) do
          {:ok, unique_value} ->
            Changeset.put_change(changeset, field, unique_value)

          {:error, :too_many_attempts} ->
            Changeset.add_error(changeset, field, "Could not find available field value")
        end
    end
  end

  defp get_unique_field_value(changeset, source, field, field_value, attempts) when attempts < @max_attempts do
    candidate = construct_field_value(field_value, attempts)
    query = from entry in source, where: field(entry, ^field) == ^candidate
    query = exclude_current_entry(query, changeset)

    query =
      if soft_delete_schema?(changeset.data.__struct__) do
        from entry in query, where: is_nil(entry.deleted_at)
      else
        query
      end

    case Repo.one(query) do
      nil -> {:ok, candidate}
      _entry -> get_unique_field_value(changeset, source, field, field_value, attempts + 1)
    end
  end

  defp get_unique_field_value(_changeset, _source, _field, _field_value, _attempts),
    do: {:error, :too_many_attempts}

  defp soft_delete_schema?(schema) do
    function_exported?(schema, :has_trait, 1) and schema.has_trait(Brando.Trait.SoftDelete)
  end

  defp exclude_current_entry(query, %Changeset{data: data}) do
    primary_key = Ecto.primary_key(data)

    if primary_key != [] and Enum.all?(primary_key, fn {_field, value} -> not is_nil(value) end) do
      current_entry =
        Enum.reduce(primary_key, dynamic(true), fn {primary_key_field, value}, current_entry ->
          dynamic([entry], ^current_entry and field(entry, ^primary_key_field) == ^value)
        end)

      not_current_entry = dynamic([_entry], not (^current_entry))
      where(query, ^not_current_entry)
    else
      query
    end
  end

  defp scope_changed?(changeset, fields) do
    fields
    |> List.wrap()
    |> Enum.any?(&Changeset.changed?(changeset, &1))
  end

  defp construct_field_value(field_value, 0), do: field_value
  defp construct_field_value(field_value, attempts), do: "#{field_value}-#{attempts}"
end
