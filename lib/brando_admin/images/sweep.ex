defmodule BrandoAdmin.Images.Sweep do
  @moduledoc """
  Sorts the images lying loose in one folder into folders named after where
  they are used: `cases/sommerro`, `pages/about`. A library fills one flat
  folder over the years, since block images all upload to the same place;
  where each image belongs is already known from the entries that show it.

  `plan/1` proposes, `apply/2` moves, `undo/1` moves back:

    * Only images directly in the folder are sorted. Whatever an editor has
      already put in a subfolder stays there, so a second run only takes what
      has arrived since.
    * An entry and its translations share one folder, named after the entry
      in the default language.
    * An image several entries use goes to one of them: by the site's order
      of types when it has set one, then to the entry that uses the most of
      the folder's images (a case before the category page showing its cover).
    * Images no entry uses stay where they are. The library's "Not in use"
      filter lists them.

  A move changes the image's folder only. Files stay where they were
  uploaded, so no URL changes.

  A site ranks its types for shared images in config, first wins:

      config :brando, Brando.Images,
        sweep_priority: [MyApp.Projects.Project, MyApp.Articles.Article, Brando.Pages.Page]
  """

  import Ecto.Query

  alias Brando.Content.Usage
  alias Brando.Images.Image
  alias Brando.Media.Folder
  alias Brando.Repo
  alias BrandoAdmin.Images.FolderBrowser

  @type group :: %{
          key: String.t(),
          path: String.t(),
          type: String.t(),
          label: String.t(),
          url: String.t() | nil,
          image_ids: [integer()],
          shared: non_neg_integer()
        }
  @type plan :: %{
          folder_id: integer(),
          folder: String.t(),
          total: non_neg_integer(),
          unused: non_neg_integer(),
          groups: [group()]
        }

  @doc """
  What sorting folder `folder_id` would do: a group for each entry with
  images in it, largest first, and how many images no entry uses.
  `{:error, :not_found}` without the folder.
  """
  @spec plan(integer()) :: {:ok, plan()} | {:error, :not_found}
  def plan(folder_id) do
    case Repo.get(Folder, folder_id) do
      nil ->
        {:error, :not_found}

      folder ->
        root = FolderBrowser.absolute_folder(folder.path, folder.scope)

        ids =
          Repo.all(
            from i in Image, where: i.folder_id == ^folder.id and is_nil(i.deleted_at), order_by: i.id, select: i.id
          )

        owners = Usage.owners(:image, ids)
        families = families(owners |> Map.values() |> List.flatten() |> Enum.uniq())
        owned = Map.new(owners, fn {id, entries} -> {id, entries |> Enum.map(&families[&1]) |> Enum.uniq()} end)

        # How many of the folder's images each entry uses decides who gets a
        # shared one.
        weight = owned |> Map.values() |> List.flatten() |> Enum.frequencies()

        by_owner =
          Enum.group_by(
            Enum.filter(ids, &Map.has_key?(owned, &1)),
            fn id -> Enum.min_by(owned[id], &{rank(elem(&1, 0)), -weight[&1], inspect(elem(&1, 0)), elem(&1, 1)}) end
          )

        labels = Usage.labels(Map.keys(by_owner))
        names = names(by_owner, labels)

        groups =
          by_owner
          |> Enum.map(fn {entry, image_ids} ->
            %{
              key: names[entry],
              path: root <> "/" <> names[entry],
              type: labels[entry].type,
              label: labels[entry].label,
              url: labels[entry].url,
              image_ids: image_ids,
              shared: Enum.count(image_ids, &(length(owned[&1]) > 1))
            }
          end)
          |> Enum.sort_by(&{-length(&1.image_ids), &1.key})

        {:ok,
         %{
           folder_id: folder.id,
           folder: root,
           total: length(ids),
           unused: length(ids) - map_size(owned),
           groups: groups
         }}
    end
  end

  @doc """
  Moves the images of `plan`'s groups into their folders, creating the
  folders. `only:` takes the keys of the groups to move; the rest stay.
  `names:` renames folders, as `%{key => "cases/other-name"}` under the swept
  folder. An image that has left the folder since the plan is left alone.

  Returns what `undo/1` needs: `%{moved: n, folders: n, from: folder_id,
  image_ids: [id], created: [folder_id]}`.
  """
  @spec apply(plan(), keyword()) :: {:ok, map()}
  def apply(plan, opts \\ []) do
    names = Keyword.get(opts, :names, %{})

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

    existing = MapSet.new(Repo.all(from f in Folder, select: f.id))
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    {:ok, moved} =
      Repo.transaction(fn ->
        Enum.flat_map(groups, fn group ->
          target = FolderBrowser.folder_id_for(group.path)

          {_count, ids} =
            Repo.update_all(
              from(i in Image, where: i.id in ^group.image_ids and i.folder_id == ^plan.folder_id, select: i.id),
              set: [folder_id: target, updated_at: now]
            )

          ids
        end)
      end)

    created = Repo.all(from f in Folder, where: f.id not in ^MapSet.to_list(existing), select: f.id)

    {:ok,
     %{
       moved: length(moved),
       folders: groups |> Enum.map(& &1.path) |> Enum.uniq() |> length(),
       from: plan.folder_id,
       image_ids: moved,
       created: created
     }}
  end

  @doc """
  Puts back what `apply/2` moved, and removes the folders it created that are
  empty again. An image an editor has moved on since stays where it was put.
  """
  @spec undo(map()) :: {:ok, non_neg_integer()}
  def undo(%{from: from, image_ids: ids, created: created}) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Repo.transaction(fn ->
      {count, _} =
        Repo.update_all(
          from(i in Image, where: i.id in ^ids and i.folder_id in ^created),
          set: [folder_id: from, updated_at: now]
        )

      remove_empty(created)
      count
    end)
  end

  # Children before parents: a type folder empties when its entry folders go.
  defp remove_empty(folder_ids) do
    folders = Repo.all(from f in Folder, where: f.id in ^folder_ids)

    folders
    |> Enum.sort_by(&(-String.length(&1.path)))
    |> Enum.each(fn folder ->
      images = Repo.aggregate(from(i in Image, where: i.folder_id == ^folder.id), :count)
      children = Repo.aggregate(from(f in Folder, where: f.parent_id == ^folder.id), :count)
      if images + children == 0, do: Repo.delete(folder)
    end)
  end

  # A type's place in the site's `sweep_priority`; unlisted types come after.
  defp rank(schema) do
    priority = Keyword.get(Application.get_env(:brando, Brando.Images, []), :sweep_priority, [])
    Enum.find_index(priority, &(&1 == schema)) || length(priority)
  end

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
