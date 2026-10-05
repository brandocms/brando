defmodule Brando.Media.Folders do
  @moduledoc """
  Media library folders by name, and the images or videos filed in them.

  These are the folders the admin's image and video pickers browse
  (the `media_folders` table, an asset's `folder_id`). The content assistant uses
  them to take "all the images in the a_form folder" literally: a name
  resolves to exact folders, and a folder's assets are counted and paged in a
  fixed order, so no request silently stops at the first page.

  Queries run in the current site/environment and only count assets the
  actor may read. Deleted assets are left out.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Transfer.{Catalog, Error}
  alias Brando.Media.Folder
  alias Brando.Repo

  @max_matches 20
  @max_page 100

  # Hidden folders live under their own scope, outside every library root
  @hidden_scope "hidden"

  @doc """
  The id of the hidden folder `name`, created on first use.

  A hidden folder holds media the site did not choose itself, such as files
  a form's visitors upload (`hidden_folder` on the field's config). It has
  `library: false`, and the media library, alt-text page and pickers leave
  it out.
  """
  @spec hidden_folder_id(String.t()) :: integer()
  def hidden_folder_id(name) when is_binary(name) and name != "" do
    case Repo.get_by(Folder, scope: @hidden_scope, path: name) do
      %Folder{id: id} ->
        id

      nil ->
        %Folder{}
        |> Folder.changeset(%{scope: @hidden_scope, name: name, path: name, library: false})
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:scope, :path])
        |> case do
          {:ok, %Folder{id: id}} when not is_nil(id) -> id
          # Lost a race with another upload creating the same folder
          _ -> Repo.get_by!(Folder, scope: @hidden_scope, path: name).id
        end
    end
  end

  @doc "Ids of every hidden (non-library) folder."
  @spec hidden_folder_ids() :: [integer()]
  def hidden_folder_ids do
    Repo.all(from(f in Folder, where: not f.library, select: f.id))
  end

  @doc """
  The folder an upload to a field with `cfg` goes in: the one the uploader
  chose, else the field's hidden folder, else none.
  """
  @spec upload_folder_id(integer() | nil, map()) :: integer() | nil
  def upload_folder_id(folder_id, _cfg) when not is_nil(folder_id), do: folder_id

  def upload_folder_id(nil, cfg) do
    case Map.get(cfg, :hidden_folder) do
      name when is_binary(name) and name != "" -> hidden_folder_id(name)
      _ -> nil
    end
  end

  @doc """
  Folders whose name or path is `name`, or whose path ends with it, ignoring
  case; when none is, those whose path contains it. Each has its number of `kind` assets (`items`),
  including subfolders (`items_with_subfolders`).

  Folders that hold no `kind` assets are left out, unless no match holds
  any: then an empty folder is still found, so it can be reported as empty.
  At most #{@max_matches} are returned; `more` tells whether there were more.
  """
  @spec find(:image | :video, String.t(), term()) :: %{folders: [map()], more: boolean()}
  def find(kind, name, actor) do
    needle = name |> to_string() |> String.trim() |> String.trim("/") |> String.downcase()
    if needle == "", do: Error.fail!("Name the folder to look for.")

    folders = Repo.all(from(f in Folder, where: f.library, order_by: [asc: f.scope, asc: f.path, asc: f.id]))
    exact = Enum.filter(folders, &exact?(&1, needle))

    matches =
      if exact != [],
        do: exact,
        else: Enum.filter(folders, &String.contains?(String.downcase(full_path(&1)), needle))

    counts = counts(kind, actor)

    described =
      Enum.map(matches, fn folder ->
        subfolders = descendants(folder, folders)

        %{
          id: folder.id,
          name: folder.name,
          path: full_path(folder),
          subfolders: length(subfolders),
          items: Map.get(counts, folder.id, 0),
          items_with_subfolders: [folder | subfolders] |> Enum.map(&Map.get(counts, &1.id, 0)) |> Enum.sum()
        }
      end)

    described =
      case Enum.filter(described, &(&1.items_with_subfolders > 0)) do
        [] -> described
        filled -> filled
      end

    %{folders: Enum.take(described, @max_matches), more: length(described) > @max_matches}
  end

  @doc """
  One page of the `kind` assets in folder `folder_id`: images by file path,
  videos in upload order, then by id.

  Options: `subfolders: true` includes the assets of every folder below it;
  `offset` and `limit` (at most #{@max_page}) select the page. Returns the
  folder, the `total` number of assets and the page's `ids`.
  """
  @spec assets(:image | :video, integer(), term(), keyword()) :: %{
          folder: map(),
          total: non_neg_integer(),
          ids: [integer()]
        }
  def assets(kind, folder_id, actor, opts \\ []) do
    folder =
      (is_integer(folder_id) && Repo.get(Folder, folder_id)) || Error.fail!("Unknown folder #{inspect(folder_id)}.")

    folder_ids = if opts[:subfolders], do: [folder.id | Enum.map(descendants(folder), & &1.id)], else: [folder.id]
    schema = schema(kind)
    query = kind |> readable(actor) |> then(&from(a in &1, where: a.folder_id in ^folder_ids))
    offset = max(opts[:offset] || 0, 0)
    limit = opts[:limit] |> Kernel.||(@max_page) |> max(1) |> min(@max_page)

    ids =
      from(a in query, order_by: ^order(schema), offset: ^offset, limit: ^limit, select: a.id)
      |> Repo.all()

    %{
      folder: %{id: folder.id, name: folder.name, path: full_path(folder)},
      total: Repo.aggregate(query, :count),
      ids: ids
    }
  end

  @doc "The largest page `assets/4` returns."
  @spec max_page() :: pos_integer()
  def max_page, do: @max_page

  # The folder's name, or its path or the end of its path, whole segments only.
  defp exact?(folder, needle) do
    full = String.downcase(full_path(folder))
    String.downcase(folder.name) == needle or full == needle or String.ends_with?(full, "/" <> needle)
  end

  # A folder's path under its upload root, as the pickers show it. Paths saved
  # before roots were split off may already start with the root.
  defp full_path(%{scope: scope, path: path}) do
    root = clean(scope)
    path = clean(path)

    cond do
      root == "" -> path
      path == "" or path == root -> root
      String.starts_with?(path, root <> "/") -> path
      true -> root <> "/" <> path
    end
  end

  defp clean(path) do
    to_string(path)
    |> String.replace("\\", "/")
    |> String.split("/", trim: true)
    |> Enum.reject(&(&1 in [".", ".."]))
    |> Enum.join("/")
  end

  defp descendants(folder), do: descendants(folder, Repo.all(from(f in Folder, where: f.scope == ^folder.scope)))

  defp descendants(folder, folders) do
    prefix = folder.path <> "/"
    Enum.filter(folders, &(&1.scope == folder.scope and String.starts_with?(&1.path, prefix)))
  end

  # Readable, undeleted `kind` assets per folder id.
  defp counts(kind, actor) do
    from(a in readable(kind, actor),
      where: not is_nil(a.folder_id),
      group_by: a.folder_id,
      select: {a.folder_id, count(a.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp readable(kind, actor) do
    schema = schema(kind)
    Catalog.scoped_query(from(a in schema, where: is_nil(a.deleted_at)), schema, actor, :read)
  end

  defp order(Brando.Images.Image), do: [asc: :path, asc: :id]
  defp order(Brando.Videos.Video), do: [asc: :id]

  defp schema(:image), do: Brando.Images.Image
  defp schema(:video), do: Brando.Videos.Video
end
