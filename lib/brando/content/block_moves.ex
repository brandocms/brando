defmodule Brando.Content.BlockMoves do
  @moduledoc """
  Changing entries' blocks outside their editors, as Resolve blocks
  (`Brando.Content.StaleBlocks`) and a definition apply that moves values
  under renamed keys (`Brando.Content.Definition.Renames`) do.

  `write!/4` runs the change between one revision of each entry before it
  and one after, however many modules it touches, records it in each
  entry's Activity and moves editors that have the entry open onto the new
  rows. Entries in the trash change like any other: one restored from it
  shows what the change left. An entry whose schema keeps no revisions (a
  template) gets none.

  It runs in the caller's transaction, and any failure rolls it back.
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{BlockReferences, Blocks, Ref, Usage, Var}
  alias Brando.Repo
  alias Ecto.Changeset

  @var_fields ~w(value value_boolean image_id file_id video_id gallery_id form_id identifier_id palette_id link_text link_type link_target_blank)a
  @ref_media ~w(image_id video_id gallery_id file_id)a

  @doc """
  The entries that own `block_ids`, those in the trash too, by block:
  `%{block_id => [entry]}`. Each entry has its `schema`, `id`, label fields
  (`Brando.Content.Usage.labels/1`), `trashed?` and `revisioned?` (whether
  History can restore it).
  """
  def entries([]), do: %{}

  def entries(block_ids) do
    by_block = BlockReferences.list_entries_for_block_ids(block_ids, include_deleted: true)
    entries = by_block |> Map.values() |> List.flatten() |> Enum.uniq()
    labels = Usage.labels(entries)
    states = states(entries)

    Map.new(by_block, fn {block_id, entries} ->
      {block_id, Enum.map(entries, &entry(&1, labels[&1], Map.get(states, &1, %{})))}
    end)
  end

  defp entry({schema, id}, label, state) do
    trashed? = Map.get(state, :deleted_at) != nil

    label
    |> Map.merge(%{
      schema: schema,
      id: id,
      trashed?: trashed?,
      revisioned?: schema.has_trait(Brando.Trait.Revisioned)
    })
    |> Map.update(:language, nil, &(&1 || Map.get(state, :language)))
    |> Map.update(:url, nil, &if(trashed?, do: trash_url(&1), else: &1))
  end

  # The listing's trash: an entry in it has no edit page.
  defp trash_url(nil), do: nil
  defp trash_url(url), do: String.replace(url, ~r{/update/\d+$}, "") <> "?status=deleted"

  # What an entry's identifier row does not say: its language (an entry
  # without one has it only on itself) and whether it is in the trash.
  defp states(entries) do
    entries
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {schema, ids} ->
      fields = Enum.filter([:id, :language, :deleted_at], &(&1 in schema.__schema__(:fields)))

      from(e in schema, where: e.id in ^ids, select: map(e, ^fields))
      |> Repo.all()
      |> Enum.map(&{{schema, &1.id}, &1})
    end)
    |> Map.new()
  end

  @doc """
  Runs `change` on the blocks of `entries` (as `entries/1` gives them), as
  `user`: a revision of each entry described `opts[:before]` first, and
  after it one more and an Activity record with `opts[:details]`. Returns
  what `change` returns.
  """
  def write!(entries, user, opts, change) do
    keys = Enum.map(entries, &{&1.schema, &1.id})
    before = revisions!(load(keys), user, false, opts[:before])
    result = change.()
    loaded = load(keys)
    saved = revisions!(loaded, user, true, nil)

    records =
      for %schema{id: id} = entry <- loaded, Brando.Activity.logged?(schema) do
        key = {schema, id}
        {entry, revision: saved[key] || before[key], details: opts[:details]}
      end

    Brando.Activity.record_all(:updated, records, user)

    Enum.each(loaded, fn entry ->
      Brando.EditSession.sync_saved(entry)
      Repo.after_commit(fn -> Brando.Cache.Query.evict({:ok, entry}) end)
    end)

    result
  end

  defp load(keys) do
    keys
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {schema, ids} -> Repo.all(from(e in schema, where: e.id in ^ids, order_by: e.id)) end)
  end

  # A revision of each entry whose schema keeps them
  defp revisions!(entries, user, active?, description) do
    revisioned = Enum.filter(entries, fn %schema{} -> schema.has_trait(Brando.Trait.Revisioned) end)

    case Brando.Revisions.create_revisions(revisioned, user, active?, description) do
      {:ok, revisions} ->
        revisions

      {:error, reason} ->
        Repo.rollback(gettext("Could not store the entries' revisions: %{reason}", reason: inspect(reason)))
    end
  end

  @doc """
  Syncs `block_ids` with `module` (`Blocks.sync_module/2`), which stamps
  each one that holds nothing the module doesn't back, and saves them.
  A block that won't save rolls the transaction back.
  """
  def sync!(module, block_ids) do
    module = Repo.preload(module, [:vars, refs: Ref.preloads()], force: true)

    from(b in Brando.Content.Block, where: b.id in ^block_ids, preload: [:vars, refs: ^Ref.preloads()])
    |> Repo.all()
    |> Enum.each(fn block ->
      case block |> Blocks.sync_module(module) |> Repo.update() do
        {:ok, _} -> :ok
        {:error, changeset} -> Repo.rollback(sync_error(block, changeset))
      end
    end)
  end

  defp sync_error(block, changeset),
    do: gettext("Block #%{id} could not be saved: %{errors}", id: block.id, errors: error_lines(changeset))

  @doc false
  def error_lines(changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, _} -> message end)
    |> inspect()
  end

  @doc """
  Whether a block's var or ref holds something of its own: a stored choice
  that is neither empty nor the one `definition` (the module's var or ref
  of that key, or nil) gives it. Judged by the stored fields, not by a
  preview: two links with one label and different addresses differ, and so
  do a link that opens in a new tab and one that doesn't. A ref is compared
  by its data and media, not its uid (a copied ref has a fresh one).
  """
  def content?(row, definition),
    do: Enum.any?(stored(row), fn {field, value} -> own?(value, stored(definition)[field]) end)

  defp own?(value, default), do: value != default and not blank?(value)

  defp stored(nil), do: %{}
  defp stored(%Var{} = var), do: var |> Map.take(@var_fields) |> Map.new(fn {k, v} -> {k, plain(v)} end)

  defp stored(%Ref{} = ref) do
    data =
      case ref.data do
        %{data: %_{} = data} -> data |> Map.from_struct() |> Map.new(fn {k, v} -> {k, plain(v)} end)
        _ -> %{}
      end

    Map.merge(data, Map.take(ref, @ref_media))
  end

  # A nested embed compares by what it holds
  defp plain(%_{} = struct) when not is_struct(struct, DateTime) and not is_struct(struct, Date),
    do: struct |> Map.from_struct() |> Map.drop([:__meta__]) |> Map.new(fn {k, v} -> {k, plain(v)} end)

  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(""), do: nil
  defp plain(value), do: value

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(value) when value == [] or value == %{}, do: true
  defp blank?(_value), do: false
end
