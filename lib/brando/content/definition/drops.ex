defmodule Brando.Content.Definition.Drops do
  @moduledoc """
  Dropping, in a release apply, the values blocks hold in the refs and vars
  the release removes, and putting them back when the apply is reverted.

  Without it, the blocks keep such a value as a leftover until someone
  resolves them (`Brando.Content.StaleBlocks`). An apply that is asked to
  (`Brando.Content.Definitions.Release.apply/2`'s `drop:`) deletes those
  rows instead, in its transaction, and keeps each one whole in
  `Brando.Content.DefinitionDrop` under the apply's batch.

  It drops only what a revert can put back, and nothing else (`plan/2`):

    * a ref or var the apply removes from a local module, held by the
      module's local blocks, that no rename the file declares has as its
      source (`Plan.dropped/1`), under the type the module defines it with:
      a ref an older change retyped stays a leftover;
    * of a module whose apply a revert could undo the day it is applied:
      neither it nor another module of its tree has a reverse that needs a
      migration (`unrevertible` on the plan item) or moves values under
      renamed keys, as `Brando.Content.Definitions.Release.Batches` decides;
    * not a ref whose slot holds blocks or footnotes: dropping the row alone
      would orphan them;
    * nothing at all when the blocks or their entries are more than one
      apply may change while editors' saves wait (`Renames.limit/0`).

  The apply plans this again under its lock, refuses when it differs from
  what the operator reviewed (`digest`), and writes as Resolve blocks does
  (`Brando.Content.BlockMoves.write!/4`). A revert puts the rows back
  (`restore!/4`) for the modules it restores; keeping the apply, or the next
  release apply, deletes them (`discard!/1`).
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Block, BlockMoves, DefinitionDrop, Module, Ref, StaleBlocks, Var}
  alias Brando.Content.Definition.{Importer, Plan, Renames, Value}
  alias Brando.Repo
  alias Brando.Villain.Blocks, as: RefTypes

  ## Planning

  @doc """
  What an apply of `plan` (its selected module updates) would drop:
  `%{modules: [module], left: [%{uid, blocker, reason}], slotted: count,
  blocks: count, entries: [entry], over_limit: nil | map, digest: digest}`.

  Each module has its `uid`, the `keys` (`{:ref | :var, key}`) blocks hold
  a droppable value of, the `rows` (`%{id, block_id, kind, key}`) and its
  `blocks`. `left` are the modules whose values stay leftovers, and why: a
  revert couldn't undo the apply of `blocker` (the module, or another of
  its tree). `slotted` counts the blocks that keep a ref because its slot
  holds blocks or footnotes. `entries` are those of the blocks
  (`BlockMoves.entries/1`), unless the blocks are over the limit already.
  `over_limit` is `Renames.over_limit/1`'s: the apply then drops nothing.
  `digest` is what a review of it saw, for `planned!/2`.

  `lock: true` locks the blocks for the apply's transaction.
  """
  def plan(%Plan{} = plan, opts \\ []) do
    items = Map.new(plan.items, &{&1.uid, &1})
    expand = Importer.selection_expander(plan.bundle)

    {droppable, left} =
      plan.items
      |> Enum.filter(&(&1.kind == "module" and &1.action == :update and Plan.selected?(plan, &1)))
      |> Enum.map(&{&1, Plan.dropped(&1)})
      |> Enum.reject(&(elem(&1, 1) == []))
      |> Enum.split_with(fn {item, _keys} -> is_nil(blocker(expand.(item.uid), items)) end)

    modules =
      droppable
      |> Enum.map(fn {item, keys} -> module_drops(item.uid, keys, opts) end)
      |> Enum.reject(&is_nil/1)

    held = Enum.filter(modules, &(&1.rows != []))
    block_ids = held |> Enum.flat_map(& &1.block_ids) |> Enum.uniq()
    over_blocks = Renames.over_limit([%{blocks: length(block_ids), entries: []}])

    entries =
      if over_blocks,
        do: [],
        else: block_ids |> BlockMoves.entries() |> Map.values() |> List.flatten() |> Enum.uniq_by(&{&1.schema, &1.id})

    %{
      modules: Enum.map(held, &Map.drop(&1, [:block_ids, :slotted])),
      left: for({item, _keys} <- left, do: Map.put(blocker(expand.(item.uid), items), :uid, item.uid)),
      slotted: modules |> Enum.map(& &1.slotted) |> Enum.sum(),
      blocks: length(block_ids),
      entries: entries,
      over_limit: over_blocks || Renames.over_limit([%{blocks: length(block_ids), entries: entries}]),
      digest: digest(held)
    }
  end

  defp digest(modules),
    do: modules |> Enum.flat_map(fn m -> for {kind, key} <- m.keys, do: [m.uid, to_string(kind), key] end) |> Enum.sort() |> Value.digest()

  # The first module of the tree `uids` whose apply a revert couldn't undo,
  # with why: `%{blocker: uid, reason: reason}`, or nil
  defp blocker(uids, items) do
    Enum.find_value(uids, fn uid ->
      case items[uid] do
        %{kind: "module", unrevertible: reason} when is_binary(reason) -> %{blocker: uid, reason: reason}
        %{kind: "module"} = item -> if moves?(item), do: %{blocker: uid, reason: moves_reason(item)}
        _ -> nil
      end
    end)
  end

  # As the batch records the moves a revert can't undo (`Release`)
  defp moves?(%{moves: %{left?: false, renames: renames}}), do: Enum.any?(renames, &(&1.blocks > 0))
  defp moves?(_item), do: false

  defp moves_reason(item),
    do: gettext("it moves values under renamed keys: %{renames}", renames: Renames.text(item.moves.renames))

  # The rows of the local blocks of the module `uid` that hold one of `keys`
  # under the type the module defines it with, but for a ref whose slot
  # holds blocks or footnotes
  defp module_drops(uid, keys, opts) do
    case Repo.one(from(m in Module, where: m.uid == ^uid and is_nil(m.deleted_at), preload: [:vars, refs: ^Ref.preloads()])) do
      nil ->
        nil

      module ->
        if opts[:lock], do: lock!(module, keys)
        rows = Enum.filter(rows(module, keys), &defined_type?(&1, module))
        slotted = slotted(rows)
        rows = Enum.reject(rows, &MapSet.member?(slotted, {&1.block_id, &1.key}))
        kept = MapSet.new(rows, & &1.block_id)
        slotted_blocks = slotted |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length()

        %{
          uid: uid,
          name: StaleBlocks.module_name(module),
          keys: rows |> Enum.map(&{&1.kind, &1.key}) |> Enum.uniq() |> Enum.sort(),
          rows: Enum.map(rows, &Map.take(&1, [:id, :block_id, :kind, :key])),
          block_ids: MapSet.to_list(kept),
          blocks: MapSet.size(kept),
          slotted: slotted_blocks
        }
    end
  end

  defp holders(module, keys) do
    {names, var_keys} = split_keys(keys)
    vars = from(v in Var, where: v.key in ^var_keys and not is_nil(v.block_id), select: v.block_id)
    refs = from(r in Ref, where: r.name in ^names and not is_nil(r.block_id), select: r.block_id)

    from(b in Block,
      where: b.module_id == ^module.id and b.module_origin == :local,
      where: b.id in subquery(vars) or b.id in subquery(refs)
    )
  end

  # The blocks, and the slots under them, in one order, as a rename's move
  # locks them: no child is added to a slot while its ref goes
  defp lock!(module, keys) do
    ids = from(b in holders(module, keys), select: b.id)

    Repo.all(
      from(b in Block,
        where: b.id in subquery(ids) or (b.parent_id in subquery(ids) and b.type == :slot),
        order_by: b.id,
        select: b.id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp rows(module, keys) do
    {names, var_keys} = split_keys(keys)
    ids = from(b in holders(module, keys), select: b.id)

    vars =
      from(v in Var,
        where: v.block_id in subquery(ids) and v.key in ^var_keys,
        order_by: [v.block_id, v.id],
        select: %{id: v.id, block_id: v.block_id, kind: :var, key: v.key, type: v.type}
      )

    refs =
      from(r in Ref,
        where: r.block_id in subquery(ids) and r.name in ^names,
        order_by: [r.block_id, r.id],
        select: %{id: r.id, block_id: r.block_id, kind: :ref, key: r.name, type: fragment("?->>'type'", r.data)}
      )

    Repo.all(vars) ++ Repo.all(refs)
  end

  defp split_keys(keys), do: {for({:ref, key} <- keys, do: key), for({:var, key} <- keys, do: key)}

  # The module as it is before the apply: a row under another type is an
  # older leftover, not this removal's
  defp defined_type?(%{kind: :var, key: key, type: type}, module),
    do: Enum.any?(module.vars, &(&1.key == key and &1.type == type))

  defp defined_type?(%{kind: :ref, key: key, type: type}, module) do
    case Enum.find(module.refs, &(&1.name == key)) do
      nil -> false
      ref -> Module.any_ref_type?(module, key) or RefTypes.ref_types_compatible?(data_struct(ref), ref_struct(type))
    end
  end

  defp data_struct(%{data: %{__struct__: struct}}), do: struct
  defp data_struct(_), do: nil

  defp ref_struct(nil), do: nil
  defp ref_struct(type), do: Enum.find_value(RefTypes.list_blocks(), fn {name, mod} -> to_string(name) == type && mod end)

  # `{block_id, ref}` for each ref row whose block holds blocks or footnotes
  # in the slot of that name
  defp slotted(rows) do
    refs = for %{kind: :ref} = row <- rows, do: row

    if refs == [] do
      MapSet.new()
    else
      from(s in Block,
        left_join: c in Block,
        on: c.parent_id == s.id,
        where: s.type == :slot and s.parent_id in ^Enum.map(refs, & &1.block_id),
        where: s.slot_name in ^Enum.map(refs, & &1.key),
        group_by: [s.parent_id, s.slot_name, s.slot_kind],
        having: s.slot_kind == :footnote or count(c.id) > 0,
        select: {s.parent_id, s.slot_name}
      )
      |> Repo.all()
      |> MapSet.new()
    end
  end

  ## Dropping

  @doc """
  `plan/2` of `plan`, planned again in the apply's transaction with the
  blocks locked, when it is what the review saw (`digest`). Rolls the apply
  back when it differs, or when it is over the limit.
  """
  def planned!(%Plan{} = plan, digest) do
    drops = plan(plan, lock: true)

    cond do
      drops.digest != digest ->
        Repo.rollback(
          gettext(
            "the refs and vars the apply drops values of changed since you reviewed it; review it again"
          )
        )

      drops.over_limit ->
        Repo.rollback(over_limit_text())

      true ->
        drops
    end
  end

  @doc "Why an apply over the limit drops nothing."
  def over_limit_text do
    gettext(
      "an apply drops no values in more than %{max_entries} entries or %{max_blocks} blocks; resolve the blocks after the apply",
      max_entries: Renames.limit()[:entries],
      max_blocks: Renames.limit()[:blocks]
    )
  end

  @doc """
  Drops the rows of `drops` (`planned!/2`'s) in the apply's transaction, as
  `person`, once `changes` (the importer's) saved the modules: keeps each
  row whole under `opts[:batch_id]`, deletes it, and syncs the blocks with
  their module. A revision of each entry before and one after, and Activity
  with `opts[:release]`. Returns `%{uid => %{blocks: count, values: count}}`.
  """
  def drop!(nil, _changes, _person, _opts), do: %{}
  def drop!(%{modules: []}, _changes, _person, _opts), do: %{}

  def drop!(drops, changes, person, opts) do
    saved = Map.new(changes, &{{&1.kind, &1.uid}, &1.id})
    modules = Map.new(drops.modules, &{&1.uid, Repo.get!(Module, saved[{"module", &1.uid}])})
    details = details(drops, opts[:release])

    BlockMoves.write!(drops.entries, person, [before: description(drops, opts[:release]), details: details], fn ->
      Enum.each(drops.modules, fn module ->
        store!(opts[:batch_id], module)
        {vars, refs} = Enum.split_with(module.rows, &(&1.kind == :var))
        Repo.delete_all(from(v in Var, where: v.id in ^Enum.map(vars, & &1.id)))
        Repo.delete_all(from(r in Ref, where: r.id in ^Enum.map(refs, & &1.id)))
        BlockMoves.sync!(modules[module.uid], module.rows |> Enum.map(& &1.block_id) |> Enum.uniq())
      end)
    end)

    Enum.each(modules, fn {_uid, module} ->
      Brando.Activity.setting_changed(:updated, module, StaleBlocks.module_name(module), person, details: details)
    end)

    Map.new(drops.modules, &{&1.uid, %{blocks: &1.blocks, values: length(&1.rows)}})
  end

  # Each row whole, as the database has it
  defp store!(batch_id, module) do
    now = NaiveDateTime.utc_now()

    for {kind, table} <- [{:var, "content_vars"}, {:ref, "content_refs"}],
        ids = for(%{kind: ^kind, id: id} <- module.rows, do: id),
        ids != [] do
      key = if kind == :var, do: "key", else: "name"

      Ecto.Adapters.SQL.query!(
        Repo.repo(),
        """
        INSERT INTO #{table("content_definition_drops")} (batch_id, module_uid, block_id, kind, key, row, inserted_at)
        SELECT $1, $2, t.block_id, $3, t.#{key}, to_jsonb(t), $4 FROM #{table(table)} t WHERE t.id = ANY($5)
        """,
        [Ecto.UUID.dump!(batch_id), module.uid, to_string(kind), now, ids]
      )
    end
  end

  defp description(drops, release) do
    dropped = Enum.map_join(drops.modules, "; ", &gettext("%{keys} in %{module}", keys: keys_text(&1.keys), module: &1.name))

    if release,
      do: gettext("Before release %{release} dropped %{dropped}", release: release, dropped: dropped),
      else: gettext("Before applying module definitions dropped %{dropped}", dropped: dropped)
  end

  defp details(drops, release) do
    %{
      "dropped" => %{
        "release" => release,
        "modules" =>
          Enum.map(drops.modules, fn module ->
            %{
              "uid" => module.uid,
              "module" => module.name,
              "keys" => Enum.map(module.keys, fn {kind, key} -> "#{kind}:#{key}" end),
              "blocks" => module.rows |> Enum.map(& &1.block_id) |> Enum.uniq() |> Enum.sort()
            }
          end)
      }
    }
  end

  @doc "`keys` as a line names them: `var tagline, ref body`."
  def keys_text(keys), do: Enum.map_join(keys, ", ", fn {kind, key} -> "#{kind} #{key}" end)

  ## The record

  @doc "How many blocks the apply `batch_id` dropped values from: a count, nothing loaded."
  def blocks(batch_id) do
    Repo.one(from(d in DefinitionDrop, where: d.batch_id == ^batch_id, select: count(d.block_id, :distinct)))
  end

  @doc "Deletes the rows the applies `batch_ids` dropped: they were kept, and can't be reverted any more."
  def discard!([]), do: :ok

  def discard!(batch_ids) do
    Repo.delete_all(from(d in DefinitionDrop, where: d.batch_id in ^batch_ids))
    :ok
  end

  ## Reverting

  @doc """
  Puts back, in a revert's transaction and before its sync, the rows the
  apply `batch_id` dropped from the blocks of the modules `uids` (those the
  revert restored), as `person`. The rows of the other modules stay with
  the record.

  A block gets its rows back when it still exists, is still a local block
  of the module, and holds no row for that key now: then every stored row
  for the key goes back. Each block is locked for the write. Whatever a
  row points at that is gone is restored empty, and a ref uid taken since
  gets a new one; a row that still won't go back is skipped.

  Returns `%{values: count, blocks: count, skipped: %{reason => count},
  left: count}`: the values put back and the blocks that got them, the
  values that didn't go back by reason (`:block_gone`, `:other_module`,
  `:filled`, `:failed`), and how many blocks of modules the revert left
  keep their values with the record.
  """
  def restore!(batch_id, uids, person, opts) do
    left =
      Repo.one(
        from(d in DefinitionDrop,
          where: d.batch_id == ^batch_id and d.module_uid not in ^uids,
          select: count(d.block_id, :distinct)
        )
      )

    stored = Repo.all(from(d in DefinitionDrop, where: d.batch_id == ^batch_id and d.module_uid in ^uids, order_by: d.id))
    modules = Repo.all(from(m in Module, where: m.uid in ^uids and is_nil(m.deleted_at), preload: [:vars, refs: ^Ref.preloads()]))
    modules = Map.new(modules, &{&1.uid, &1})
    verdicts = verdicts(stored, modules)
    restorable = for {row, :restore} <- verdicts, do: row
    restored = if restorable == [], do: [], else: write_back!(restorable, modules, person, opts)

    restored_ids = MapSet.new(restored, & &1.id)
    Repo.delete_all(from(d in DefinitionDrop, where: d.id in ^MapSet.to_list(restored_ids)))

    skipped =
      verdicts
      |> Enum.map(fn {row, verdict} ->
        if verdict == :restore and not MapSet.member?(restored_ids, row.id), do: :failed, else: verdict
      end)
      |> Enum.reject(&(&1 == :restore))
      |> Enum.frequencies()

    %{
      values: length(restored),
      blocks: restored |> Enum.map(& &1.block_id) |> Enum.uniq() |> length(),
      skipped: skipped,
      left: left
    }
  end

  # Each stored row with whether it goes back, decided for every block and
  # key before anything is written
  defp verdicts([], _modules), do: []

  defp verdicts(stored, modules) do
    block_ids = stored |> Enum.map(& &1.block_id) |> Enum.uniq()

    blocks =
      from(b in Block,
        where: b.id in ^block_ids,
        order_by: b.id,
        select: {b.id, %{module_id: b.module_id, origin: b.module_origin}},
        lock: "FOR UPDATE"
      )
      |> Repo.all()
      |> Map.new()

    vars = from(v in Var, where: v.block_id in ^block_ids, select: {v.block_id, "var", v.key})
    refs = from(r in Ref, where: r.block_id in ^block_ids, select: {r.block_id, "ref", r.name})
    filled = MapSet.new(Repo.all(vars) ++ Repo.all(refs))

    for row <- stored do
      module = modules[row.module_uid]
      block = blocks[row.block_id]

      verdict =
        cond do
          is_nil(block) -> :block_gone
          is_nil(module) or block.module_id != module.id or block.origin != :local -> :other_module
          MapSet.member?(filled, {row.block_id, row.kind, row.key}) -> :filled
          true -> :restore
        end

      {row, verdict}
    end
  end

  defp write_back!(rows, modules, person, opts) do
    block_ids = rows |> Enum.map(& &1.block_id) |> Enum.uniq()
    entries = block_ids |> BlockMoves.entries() |> Map.values() |> List.flatten() |> Enum.uniq_by(&{&1.schema, &1.id})
    by_module = Enum.group_by(rows, & &1.module_uid)
    details = restored_details(by_module, modules, opts[:release])
    before = restored_description(by_module, modules, opts[:release])

    restored =
      BlockMoves.write!(entries, person, [before: before, details: details], fn ->
        columns = %{"var" => columns("content_vars"), "ref" => columns("content_refs")}
        restored = Enum.filter(rows, &insert(&1, columns))
        restored_ids = MapSet.new(restored, & &1.id)

        Enum.each(by_module, fn {uid, module_rows} ->
          ids = for row <- module_rows, MapSet.member?(restored_ids, row.id), uniq: true, do: row.block_id
          if ids != [], do: BlockMoves.sync!(modules[uid], ids)
        end)

        restored
      end)

    Enum.each(by_module, fn {uid, _rows} ->
      module = modules[uid]
      Brando.Activity.setting_changed(:updated, module, StaleBlocks.module_name(module), person, details: details)
    end)

    restored
  end

  # The row back in its block, in a savepoint: a row that won't go back
  # leaves the rest of the revert as it is
  defp insert(%DefinitionDrop{kind: kind, row: row}, columns) do
    {schema, table} = if kind == "var", do: {Var, "content_vars"}, else: {Ref, "content_refs"}
    row = prepare(row, schema)
    names = Enum.filter(columns[kind], &Map.has_key?(row, &1))
    list = Enum.map_join(names, ", ", &~s("#{&1}"))

    sql =
      "INSERT INTO #{table(table)} (#{list}) SELECT #{list} FROM jsonb_populate_record(NULL::#{table(table)}, $1)"

    match?({:ok, _}, Ecto.Adapters.SQL.query(Repo.repo(), sql, [row], mode: :savepoint))
  rescue
    _error in [DBConnection.EncodeError, ArgumentError] -> false
  end

  # A new id; anything the row points at that is gone, empty; a ref uid
  # taken since, a new one
  defp prepare(row, schema) do
    row =
      for association <- schema.__schema__(:associations),
          %Ecto.Association.BelongsTo{owner_key: key, related: related} <- [schema.__schema__(:association, association)],
          key != :block_id,
          id = row[to_string(key)],
          not exists?(from(r in related, where: r.id == ^id)),
          reduce: Map.delete(row, "id"),
          do: (row -> Map.put(row, to_string(key), nil))

    if schema == Ref and exists?(from(r in Ref, where: r.uid == ^row["uid"])),
      do: Map.put(row, "uid", Brando.Utils.generate_uid()),
      else: row
  end

  defp exists?(query), do: Repo.one(from(r in query, select: true, limit: 1)) == true

  defp columns(table) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo.repo(),
        "SELECT column_name FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2 AND column_name != 'id'",
        [prefix(), table]
      )

    List.flatten(rows)
  end

  defp restored_description(by_module, modules, release) do
    restored =
      Enum.map_join(by_module, "; ", fn {uid, rows} ->
        keys = rows |> Enum.map(&{&1.kind, &1.key}) |> Enum.uniq() |> Enum.sort()
        gettext("%{keys} in %{module}", keys: keys_text(keys), module: StaleBlocks.module_name(modules[uid]))
      end)

    gettext("Before reverting release %{release} restored %{restored}", release: release, restored: restored)
  end

  defp restored_details(by_module, modules, release) do
    %{
      "restored" => %{
        "release" => release,
        "modules" =>
          Enum.map(by_module, fn {uid, rows} ->
            %{
              "uid" => uid,
              "module" => StaleBlocks.module_name(modules[uid]),
              "keys" => rows |> Enum.map(&"#{&1.kind}:#{&1.key}") |> Enum.uniq() |> Enum.sort(),
              "blocks" => rows |> Enum.map(& &1.block_id) |> Enum.uniq() |> Enum.sort()
            }
          end)
      }
    }
  end

  defp table(name), do: ~s("#{prefix()}"."#{name}")
  defp prefix, do: Brando.Tenant.current_prefix() || "public"
end
