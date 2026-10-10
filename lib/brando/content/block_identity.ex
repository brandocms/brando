defmodule Brando.Content.BlockIdentity do
  @moduledoc """
  What a save keeps of the blocks it writes over rows the entry has, or
  had in a revision being restored: their `sync_uid` (translations match
  blocks and table rows by it) and their `module_version`.

  Neither is castable, so a block inserted under a uid the entry already
  has (a child moved to another parent is a new row there) gets a fresh
  sync uid and no module version. Both come from rows read on the server,
  never from params:

    * `loaded`, the rows the save writes over: a block inserted under one
      of their uids keeps its sync uid, and that row is deleted just before
      the insert, in the save's transaction. Parents are saved in order, so
      a block moved into an earlier one would otherwise be inserted while
      its old row still holds the uid.
    * `restored`, the blocks of a revision being restored (History, or a
      working copy of a revision). A block written with the revision's
      content takes the revision's module version, so a block from before a
      module change shows as needing an upgrade. A block the entry no
      longer has comes back with the revision's sync uid.

  Build both with `index/1`.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Ecto.Changeset

  @typedoc "Blocks by uid, the whole tree under each (`index/1`)."
  @type index :: %{optional(String.t()) => Block.t()}

  # changes that say nothing about a block's content
  @placement [:children, :sequence, :parent_id]

  @doc """
  Index blocks, or entry blocks, by uid: the blocks and every child under
  them.
  """
  @spec index(list() | nil) :: index()
  def index(blocks), do: blocks |> List.wrap() |> Enum.map(&block/1) |> index_by_uid(%{})

  defp block(%{block: %Block{} = block}), do: block
  defp block(block), do: block

  defp index_by_uid(blocks, acc) do
    Enum.reduce(blocks, acc, fn
      %{uid: uid} = block, acc when is_binary(uid) ->
        children = if is_list(Map.get(block, :children)), do: block.children, else: []
        index_by_uid(children, Map.put(acc, uid, block))

      _, acc ->
        acc
    end)
  end

  @doc """
  Apply `loaded` and `restored` to an entry block's changeset and the
  block tree under it.
  """
  @spec keep_entry_block(Changeset.t(), index(), index()) :: Changeset.t()
  def keep_entry_block(%Changeset{} = entry_block, loaded, restored \\ %{}) do
    if loaded == %{} and restored == %{},
      do: entry_block,
      else: map_change(entry_block, :block, &keep(&1, loaded, restored))
  end

  @doc """
  Apply `loaded` and `restored` to a block's changeset and the blocks
  under it.
  """
  @spec keep(Changeset.t(), index(), index()) :: Changeset.t()
  def keep(changeset, loaded, restored \\ %{})

  def keep(%Changeset{action: :insert} = changeset, loaded, restored) do
    uid = Changeset.get_field(changeset, :uid)
    row = loaded[uid]
    revision = restored[uid]

    changeset =
      case {row, revision} do
        {nil, nil} ->
          changeset

        _ ->
          known = row || revision
          version = if revision, do: revision.module_version, else: row.module_version

          changeset
          |> force_present(:sync_uid, known.sync_uid)
          |> force_present(:module_version, version)
          |> map_change(:table_rows, &keep_row_syncs(&1, known))
          |> delete_row_first(row)
      end

    keep_children(changeset, loaded, restored)
  end

  def keep(%Changeset{} = changeset, loaded, restored) do
    changeset
    |> restored_version(restored[Changeset.get_field(changeset, :uid)])
    |> keep_children(loaded, restored)
  end

  def keep(other, _loaded, _restored), do: other

  defp keep_children(changeset, loaded, restored),
    do: map_change(changeset, :children, fn children -> Enum.map(children, &keep(&1, loaded, restored)) end)

  # A block a restore writes the revision's content to is at the revision's
  # module version. One it leaves as it is keeps its own.
  defp restored_version(%Changeset{changes: changes, data: data} = changeset, %{module_version: version})
       when version != data.module_version do
    if changes |> Map.drop(@placement) |> map_size() > 0,
      do: Changeset.force_change(changeset, :module_version, version),
      else: changeset
  end

  defp restored_version(changeset, _revision), do: changeset

  # The changesets a cast made, edited in place: `put_change/3` would cast
  # the relation again, which Ecto refuses for related changesets.
  defp map_change(%Changeset{changes: changes} = changeset, key, fun) when is_map_key(changes, key),
    do: %{changeset | changes: Map.update!(changes, key, fun)}

  defp map_change(changeset, _key, _fun), do: changeset

  # A table row's sync uid is kept only when the params name one the same
  # block has, and each once: two rows never share one.
  defp keep_row_syncs(rows, %{table_rows: known_rows}) when is_list(rows) and is_list(known_rows) do
    known = known_rows |> Enum.map(& &1.sync_uid) |> Enum.reject(&is_nil/1) |> MapSet.new()

    {rows, _known} =
      Enum.map_reduce(rows, known, fn
        %Changeset{action: :insert, params: %{"sync_uid" => sync_uid}} = row, known when is_binary(sync_uid) ->
          if MapSet.member?(known, sync_uid),
            do: {Changeset.force_change(row, :sync_uid, sync_uid), MapSet.delete(known, sync_uid)},
            else: {row, known}

        row, known ->
          {row, known}
      end)

    rows
  end

  defp keep_row_syncs(rows, _block), do: rows

  # Its old parent deletes the row it leaves (`:delete_if_exists`, so it
  # then finds it gone), its refs, rows and children with it.
  defp delete_row_first(changeset, %{id: id} = row) when not is_nil(id) do
    Changeset.prepare_changes(changeset, fn %Changeset{repo: repo} = changeset ->
      opts = if prefix = row.__meta__.prefix, do: [prefix: prefix], else: []
      repo.delete_all(from(b in Block, where: b.id == ^id), opts)
      changeset
    end)
  end

  defp delete_row_first(changeset, _row), do: changeset

  defp force_present(changeset, _field, nil), do: changeset
  defp force_present(changeset, field, value), do: Changeset.force_change(changeset, field, value)
end
