defmodule Brando.Utils.Schema do
  @moduledoc """
  Common schema utility functions
  """

  import Ecto.Query
  alias Brando.SoftDelete

  @type changeset :: Ecto.Changeset.t()

  @field_val_collision_attemps 30

  @doc """
  Updates a field on `schema`.
  `coll` should be [field_name: value]

  ## Example:

      {:ok, schema} = update_field(schema, [field_name: "value"])

  """

  def update_field(schema, coll) do
    changeset = Ecto.Changeset.change(schema, coll)
    {:ok, Brando.repo().update!(changeset)}
  end

  @doc """
  Puts `id` from `user` in the `params` map.
  """
  @spec put_creator(changeset | map, map | :system) :: changeset
  def put_creator(%Ecto.Changeset{} = cs, :system), do: cs

  def put_creator(%Ecto.Changeset{} = cs, user) when is_map(user),
    do: Ecto.Changeset.put_change(cs, :creator_id, user.id)

  def put_creator(%Ecto.Changeset{} = cs, user_id),
    do: Ecto.Changeset.put_change(cs, :creator_id, user_id)

  def put_creator(params, :system), do: params

  @doc """
  Put slug in changeset
  """
  def put_slug(%{changes: %{title: title}} = cs) do
    Ecto.Changeset.change(cs, %{slug: Brando.Utils.slugify(title)})
  end

  def put_slug(cs), do: cs

  def put_slug(%{changes: _} = cs, field) do
    case Ecto.Changeset.get_change(cs, field) do
      nil -> cs
      to_slug -> Ecto.Changeset.change(cs, %{slug: Brando.Utils.slugify(to_slug)})
    end
  end

  defmacro avoid_slug_collision(_) do
    raise """
    avoid_slug_collision(changeset, filter_fn \\ nil) is removed.

    Use avoid_field_collision(changeset, [:slug], filter_fn \\ nil) instead.
    """
  end

  @doc """
  Precheck field in `cs` to make sure we avoid collisions
  """
  def avoid_field_collision(changeset, fields \\ [:slug], filter_fn \\ nil)

  def avoid_field_collision(%{valid?: true} = changeset, fields, filter_fn) do
    src = (filter_fn && filter_fn.(changeset)) || changeset.data.__struct__

    Enum.reduce(fields, changeset, fn field, new_changeset ->
      field_val = Ecto.Changeset.get_change(new_changeset, field)

      if field_val do
        case get_unique_field_value(new_changeset, src, field, field_val, 0) do
          {:ok, unique_value} ->
            Ecto.Changeset.put_change(new_changeset, field, unique_value)

          {:error, :too_many_attempts} ->
            Ecto.Changeset.add_error(
              new_changeset,
              field,
              "Klarte ikke finne en ledig verdi for feltet"
            )
        end
      else
        new_changeset
      end
    end)
  end

  def avoid_field_collision(changeset, _, _), do: changeset

  defp get_unique_field_value(cs, src, field, field_val, attempts)
       when attempts < @field_val_collision_attemps do
    field_val_to_test = construct_field_val(field_val, attempts)
    test_query = from m in src, where: field(m, ^field) == ^field_val_to_test

    # if schema is soft deleted, only check non deleted entries.
    test_query =
      if SoftDelete.Query.soft_delete_schema?(cs.data.__struct__) do
        from m in test_query, where: is_nil(m.deleted_at)
      else
        test_query
      end

    case Brando.repo().one(test_query) do
      nil ->
        {:ok, field_val_to_test}

      _ ->
        get_unique_field_value(cs, src, field, field_val, attempts + 1)
    end
  end

  defp get_unique_field_value(_, _, _, _, _), do: {:error, :too_many_attempts}

  defp construct_field_val(field_val, 0), do: field_val
  defp construct_field_val(field_val, attempts), do: "#{field_val}-#{to_string(attempts)}"
end
