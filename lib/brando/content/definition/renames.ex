defmodule Brando.Content.Definition.Renames do
  # How many entries and blocks one apply moves values in, for all the
  # modules it selects: see the moduledoc
  @limit [entries: 500, blocks: 1500]

  @moduledoc """
  The renames a module's definition file declares (`renamed_from:` on a ref
  or var, carried in the bundle's `"renames"`), and the values they move
  when the definition is applied.

  A rename moves values only in the apply that removes its source key and
  adds its destination (`split/2`): there it moves each block's value from
  the old key to the new one, in the apply's transaction. Anywhere else it
  does nothing, and blocks that still hold the old key keep it as a leftover
  (`remaps/3` says whether a `resolve --map` would move it).

  The first version moves only what keeps its type. The plan refuses, with
  the blocks it names:

    * a rename whose definition changes type (var type, ref block type);
    * a block whose stored value doesn't fit the new key (stored under
      another type, or not one of a select's options);
    * a block that holds a value of its own under the new key already
      (`Brando.Content.BlockMoves.content?/2`), or a region or footnotes in a
      slot of that name.

  The apply plans the moves again with the rows locked (`move!/3`), and
  rolls back when anything is refused now.

  The apply holds the definition tables locked while it moves, and every
  editor's save in the environment waits for it: when the renames would
  move values in more than #{@limit[:entries]} entries or #{@limit[:blocks]} blocks,
  counted across the modules one apply selects, the apply moves none of
  them. It adds the new keys, the blocks keep each value under the old one
  as a leftover, and `resolve --map` moves them after the apply (the plan
  prints the command while the file declares the rename). Only what that
  command can't move either is refused then: a rename that changes type,
  and a ref whose slot holds blocks.

  Measured on the development machine the limit was set on (pages with
  three blocks each; from the apply's call to the end of its transaction):

  | Entries | Blocks | Lock held | With fresh table statistics |
  |---|---|---|---|
  | 120 | 360 | 0.5–0.6 s | 0.3 s |
  | 500 | 1500 | 1.7–1.9 s | 1.3 s |
  | 1000 | 3000 | 5.3–5.7 s | 3.6 s |

  The revisions and Activity rows are written in bulk; most of what is
  left is each entry's content event (about 1.7 ms) and each block's sync
  (about 0.25 ms). Raise the limit here if editors' saves may wait longer.
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.{Block, BlockMoves, Ref, StaleBlocks, Var}
  alias Brando.Content.Definition.Plan
  alias Brando.Repo
  alias Brando.Villain.Blocks, as: RefTypes

  @type rename :: %{kind: :ref | :var, from: String.t(), to: String.t()}

  @doc "The renames `bundle` declares for the module `uid`."
  @spec declared(map(), String.t()) :: [rename()]
  def declared(bundle, uid) do
    for rename <- get_in(bundle, ["renames", uid]) || [],
        do: %{kind: if(rename["kind"] == "ref", do: :ref, else: :var), from: rename["from"], to: rename["to"]}
  end

  @doc "`rename` as a batch records it."
  def to_json(%{kind: kind, from: from, to: to}), do: %{"kind" => to_string(kind), "from" => from, "to" => to}

  @doc """
  `renames` split into those an update with `diff` (`Brando.Content.ModuleDiff`)
  carries out, which remove the source and add the destination, and the rest.
  """
  def split(renames, diff) do
    Enum.split_with(renames, fn %{kind: kind, from: from, to: to} ->
      {removed, added} =
        if kind == :ref, do: {diff.removed_refs, diff.added_refs}, else: {diff.removed_vars, diff.added_vars}

      from in removed and to in added
    end)
  end

  ## Planning

  @doc """
  What moving `renames` does to the blocks of the module `record` (stored,
  with its refs and vars), once the module is `module` (with refs and
  vars): `%{renames: [rename with blocks and entries], blocks: count,
  entries: [entry], unrevisioned: count, refused: [reason], left?: boolean}`.
  Each reason names the entries `viewer` may read and counts the others.

  Over the limit the apply moves nothing (`left?`, `leave/1`): blocks over
  it are counted without loading them, and only what the resolve command
  can't move either is refused (`refused_if_left`).
  """
  def plan(record, module, renames, viewer) do
    holders = Map.new(renames, &{&1, holder_ids(record.id, [&1])})
    ids = holders |> Map.values() |> List.flatten() |> Enum.uniq() |> Enum.sort()
    counted = Enum.map(renames, &Map.merge(&1, %{blocks: length(holders[&1]), entries: 0}))

    refused_if_left =
      renames
      |> Enum.zip(counted)
      |> Enum.flat_map(fn {rename, counted} ->
        (definition_refusal(counted, record, module, viewer) || []) ++ slot_refusal(rename, holders[rename])
      end)

    if length(ids) > @limit[:blocks] do
      %{
        renames: counted,
        blocks: length(ids),
        entries: [],
        unrevisioned: 0,
        refused: refused_if_left,
        refused_if_left: refused_if_left,
        left?: true
      }
    else
      plan = Map.merge(loaded(record, module, renames, ids, viewer), %{refused_if_left: refused_if_left, left?: false})
      if over_limit([plan]), do: leave(plan), else: plan
    end
  end

  @doc """
  `plan` (`plan/4`'s) as an apply that moves nothing: the blocks keep each
  value under the old key, for the resolve command, and only what that
  command can't move either is refused.
  """
  def leave(plan), do: %{plan | left?: true, refused: plan.refused_if_left}

  defp loaded(record, module, renames, ids, viewer) do
    blocks = load(ids)
    entries = BlockMoves.entries(ids)
    owners = fn holders -> holders |> Enum.flat_map(&Map.get(entries, &1.id, [])) |> Enum.uniq_by(&{&1.schema, &1.id}) end

    planned =
      Enum.map(renames, fn rename ->
        holders = Enum.filter(blocks, &row(&1, rename.kind, rename.from))
        Map.merge(rename, %{blocks: length(holders), entries: length(owners.(holders)), holders: holders})
      end)

    refused =
      Enum.flat_map(planned, fn rename ->
        definition_refusal(rename, record, module, viewer) ||
          block_refusals(rename, module, fn holders -> entry_text(owners.(holders), viewer) end)
      end)

    moved = owners.(blocks)

    %{
      renames: Enum.map(planned, &Map.delete(&1, :holders)),
      blocks: length(blocks),
      entries: moved,
      unrevisioned: Enum.count(moved, &(not &1.revisioned?)),
      refused: refused
    }
  end

  @doc """
  Whether `moves` (`plan/4`'s, of the modules one apply selects) move more
  together than an apply may while editors' saves wait for it: nil, or
  the blocks and distinct entries they move.
  """
  def over_limit(moves) do
    blocks = moves |> Enum.map(& &1.blocks) |> Enum.sum()
    entries = moves |> Enum.flat_map(& &1.entries) |> Enum.uniq_by(&{&1.schema, &1.id}) |> length()

    if blocks > @limit[:blocks] or entries > @limit[:entries],
      do: %{blocks: blocks, entries: entries, modules: length(moves)}
  end

  @doc """
  What an apply leaves of `renames` (with their `blocks`) in the blocks of
  the module `uid`, and the resolve command `viewer` runs to move it, as a
  line: nil when no block holds a value of them.
  """
  def left_text(uid, renames, viewer) do
    case resolve_command([{uid, renames}], viewer) do
      "" ->
        nil

      command ->
        gettext(
          "%{renames}: the apply moves no values over its limit (%{max_entries} entries, %{max_blocks} blocks), and the blocks keep them under the old names; move them with %{command}, as a user who may edit those entries",
          renames: text(Enum.filter(renames, &(&1.blocks > 0))),
          max_entries: @limit[:entries],
          max_blocks: @limit[:blocks],
          command: command
        )
    end
  end

  # The resolve command of each module, as one shell line, that moves the
  # values of `modules`: only the renames blocks hold a value of, as
  # resolve refuses a key no block holds
  defp resolve_command(modules, viewer) do
    user_id = if is_map(viewer), do: viewer.id

    for {uid, renames} <- modules, held = Enum.filter(renames, &(&1.blocks > 0)), held != [] do
      Plan.resolve_command(uid, user_id, [], held)
    end
    |> Enum.join(" && ")
  end

  # The blocks of the module, here, that hold a source key
  defp holder_ids(module_id, renames) do
    keys = for %{kind: :var, from: from} <- renames, do: from
    names = for %{kind: :ref, from: from} <- renames, do: from
    vars = from(v in Var, where: v.key in ^keys and not is_nil(v.block_id), select: v.block_id)
    refs = from(r in Ref, where: r.name in ^names and not is_nil(r.block_id), select: r.block_id)

    from(b in Block,
      where: b.module_id == ^module_id and b.module_origin == :local,
      where: b.id in subquery(vars) or b.id in subquery(refs),
      order_by: b.id,
      select: b.id
    )
    |> Repo.all()
  end

  defp load([]), do: []

  defp load(ids) do
    slots =
      from(s in Block,
        left_join: c in Block,
        on: c.parent_id == s.id,
        where: s.parent_id in ^ids and s.type == :slot,
        group_by: s.id,
        select: %{parent_id: s.parent_id, name: s.slot_name, kind: s.slot_kind, children: count(c.id)}
      )
      |> Repo.all()
      |> Enum.group_by(& &1.parent_id)

    from(b in Block, where: b.id in ^ids, order_by: b.id, preload: [:vars, refs: ^Ref.preloads()])
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :slots, Map.get(slots, &1.id, [])))
  end

  defp definition_refusal(%{kind: :var, from: from, to: to} = rename, record, module, viewer) do
    source = Enum.find(record.vars, &(&1.key == from))
    target = Enum.find(module.vars, &(&1.key == to))

    if source && target && source.type != target.type,
      do: [changes_type(rename, record.uid, {source.type, target}, viewer)]
  end

  defp definition_refusal(%{kind: :ref, from: from, to: to} = rename, record, module, viewer) do
    source = Enum.find(record.refs, &(&1.name == from))
    target = Enum.find(module.refs, &(&1.name == to))

    if source && target && StaleBlocks.ref_type(source) != StaleBlocks.ref_type(target),
      do: [changes_type(rename, record.uid, {StaleBlocks.ref_type(source), target}, viewer)]
  end

  # The resolve command is offered when it converts the values (`StaleBlocks.targets/4`)
  defp changes_type(rename, uid, {old_type, target}, viewer) do
    [%{type: new_type, ok?: convertible?}] =
      StaleBlocks.targets(rename.kind, rename.from, [old_type], %{rename.kind => %{rename.to => target}})

    bindings = [subject: subject(rename.kind, rename.from, rename.to), old_type: old_type, new_type: new_type]

    case convertible? && resolve_command([{uid, [rename]}], viewer) do
      command when command not in [nil, false, ""] ->
        gettext(
          "%{subject} changes type (%{old_type} → %{new_type}): rename it in one release and change the type in the next, or take renamed_from out of the file, and after the apply move the values with %{command}, as a user who may edit those entries; it names any block whose value it can't convert, and then changes nothing. Without renamed_from the plan's resolve line drops them instead: don't run that one.",
          Keyword.put(bindings, :command, command)
        )

      _ ->
        gettext(
          "%{subject} changes type (%{old_type} → %{new_type}): rename it in one release and change the type in the next",
          bindings
        )
    end
  end

  # A ref whose slot holds blocks: the resolve command renames the ref, not
  # the slot, so its values can't be left for it
  defp slot_refusal(%{kind: :var}, _ids), do: []

  defp slot_refusal(%{kind: :ref} = rename, ids) do
    case slotted(rename, ids) do
      0 ->
        []

      count ->
        [
          ngettext(
            "%{subject}: 1 block holds blocks in the slot of %{from}, which mix brando.modules resolve doesn't move, and the apply moves no values over its limit (%{max_entries} entries, %{max_blocks} blocks): move them out of the slot first, or apply fewer modules at once",
            "%{subject}: %{count} blocks hold blocks in the slot of %{from}, which mix brando.modules resolve doesn't move, and the apply moves no values over its limit (%{max_entries} entries, %{max_blocks} blocks): move them out of the slot first, or apply fewer modules at once",
            count,
            subject: subject(:ref, rename.from, rename.to),
            from: rename.from,
            max_entries: @limit[:entries],
            max_blocks: @limit[:blocks]
          )
        ]
    end
  end

  defp block_refusals(%{holders: holders} = rename, module, owners) do
    target = target(module, rename.kind, rename.to)

    holders
    |> Enum.flat_map(fn block ->
      source = row(block, rename.kind, rename.from)
      for problem <- [fit(source, target), occupied(block, rename, target)], problem, do: {problem, block}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map(fn {problem, blocks} ->
      ids = Enum.map_join(blocks, ", ", &"##{&1.id}")

      problem_text(problem,
        subject: subject(rename.kind, rename.from, rename.to),
        blocks: ids,
        from: rename.from,
        to: rename.to
      ) <>
        owners.(blocks)
    end)
  end

  # Whether the stored value fits the new key: stored under its type, and
  # one of a select's options
  defp fit(%Var{} = var, %Var{} = target) do
    cond do
      var.type != target.type -> :type
      not option?(var, target) -> :option
      true -> nil
    end
  end

  defp fit(%Ref{} = ref, %Ref{} = target),
    do: unless(RefTypes.ref_types_compatible?(data_type(target), data_type(ref)), do: :type)

  defp option?(%Var{value: value}, %Var{type: :select, options: options})
       when value not in [nil, ""] and is_list(options),
       do: Enum.any?(options, &(&1.value == value))

  defp option?(_var, _target), do: true

  defp occupied(block, %{kind: kind, to: to}, target) do
    own = row(block, kind, to)
    slots = if kind == :ref, do: Enum.filter(block.slots, &(&1.name == to)), else: []

    if (own != nil and BlockMoves.content?(own, target)) or Enum.any?(slots, &(&1.kind == :footnote or &1.children > 0)),
      do: :occupied
  end

  defp problem_text(:type, bindings),
    do: gettext("%{subject}: blocks %{blocks} hold %{from} as another type than %{to} has", bindings)

  defp problem_text(:option, bindings),
    do: gettext("%{subject}: blocks %{blocks} hold a value of %{from} that is not one of %{to}'s options", bindings)

  defp problem_text(:occupied, bindings),
    do:
      gettext(
        "%{subject}: blocks %{blocks} already hold a value under %{to}; drop or move it under Resolve blocks first",
        bindings
      )

  defp subject(kind, from, to), do: gettext(~s(%{kind} "%{to}" renamed from "%{from}"), kind: kind, to: to, from: from)

  # The entries the person may open, named; the others counted
  defp entry_text([], _viewer), do: ""

  defp entry_text(entries, viewer) do
    {readable, hidden} = Enum.split_with(entries, &(Boundary.authorize_record(viewer, :read, &1.schema, &1.id) == :ok))
    named = Enum.map(readable, & &1.label)

    hidden =
      case length(hidden) do
        0 -> []
        count -> [ngettext("1 entry you cannot open", "%{count} entries you cannot open", count)]
      end

    " (" <> gettext("in %{entries}", entries: Enum.join(named ++ hidden, ", ")) <> ")"
  end

  @doc """
  Of the declared renames an update doesn't carry out (`split/2`), those
  whose source key `module` (with refs and vars) doesn't define and blocks
  of the module `record` hold: leftovers a `resolve --map` moves onto the
  destination. Each has `ok?`: whether a dry run of that mapping finds them
  and refuses nothing (a block whose destination an editor filled in keeps
  both, `StaleBlocks.keep_filled/2`), and no block holds blocks in a slot
  of the old ref, which the mapping doesn't move. Over the apply's limit
  the blocks aren't loaded for the dry run: the command refuses what it
  can't move by name.
  """
  def remaps(_record, _module, []), do: []

  def remaps(record, module, renames),
    do: for({rename, ids} <- held(record, module, renames), do: Map.put(rename, :ok?, remap?(module, rename, ids)))

  @doc """
  Of the declared renames of the module `record` (with refs and vars),
  applied already, those whose source key blocks still hold: values an
  apply left for `resolve --map` (`leave/1`), as `remaps/3` gives them. The
  blocks aren't loaded for a dry run, as for any rename an apply left: the
  command refuses what it can't move by name. A new key the module lacks
  by now (removed in the admin since) has no command to offer.
  """
  def left(record, renames) do
    for {rename, ids} <- held(record, record, renames) do
      Map.put(rename, :ok?, target(record, rename.kind, rename.to) != nil and slotted(rename, ids) == 0)
    end
  end

  defp held(record, module, renames) do
    for rename <- renames,
        !target(module, rename.kind, rename.from),
        ids = holder_ids(record.id, [rename]),
        ids != [],
        do: {rename, ids}
  end

  defp remap?(module, rename, ids) do
    if Enum.count(ids) > @limit[:blocks] do
      slotted(rename, ids) == 0
    else
      report = StaleBlocks.report_for(module, ids)
      resolutions = %{{rename.kind, rename.from} => {:map, rename.to}}
      {resolutions, _kept} = StaleBlocks.keep_filled(StaleBlocks.plan(report, resolutions), resolutions)
      dry_run = StaleBlocks.plan(report, resolutions)
      dry_run.refused == [] and dry_run.changes != [] and slotted(rename, ids) == 0
    end
  end

  # How many of the blocks `ids` hold blocks in a slot of the renamed ref
  defp slotted(%{kind: :var}, _ids), do: 0

  defp slotted(%{kind: :ref, from: from}, ids) do
    Repo.one(
      from(s in Block,
        join: c in Block,
        on: c.parent_id == s.id,
        where: s.parent_id in ^ids and s.type == :slot and s.slot_name == ^from,
        select: count(s.parent_id, :distinct)
      )
    )
  end

  ## Applying

  @doc """
  Moves the values of `moves` (`[%{record: stored, module: saved, renames:
  renames}]`, each module as the apply found it and as it saved it) in the
  apply's transaction, as `person`: the blocks that hold a source key are
  locked and planned again, and anything refused now rolls the apply back.
  When they move more together than the apply may (`over_limit/1`), none
  moves: the blocks keep the values for the resolve command (`leave/1`).
  One revision of each entry before and one after, however many modules
  move; each entry and module records the renames in Activity with
  `opts[:release]`.

  Returns each module's plan (`plan/4`) by uid: what the apply moved, or
  left (`left?`).
  """
  def move!([], _person, _opts), do: %{}

  def move!(moves, person, opts) do
    moves =
      Enum.map(moves, fn move ->
        Map.put(move, :holders, Map.new(move.renames, &{&1, holder_ids(move.record.id, [&1])}))
      end)

    moves |> Enum.flat_map(&(&1.holders |> Map.values() |> List.flatten())) |> lock!()
    planned = Enum.map(moves, &Map.put(&1, :plan, plan(&1.record, &1.module, &1.renames, person)))

    together? = over_limit(Enum.map(planned, & &1.plan)) != nil
    planned = if together?, do: Enum.map(planned, &Map.update!(&1, :plan, fn plan -> leave(plan) end)), else: planned

    # Left together, what is refused is what the resolve command can't move
    # either, which a review of each module alone doesn't refuse
    case Enum.flat_map(planned, & &1.plan.refused) do
      [] -> :ok
      refused when together? -> Repo.rollback(Enum.join(refused, "; "))
      refused -> Repo.rollback(changed_since_review(refused))
    end

    case Enum.reject(planned, & &1.plan.left?) do
      [] -> :ok
      moving -> write!(moving, person, opts)
    end

    Map.new(planned, &{&1.record.uid, &1.plan})
  end

  defp write!(planned, person, opts) do
    entries = planned |> Enum.flat_map(& &1.plan.entries) |> Enum.uniq_by(&{&1.schema, &1.id})
    details = details(planned, opts[:release])

    BlockMoves.write!(entries, person, [before: description(planned, opts[:release]), details: details], fn ->
      Enum.each(planned, fn move ->
        Enum.each(move.renames, &rename_rows!(&1, move.holders[&1]))
        BlockMoves.sync!(move.module, move.holders |> Map.values() |> List.flatten() |> Enum.uniq())
      end)
    end)

    Enum.each(planned, fn move ->
      Brando.Activity.setting_changed(:updated, move.module, StaleBlocks.module_name(move.module), person,
        details: details
      )
    end)
  end

  @doc "Why an apply is refused when `refused` (reasons) changed since the review."
  def changed_since_review(refused),
    do: gettext("content changed since you reviewed it: %{reasons}; review again", reasons: Enum.join(refused, "; "))

  # The blocks, and the slots under them, in one order, so no child is added
  # to a region while it moves. The importer's table lock already holds the
  # refs and vars.
  defp lock!(ids) do
    Repo.all(
      from(b in Block,
        where: b.id in ^ids or (b.parent_id in ^ids and b.type == :slot),
        order_by: b.id,
        select: b.id,
        lock: "FOR UPDATE"
      )
    )
  end

  # Each block's own empty copy of the destination gives way (anything else
  # was refused), then the source takes its name
  defp rename_rows!(%{kind: :var, from: from, to: to}, ids) do
    Repo.delete_all(from(v in Var, where: v.block_id in ^ids and v.key == ^to))
    Repo.update_all(from(v in Var, where: v.block_id in ^ids and v.key == ^from), set: [key: to])
  end

  defp rename_rows!(%{kind: :ref, from: from, to: to}, ids) do
    Repo.delete_all(from(r in Ref, where: r.block_id in ^ids and r.name == ^to))
    Repo.update_all(from(r in Ref, where: r.block_id in ^ids and r.name == ^from), set: [name: to])

    Repo.delete_all(
      from(s in Block,
        as: :slot,
        where: s.parent_id in ^ids and s.type == :slot and s.slot_kind == :region and s.slot_name == ^to,
        where: not exists(from(c in Block, where: c.parent_id == parent_as(:slot).id, select: 1))
      )
    )

    Repo.update_all(
      from(s in Block, where: s.parent_id in ^ids and s.type == :slot and s.slot_name == ^from),
      set: [slot_name: to]
    )
  end

  defp description(planned, release) do
    renames =
      Enum.map_join(
        planned,
        "; ",
        &gettext("%{renames} in %{module}", renames: text(&1.renames), module: StaleBlocks.module_name(&1.module))
      )

    if release,
      do: gettext("Before release %{release}: %{renames}", release: release, renames: renames),
      else: gettext("Before applying module definitions: %{renames}", renames: renames)
  end

  defp details(planned, release) do
    %{
      "renamed" => %{
        "release" => release,
        "modules" =>
          Enum.map(planned, fn move ->
            %{
              "uid" => move.module.uid,
              "module" => StaleBlocks.module_name(move.module),
              "renames" => Enum.map(move.renames, &"#{&1.kind}:#{&1.from}→#{&1.to}"),
              "blocks" => move.holders |> Map.values() |> List.flatten() |> Enum.uniq() |> Enum.sort()
            }
          end)
      }
    }
  end

  @doc "`renames` as a line names them: `var title → heading, ref body → text`."
  def text(renames), do: Enum.map_join(renames, ", ", &"#{&1.kind} #{&1.from} → #{&1.to}")

  ## In memory

  @doc """
  `block` (as a render reads it, with its refs, vars and children) with
  `renames` moved as the apply moves them: the source takes the
  destination's name, and the block's own copy of the destination gives
  way. `Brando.Content.Definitions.Release.Proposed` renders with it, so a
  rename verifies as unchanged.
  """
  def rename(block, renames) do
    Enum.reduce(renames, block, fn rename, block ->
      if is_list(rows(block, rename.kind)) and row(block, rename.kind, rename.from),
        do: rename_in_memory(block, rename),
        else: block
    end)
  end

  defp rename_in_memory(block, %{kind: :var, from: from, to: to}) do
    vars = for var <- block.vars, var.key != to, do: if(var.key == from, do: %{var | key: to}, else: var)
    %{block | vars: vars}
  end

  defp rename_in_memory(block, %{kind: :ref, from: from, to: to}) do
    refs = for ref <- block.refs, ref.name != to, do: if(ref.name == from, do: %{ref | name: to}, else: ref)

    case Map.get(block, :children) do
      children when is_list(children) -> %{block | refs: refs, children: rename_slots(children, from, to)}
      _ -> %{block | refs: refs}
    end
  end

  # An empty region under the new name gives way, as the block's own copy
  # of the new ref does
  defp rename_slots(children, from, to) do
    for child <- children, not (slot?(child, to) and child.slot_kind == :region and empty?(child)) do
      if slot?(child, from), do: %{child | slot_name: to}, else: child
    end
  end

  defp slot?(child, name), do: Map.get(child, :type) == :slot and Map.get(child, :slot_name) == name
  defp empty?(child), do: Map.get(child, :children) in [nil, []]

  defp rows(block, :var), do: Map.get(block, :vars)
  defp rows(block, :ref), do: Map.get(block, :refs)

  defp row(block, kind, key) do
    case rows(block, kind) do
      rows when is_list(rows) -> Enum.find(rows, &(name(&1) == key))
      _ -> nil
    end
  end

  defp target(module, kind, key), do: Enum.find(rows(module, kind), &(name(&1) == key))

  defp name(%{key: key}), do: key
  defp name(%{name: name}), do: name

  defp data_type(%{data: %{__struct__: struct}}), do: struct
  defp data_type(_), do: nil
end
