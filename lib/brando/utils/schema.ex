defmodule Brando.Utils.Schema do
  @moduledoc """
  Common schema utility functions
  """

  alias Brando.Blueprint.Collision
  alias Ecto.Changeset
  alias Slug

  @type changeset :: Changeset.t()

  @doc """
  Updates a field on `schema`.
  `coll` should be [field_name: value]

  ## Example:

      {:ok, schema} = update_field(schema, [field_name: "value"])

  """

  def update_field(schema, coll) do
    schema
    |> Changeset.change(coll)
    |> Brando.Repo.update()
    |> Brando.Cache.Query.evict()
  end

  @doc """
  Put slug in changeset
  """
  def put_slug(%{changes: %{title: title}} = cs) do
    Changeset.change(cs, %{slug: Slug.slugify(title)})
  end

  def put_slug(cs), do: cs

  def put_slug(%{changes: _} = cs, field) do
    case Changeset.get_change(cs, field) do
      nil -> cs
      to_slug -> Changeset.change(cs, %{slug: Slug.slugify(to_slug)})
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
  defdelegate avoid_field_collision(changeset, module, fields, filter), to: Collision
  defdelegate avoid_field_collision(changeset, fields, filter_fn), to: Collision
  defdelegate avoid_field_collision(changeset, fields), to: Collision
  defdelegate do_avoid_field_collision(fields, changeset, source), to: Collision
end
