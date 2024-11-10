defmodule Brando.Utils.Schema do
  @moduledoc """
  Common schema utility functions
  """

  import Ecto.Query
  alias Brando.SoftDelete
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @field_val_collision_attemps 30

  @doc """
  Updates a field on `schema`.
  `coll` should be [field_name: value]

  ## Example:

      {:ok, schema} = update_field(schema, [field_name: "value"])

  """

  def update_field(schema, coll) do
    schema
    |> Changeset.change(coll)
    |> Brando.repo().update
    |> Brando.Cache.Query.evict()
  end

  @doc """
  Put slug in changeset
  """
  def put_slug(%{changes: %{title: title}} = cs) do
    Changeset.change(cs, %{slug: Brando.Utils.slugify(title)})
  end

  def put_slug(cs), do: cs

  def put_slug(%{changes: _} = cs, field) do
    case Changeset.get_change(cs, field) do
      nil -> cs
      to_slug -> Changeset.change(cs, %{slug: Brando.Utils.slugify(to_slug)})
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
  def avoid_field_collision(%Changeset{valid?: true} = changeset, _module, fields, nil) do
    case Changeset.get_field(changeset, :status) do
      :draft ->
        changeset

      _ ->
        src = changeset.data.__struct__
        do_avoid_field_collision(fields, changeset, src)
    end
  end

  def avoid_field_collision(
        %Changeset{valid?: true} = changeset,
        module,
        fields,
        {filter_field, filter_fn}
      ) do
    case Changeset.get_field(changeset, :status) do
      :draft ->
        changeset

      _ ->
        src = filter_fn.(module, filter_field, changeset)
        do_avoid_field_collision(fields, changeset, src)
    end
  end

  def avoid_field_collision(%Changeset{} = changeset, _, _, _) do
    changeset
  end

  def avoid_field_collision(%Changeset{valid?: true} = changeset, fields, filter_fn)
      when is_list(fields) do
    case Changeset.get_field(changeset, :status) do
      :draft ->
        changeset

      _ ->
        src = filter_fn.(changeset)
        do_avoid_field_collision(fields, changeset, src)
    end
  end

  def avoid_field_collision(%Changeset{} = changeset, _, _), do: changeset

  def avoid_field_collision(%Changeset{valid?: true} = changeset, fields)
      when is_list(fields) do
    case Changeset.get_field(changeset, :status) do
      :draft ->
        changeset

      _ ->
        src = changeset.data.__struct__
        do_avoid_field_collision(fields, changeset, src)
    end
  end

  def avoid_field_collision(changeset, _), do: changeset

  def do_avoid_field_collision(fields, changeset, src) do
    Changeset.prepare_changes(changeset, fn cs ->
      Enum.reduce(fields, cs, fn field, new_cs ->
        field_val = Changeset.get_change(new_cs, field)

        if field_val do
          case get_unique_field_value(new_cs, src, field, field_val, 0) do
            {:ok, unique_value} ->
              Changeset.put_change(new_cs, field, unique_value)

            {:error, :too_many_attempts} ->
              Changeset.add_error(
                new_cs,
                field,
                "Could not find available field value"
              )
          end
        else
          new_cs
        end
      end)
    end)
  end

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
