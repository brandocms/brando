defmodule Brando.Content.Definition.Renames do
  @max_entries 120
  @max_blocks 480

  @moduledoc """
  The renames a module's definition file declares (`renamed_from:` on a ref
  or var, read by `Brando.Content.Definition.Model.renames!/1`), and the
  values they move when the definition is applied.

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
  editor's save in the environment waits for it: a module whose renames
  move values in more than #{@max_entries} entries or #{@max_blocks} blocks
  is refused too, and its values are moved with `resolve --map` after an
  apply without the rename. Measured at about two seconds (each entry
  costs a revision before and after and an Activity record, about 12 ms;
  each block a sync, about 0.5 ms).
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.{Block, BlockMoves, Ref, StaleBlocks, Var}
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
  entries: [entry], unrevisioned: count, refused: [reason]}`. Each reason
  names the entries `viewer` may read and counts the others.
  """
  def plan(record, module, renames, viewer) do
    blocks = load(holder_ids(record.id, renames))
    entries = BlockMoves.entries(Enum.map(blocks, & &1.id))
    owners = fn holders -> holders |> Enum.flat_map(&Map.get(entries, &1.id, [])) |> Enum.uniq_by(&{&1.schema, &1.id}) end

    planned =
      Enum.map(renames, fn rename ->
        holders = Enum.filter(blocks, &row(&1, rename.kind, rename.from))
        Map.merge(rename, %{blocks: length(holders), entries: length(owners.(holders)), holders: holders})
      end)

    refused =
      Enum.flat_map(planned, fn rename ->
        definition_refusal(rename, record, module) ||
          block_refusals(rename, module, fn holders -> entry_text(owners.(holders), viewer) end)
      end)

    moved = owners.(blocks)

    %{
      renames: Enum.map(planned, &Map.delete(&1, :holders)),
      blocks: length(blocks),
      entries: moved,
      unrevisioned: Enum.count(moved, &(not &1.revisioned?)),
      refused: refused ++ too_many(planned, length(blocks), length(moved))
    }
  end

  defp too_many(renames, blocks, entries) when blocks > @max_blocks or entries > @max_entries do
    maps = Enum.map_join(renames, " ", &"--map #{&1.kind}:#{&1.from}=#{&1.to}")

    [
      "#{text(renames)} would move values in #{blocks} blocks of #{entries} entries, more than an apply moves " <>
        "while editors' saves wait for it (#{@max_entries} entries, #{@max_blocks} blocks): take renamed_from " <>
        "out of the file, and move the values after the apply with mix brando.modules resolve #{maps}"
    ]
  end

  defp too_many(_renames, _blocks, _entries), do: []

  # The blocks of the module, here, that hold a source key
  defp holder_ids(_module_id, []), do: []

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

  defp definition_refusal(%{kind: :var, from: from, to: to}, record, module) do
    source = Enum.find(record.vars, &(&1.key == from))
    target = Enum.find(module.vars, &(&1.key == to))

    if source && target && source.type != target.type,
      do: [changes_type(:var, from, to, source.type, target.type)]
  end

  defp definition_refusal(%{kind: :ref, from: from, to: to}, record, module) do
    source = Enum.find(record.refs, &(&1.name == from))
    target = Enum.find(module.refs, &(&1.name == to))

    if source && target && StaleBlocks.ref_type(source) != StaleBlocks.ref_type(target),
      do: [changes_type(:ref, from, to, StaleBlocks.ref_type(source), StaleBlocks.ref_type(target))]
  end

  defp changes_type(kind, from, to, old_type, new_type) do
    "#{subject(kind, from, to)} changes type (#{old_type} → #{new_type}): rename it in one release and change " <>
      "the type in the next, or move the values with mix brando.modules resolve --map"
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
      "#{subject(rename.kind, rename.from, rename.to)}: blocks #{ids} #{problem_text(problem, rename)}#{owners.(blocks)}"
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

  defp option?(%Var{value: value}, %Var{type: :select, options: [_ | _] = options}) when value not in [nil, ""],
    do: Enum.any?(options, &(&1.value == value))

  defp option?(_var, _target), do: true

  defp occupied(block, %{kind: kind, to: to}, target) do
    own = row(block, kind, to)
    slots = if kind == :ref, do: Enum.filter(block.slots, &(&1.name == to)), else: []

    if (own != nil and BlockMoves.content?(own, target)) or Enum.any?(slots, &(&1.kind == :footnote or &1.children > 0)),
      do: :occupied
  end

  defp problem_text(:type, rename), do: "hold #{rename.from} as another type than #{rename.to} has"
  defp problem_text(:option, rename), do: "hold a value of #{rename.from} that is not one of #{rename.to}'s options"

  defp problem_text(:occupied, rename),
    do: "already hold a value under #{rename.to}; drop or move it under Resolve blocks first"

  defp subject(kind, from, to), do: ~s(#{kind} "#{to}" renamed from "#{from}")

  # The entries the person may open, named; the others counted
  defp entry_text([], _viewer), do: ""

  defp entry_text(entries, viewer) do
    {readable, hidden} = Enum.split_with(entries, &(Boundary.authorize_record(viewer, :read, &1.schema, &1.id) == :ok))
    named = Enum.map(readable, & &1.label)

    hidden =
      case length(hidden) do
        0 -> []
        1 -> ["1 entry you cannot open"]
        count -> ["#{count} entries you cannot open"]
      end

    " (in " <> Enum.join(named ++ hidden, ", ") <> ")"
  end

  @doc """
  Of the declared renames this update doesn't carry out (`split/2`), those
  whose source key blocks of the module `record` hold: after the apply
  they are leftovers a `resolve --map` would move onto the destination
  `module` defines. Each has `ok?`: whether a dry run of that mapping finds
  them and refuses nothing.
  """
  def remaps(_record, _module, []), do: []

  def remaps(record, module, renames) do
    Enum.flat_map(renames, fn rename ->
      case holder_ids(record.id, [rename]) do
        [] ->
          []

        ids ->
          dry_run = StaleBlocks.plan_for(module, ids, %{{rename.kind, rename.from} => {:map, rename.to}})
          [Map.put(rename, :ok?, dry_run.refused == [] and dry_run.changes != [])]
      end
    end)
  end

  ## Applying

  @doc """
  Moves the values of `moves` (`[%{record: stored, module: saved, renames:
  renames}]`, each module as the apply found it and as it saved it) in the
  apply's transaction, as `person`: the blocks that hold a source key are
  locked and planned again, and anything refused now rolls the apply back.
  One revision of each entry before and one after, however many modules
  move; each entry and module records the renames in Activity with
  `opts[:release]`.
  """
  def move!([], _person, _opts), do: :ok

  def move!(moves, person, opts) do
    planned =
      Enum.map(moves, fn move ->
        ids = holder_ids(move.record.id, move.renames)
        lock!(ids)
        Map.merge(move, %{ids: ids, plan: plan(move.record, move.module, move.renames, person)})
      end)

    case Enum.flat_map(planned, & &1.plan.refused) do
      [] -> :ok
      refused -> Repo.rollback("content changed since you reviewed it: #{Enum.join(refused, "; ")}; review again")
    end

    entries = planned |> Enum.flat_map(& &1.plan.entries) |> Enum.uniq_by(&{&1.schema, &1.id})
    details = details(planned, opts[:release])

    BlockMoves.write!(entries, person, [before: description(planned, opts[:release]), details: details], fn ->
      Enum.each(planned, fn move ->
        Enum.each(move.renames, &rename_rows!(&1, move.ids))
        BlockMoves.sync!(move.module, move.ids)
      end)
    end)

    Enum.each(planned, fn move ->
      Brando.Activity.setting_changed(:updated, move.module, StaleBlocks.module_name(move.module), person,
        details: details
      )
    end)
  end

  # The blocks, and the slots under them, so no child is added to a region
  # while it moves. The importer's table lock already holds the refs and vars.
  defp lock!(ids) do
    Repo.all(
      from(b in Block,
        where: b.id in ^ids or (b.parent_id in ^ids and b.type == :slot),
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
    renames = Enum.map_join(planned, "; ", &"#{text(&1.renames)} in #{StaleBlocks.module_name(&1.module)}")

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
              "blocks" => move.ids
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
      children when is_list(children) ->
        children =
          for child <- children, not (slot?(child, to) and child.slot_kind == :region and empty?(child)) do
            if slot?(child, from), do: %{child | slot_name: to}, else: child
          end

        %{block | refs: refs, children: children}

      _ ->
        %{block | refs: refs}
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
