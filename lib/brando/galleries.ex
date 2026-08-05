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
      {:ids, ids}, query when is_list(ids) ->
        from t in query, where: t.id in ^ids

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

  @gallery_object_fields [:id, :image_id, :video_id, :gallery_id, :sequence, :creator_id, :config]

  @doc """
  Slim a gallery object (struct or map) to the params `put_assoc` needs.

  Existing objects must be passed as plain maps when mixing in new (nil-ID)
  objects on a gallery's `gallery_objects` — `put_assoc` with multiple nil-ID
  structs raises duplicate-PK errors. This field list is canonical: every
  slimming site must use this helper, so per-object `:config` overrides
  survive all mutation paths (add/remove/append/reorder) instead of being
  silently dropped by a hand-rolled `Map.take` that forgot a field.
  """
  def slim_gallery_object(object), do: Map.take(object, @gallery_object_fields)

  @doc """
  Reconcile a gallery's objects as the changeset now holds them with the
  previously-loaded media the editor already had.

  The changeset is the source of truth for *which* objects a gallery holds, so
  the gallery components must re-derive from it on every update — caching the
  list in `assign_new` meant an external mutation (an upload delivered to the
  entry form, a revision restore, a picker on a sibling component) never
  reached the UI.

  But re-deriving alone would blank every thumbnail: the objects only carry a
  preloaded `:image` / `:video` while they come straight from the DB, and
  `slim_gallery_object/1` strips the associations the moment anything writes
  the list back through `put_assoc`. So an object that arrives without its
  media borrows it from the previous list by media id, instead of costing a
  query per render.
  """
  def merge_loaded_media(objects, previous) when is_list(objects) and is_list(previous) do
    Enum.map(objects, fn object ->
      if loaded_media?(object) do
        object
      else
        Enum.find(previous, &same_media?(&1, object)) || object
      end
    end)
  end

  defp loaded_media?(object) do
    (Map.get(object, :image_id) && Brando.Utils.loaded_assoc?(object, :image)) ||
      (Map.get(object, :video_id) && Brando.Utils.loaded_assoc?(object, :video)) || false
  end

  defp same_media?(left, right) do
    matches?(left, right, :image_id) or matches?(left, right, :video_id)
  end

  defp matches?(left, right, key) do
    case {Map.get(left, key), Map.get(right, key)} do
      {nil, _} -> false
      {_, nil} -> false
      {same, same} -> true
      _ -> false
    end
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
    with %Gallery{} = gallery <- Brando.Repo.get(Gallery, gallery_id),
         {:ok, schema, field} <- parse_config_target(gallery.config_target) do
      field_atom = String.to_existing_atom("#{field}_id")

      query =
        from e in schema,
          where: field(e, ^field_atom) == ^gallery_id,
          select: e.id

      case Brando.Repo.all(query) do
        [] -> %{}
        entry_ids -> %{schema => entry_ids}
      end
    else
      _ -> %{}
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
