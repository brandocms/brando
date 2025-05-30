defmodule Brando.Galleries do
  @moduledoc """
  Context for Galleries.
  Handles gallery objects (images and videos).
  """
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.Galleries.Gallery
  alias Brando.Users.User

  @type id :: binary | integer
  @type changeset :: changeset
  @type params :: map
  @type user :: User.t()

  query :single, Gallery, do: fn query -> from(t in query) end

  matches Gallery do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
    end
  end

  query :list, Gallery, do: fn query -> from(t in query) end

  filters Gallery do
    fn
      {:config_target, nil}, query ->
        from(t in query)

      {:config_target, "default"}, query ->
        target_string = "default"
        from t in query, where: t.config_target == ^target_string

      {:config_target, target_string}, query when is_binary(target_string) ->
        from t in query, where: t.config_target == ^target_string

      {:config_target, {type, schema, field}}, query ->
        target_string = "#{type}:#{inspect(schema)}:#{field}"
        from t in query, where: t.config_target == ^target_string
    end
  end

  mutation :update, Gallery
  mutation :delete, Gallery

  @doc """
  Create new gallery
  """
  @spec create_gallery(params, user) :: {:ok, Gallery.t()} | {:error, changeset}
  def create_gallery(params, user) do
    %Gallery{}
    |> Gallery.changeset(params, user)
    |> Brando.Repo.insert()
  end

  @doc """
  Get gallery.
  Raises on failure
  """
  def get_gallery!(id) do
    query =
      from t in Gallery,
        where: t.id == ^id and is_nil(t.deleted_at)

    Brando.Repo.one!(query)
  end

  @doc """
  Delete `ids` from database
  """
  def delete_galleries(ids) when is_list(ids) do
    q = from m in Gallery, where: m.id in ^ids
    Brando.Repo.soft_delete_all(q)
  end
end