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

  mutation :update, Gallery do
    fn entry ->
      Brando.Content.Blocks.render_entries_with_gallery_id(entry.id)
      {:ok, entry}
    end
  end

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

  @doc """
  List entries that use the given gallery, grouped by schema.

  Returns a map of `%{schema => [entry_ids]}` by tracing through refs that
  reference the gallery and finding their root blocks and associated entries.
  """
  def list_gallery_usage(gallery_id) do
    block_ids =
      from(r in Brando.Content.Ref,
        where: r.gallery_id == ^gallery_id and not is_nil(r.block_id),
        select: r.block_id
      )
      |> Brando.Repo.all()

    ref_usage =
      block_ids
      |> Brando.Content.Blocks.list_root_block_ids_by_source()
      |> Brando.Content.Blocks.list_entry_ids_for_root_blocks_by_source()

    asset_usage = list_gallery_asset_usage(gallery_id)

    Map.merge(ref_usage, asset_usage, fn _k, v1, v2 -> Enum.uniq(v1 ++ v2) end)
  end

  @doc """
  Find entries that reference a gallery via blueprint assets (direct FK).

  Parses the `config_target` field (format: `"gallery:Elixir.Module:field"`)
  to identify the parent schema and FK field, then queries that table.
  """
  def list_gallery_asset_usage(gallery_id) do
    case Brando.Repo.get(Gallery, gallery_id) do
      nil ->
        %{}

      gallery ->
        case parse_config_target(gallery.config_target) do
          {:ok, schema, field} ->
            field_atom = String.to_existing_atom("#{field}_id")

            query =
              from e in schema,
                where: field(e, ^field_atom) == ^gallery_id,
                select: e.id

            entry_ids = Brando.Repo.all(query)

            if entry_ids == [] do
              %{}
            else
              %{schema => entry_ids}
            end

          :error ->
            %{}
        end
    end
  end

  defp parse_config_target(nil), do: :error
  defp parse_config_target(""), do: :error

  defp parse_config_target(config_target) when is_binary(config_target) do
    case String.split(config_target, ":") do
      ["gallery", schema_binary, field] ->
        schema = Module.concat([schema_binary])
        {:ok, schema, field}

      _ ->
        :error
    end
  end
end
