defmodule BrandoAdmin.Media.Sweep do
  @moduledoc """
  Sorts the images, videos or files lying loose in one library folder into
  folders named after where they are used: `cases/sommerro`, `pages/about`.
  A library fills one flat folder over the years, since block media all
  uploads to the same place; where each asset belongs is already known from
  the entries that show it.

  `plan/2` proposes, `apply/2` moves, `undo/1` moves back. The asset type is
  the first argument of `plan/2` (`:image`, `:video` or `:file`) and travels
  in the plan and the result:

    * Only assets directly in the folder are sorted. Whatever an editor has
      already put in a subfolder stays there, so a second run only takes what
      has arrived since.
    * An entry and its translations share one folder, named after the entry
      in the default language.
    * An asset several entries use goes to one of them: by the site's order
      of types when it has set one, then to the entry that uses the most of
      the folder's assets (a case before the category page showing its cover).
    * Assets no entry uses stay where they are. The library's "Not in use"
      filter lists them.

  A move changes the asset's folder only. Files stay where they were
  uploaded, so no URL changes.

  A site ranks its types for shared assets in config, first wins. Videos and
  files take their own list when they have one, else the images' list:

      config :brando, Brando.Images,
        sweep_priority: [MyApp.Projects.Project, MyApp.Articles.Article, Brando.Pages.Page]

      config :brando, Brando.Videos, sweep_priority: [MyApp.Projects.Project]
      config :brando, Brando.Files, sweep_priority: [MyApp.Articles.Article]

  Every query runs through `Brando.Repo`, so in the current site and
  environment only.
  """

  import Ecto.Query

  alias Brando.Content.Usage
  alias Brando.Media.Folder
  alias Brando.Repo
  alias BrandoAdmin.Images.FolderBrowser

  @type asset_type :: :image | :video | :file
  @type group :: %{
          key: String.t(),
          path: String.t(),
          type: String.t(),
          label: String.t(),
          url: String.t() | nil,
          ids: [integer()],
          shared: non_neg_integer()
        }
  @type plan :: %{
          asset_type: asset_type(),
          folder_id: integer(),
          folder: String.t(),
          total: non_neg_integer(),
          unused: non_neg_integer(),
          groups: [group()]
        }

  @types [:image, :video, :file]
  @schemas %{image: Brando.Images.Image, video: Brando.Videos.Video, file: Brando.Files.File}
  @contexts %{image: Brando.Images, video: Brando.Videos, file: Brando.Files}

  @doc "The asset types a library folder can be sorted for."
  @spec types() :: [asset_type()]
  def types, do: @types

  @doc "The schema of `asset_type`'s assets."
  @spec schema(asset_type()) :: module()
  def schema(asset_type) when asset_type in @types, do: Map.fetch!(@schemas, asset_type)

  @doc """
  The top folder of `asset_type`'s library, as its list shows it: `images`,
  or the top of the default config's upload path for videos and files.
  """
  @spec library_root(asset_type()) :: String.t()
  def library_root(:image), do: FolderBrowser.scope_for(nil)

  def library_root(asset_type) when asset_type in [:video, :file] do
    {:ok, cfg} = Map.fetch!(@contexts, asset_type).get_config_for(%{config_target: "default"})
    FolderBrowser.scope_for(cfg && cfg.upload_path)
  end

  @doc """
  What sorting folder `folder_id` would do for `asset_type`: a group for each
  entry with assets in it, largest first, and how many assets no entry uses.
  `{:error, :not_found}` without the folder, or for a folder outside the
  type's library (another type's, or a hidden one).
  """
  @spec plan(asset_type(), integer() | nil) :: {:ok, plan()} | {:error, :not_found}
  def plan(asset_type, folder_id) when asset_type in @types do
    with %Folder{library: true} = folder <- folder_id && Repo.get(Folder, folder_id),
         root = FolderBrowser.absolute_folder(folder.path, folder.scope),
         true <- under?(root, library_root(asset_type)) do
      {:ok, build_plan(asset_type, folder, root)}
    else
      _ -> {:error, :not_found}
    end
  end

  defp build_plan(asset_type, folder, root) do
    schema = schema(asset_type)

    ids =
      Repo.all(from a in schema, where: a.folder_id == ^folder.id and is_nil(a.deleted_at), order_by: a.id, select: a.id)

    owners = Usage.owners(asset_type, ids)
    families = families(owners |> Map.values() |> List.flatten() |> Enum.uniq())
    owned = Map.new(owners, fn {id, entries} -> {id, entries |> Enum.map(&families[&1]) |> Enum.uniq()} end)

    # How many of the folder's assets each entry uses decides who gets a
    # shared one.
    weight = owned |> Map.values() |> List.flatten() |> Enum.frequencies()
    priority = priority(asset_type)

    by_owner =
      Enum.group_by(
        Enum.filter(ids, &Map.has_key?(owned, &1)),
        fn id ->
          Enum.min_by(owned[id], &{rank(priority, elem(&1, 0)), -weight[&1], inspect(elem(&1, 0)), elem(&1, 1)})
        end
      )

    labels = Usage.labels(Map.keys(by_owner))
    names = names(by_owner, labels)

    groups =
      by_owner
      |> Enum.map(fn {entry, asset_ids} ->
        %{
          key: names[entry],
          path: root <> "/" <> names[entry],
          type: labels[entry].type,
          label: labels[entry].label,
          url: labels[entry].url,
          ids: asset_ids,
          shared: Enum.count(asset_ids, &(length(owned[&1]) > 1))
        }
      end)
      |> Enum.sort_by(&{-length(&1.ids), &1.key})

    %{
      asset_type: asset_type,
      folder_id: folder.id,
      folder: root,
      total: length(ids),
      unused: length(ids) - map_size(owned),
      groups: groups
    }
  end

  @doc """
  Up to `per_group` assets of each of `plan`'s groups, by id, to show in the
  preview: images as they are, videos with their thumbnail.
  """
  @spec samples(plan(), pos_integer()) :: %{optional(integer()) => struct()}
  def samples(%{asset_type: asset_type, groups: groups}, per_group \\ 4) do
    ids = Enum.flat_map(groups, &Enum.take(&1.ids, per_group))
    query = from(a in schema(asset_type), where: a.id in ^ids)
    query = if asset_type == :video, do: preload(query, [:thumbnail]), else: query

    Map.new(Repo.all(query), &{&1.id, &1})
  end

  @doc """
  Moves the assets of `plan`'s groups into their folders, creating the
  folders. `only:` takes the keys of the groups to move; the rest stay.
  `names:` renames folders, as `%{key => "cases/other-name"}` under the swept
  folder. An asset that has left the folder since the plan is left alone.

  Returns what `undo/1` needs: `%{asset_type: type, moved: n, folders: n,
  from: folder_id, ids: [id], created: [folder_id]}`.
  """
  @spec apply(plan(), keyword()) :: {:ok, map()}
  def apply(plan, opts \\ []) do
    names = Keyword.get(opts, :names, %{})
    schema = schema(plan.asset_type)

    groups =
      case Keyword.get(opts, :only) do
        nil -> plan.groups
        keys -> Enum.filter(plan.groups, &(&1.key in keys))
      end

    groups =
      Enum.map(groups, fn group ->
        case names |> Map.get(group.key) |> FolderBrowser.normalize_folder() do
          nil -> group
          name -> %{group | path: plan.folder <> "/" <> name}
        end
      end)

    # The folders this run may create: each target and the folders above it,
    # under the swept one. Known before the move, so `created` is only ours.
    paths = groups |> Enum.map(& &1.path) |> Enum.uniq()
    candidates = candidate_folders(plan.folder, paths)
    before = folder_ids(candidates)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    {:ok, moved} =
      Repo.transaction(fn ->
        Enum.flat_map(groups, fn group ->
          target = FolderBrowser.folder_id_for(group.path)

          {_count, ids} =
            Repo.update_all(
              from(a in schema, where: a.id in ^group.ids and a.folder_id == ^plan.folder_id, select: a.id),
              set: [folder_id: target, updated_at: now]
            )

          ids
        end)
      end)

    {:ok,
     %{
       asset_type: plan.asset_type,
       moved: length(moved),
       folders: length(paths),
       from: plan.folder_id,
       ids: moved,
       created: folder_ids(candidates) -- before
     }}
  end

  @doc """
  Puts back what `apply/2` moved, and removes the folders it created that are
  empty again. An asset an editor has moved on since stays where it was put.
  """
  @spec undo(map()) :: {:ok, non_neg_integer()}
  def undo(%{asset_type: asset_type, from: from, ids: ids, created: created}) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Repo.transaction(fn ->
      {count, _} =
        Repo.update_all(
          from(a in schema(asset_type), where: a.id in ^ids and a.folder_id in ^created),
          set: [folder_id: from, updated_at: now]
        )

      remove_empty(created)
      count
    end)
  end

  # {scope, path} of each folder from the swept one down to every target,
  # stored as `FolderBrowser.folder_id_for/1` stores them.
  defp candidate_folders(root, paths) do
    [scope | _] = String.split(root, "/")

    paths
    |> Enum.flat_map(fn path ->
      path
      |> String.replace_prefix(root <> "/", "")
      |> String.split("/", trim: true)
      |> Enum.scan(root, &(&2 <> "/" <> &1))
    end)
    |> Enum.uniq()
    |> Enum.map(&{scope, FolderBrowser.relative_folder(&1, scope)})
  end

  defp folder_ids([]), do: []

  defp folder_ids([{scope, _} | _] = candidates) do
    paths = Enum.map(candidates, &elem(&1, 1))
    Repo.all(from f in Folder, where: f.scope == ^scope and f.path in ^paths, select: f.id)
  end

  # Children before parents: a type folder empties when its entry folders go.
  # A folder still holding any asset, of any type and deleted or not, stays.
  defp remove_empty(folder_ids) do
    folders = Repo.all(from f in Folder, where: f.id in ^folder_ids)

    folders
    |> Enum.sort_by(&(-String.length(&1.path)))
    |> Enum.each(fn folder ->
      assets =
        @types |> Enum.map(&Repo.aggregate(from(a in schema(&1), where: a.folder_id == ^folder.id), :count)) |> Enum.sum()

      children = Repo.aggregate(from(f in Folder, where: f.parent_id == ^folder.id), :count)
      if assets + children == 0, do: Repo.delete(folder)
    end)
  end

  defp under?(folder, root), do: folder == root or String.starts_with?(folder, root <> "/")

  # The site's `sweep_priority` for the type; videos and files fall back to
  # the images' list.
  defp priority(asset_type) do
    own = Keyword.get(Application.get_env(:brando, Map.fetch!(@contexts, asset_type), []), :sweep_priority)
    own || Keyword.get(Application.get_env(:brando, Brando.Images, []), :sweep_priority, [])
  end

  # A type's place in the priority; unlisted types come after.
  defp rank(priority, schema), do: Enum.find_index(priority, &(&1 == schema)) || length(priority)

  # Each entry's family head: the default-language entry among it and its
  # translations, else the one with the lowest id. Entries of a schema without
  # translations are their own.
  defp families(entries) do
    default = to_string(Brando.config(:default_language))

    entries
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {schema, ids} ->
      heads = if alternates?(schema), do: heads(schema, ids, default), else: %{}
      Enum.map(ids, &{{schema, &1}, {schema, Map.get(heads, &1, &1)}})
    end)
    |> Map.new()
  end

  defp alternates?(schema) do
    function_exported?(schema, :has_alternates?, 0) and schema.has_alternates?()
  end

  defp heads(schema, ids, default) do
    alternate = Module.concat([schema, Alternate])

    links =
      Repo.all(
        from a in alternate,
          where: a.entry_id in ^ids or a.linked_entry_id in ^ids,
          select: {a.entry_id, a.linked_entry_id}
      )

    family =
      Enum.reduce(links, Map.new(ids, &{&1, MapSet.new([&1])}), fn {a, b}, acc ->
        joined = MapSet.union(Map.get(acc, a, MapSet.new([a])), Map.get(acc, b, MapSet.new([b])))
        Enum.reduce(joined, acc, &Map.put(&2, &1, joined))
      end)

    members = family |> Map.values() |> Enum.flat_map(&MapSet.to_list/1) |> Enum.uniq()

    languages =
      Map.new(Repo.all(from e in schema, where: e.id in ^members, select: {e.id, e.language}))

    Map.new(ids, fn id ->
      head = family[id] |> Enum.sort() |> Enum.min_by(&if(to_string(languages[&1]) == default, do: 0, else: 1))
      {id, head}
    end)
  end

  # "cases/sommerro": the schema's plural and the entry's title, slugified.
  # Two entries of a type with the same title get their ids added.
  defp names(by_owner, labels) do
    named =
      Map.new(by_owner, fn {{schema, _id} = entry, _ids} ->
        {entry, slug(schema.__naming__().plural) <> "/" <> short(slug(labels[entry].label))}
      end)

    taken = named |> Map.values() |> Enum.frequencies()

    Map.new(named, fn {{_schema, id} = entry, name} ->
      {entry, if(taken[name] > 1, do: "#{name}-#{id}", else: name)}
    end)
  end

  # A title can run to a sentence; a folder name shouldn't. Cut at a word.
  @name_length 32
  defp short(slug) do
    if String.length(slug) <= @name_length do
      slug
    else
      slug |> String.slice(0, @name_length) |> String.replace(~r/-[^-]*$/, "")
    end
  end

  defp slug(text) do
    case Brando.Utils.slugify(to_string(text)) do
      slug when is_binary(slug) and slug != "" -> slug
      _ -> "untitled"
    end
  end
end
