defmodule Brando.Content.BlockSlotLifecycleTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.{Block, Ref}
  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Content.BlockSlots.Lifecycle
  alias Brando.Factory
  alias Brando.Villain.Blocks.{BlocksBlock, TextBlock}
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset

  defp region_ref(name, set \\ "all"),
    do: %Ref{name: name, uid: Brando.Utils.generate_uid(), data: %BlocksBlock{data: %BlocksBlock.Data{module_set: set}}}

  defp text_ref(html),
    do: %Ref{name: "text", uid: Brando.Utils.generate_uid(), data: %TextBlock{data: %TextBlock.Data{text: html}}}

  defp block(attrs),
    do:
      struct(
        %Block{
          uid: Brando.Utils.generate_uid(),
          type: :module,
          refs: [],
          vars: [],
          children: [],
          table_rows: [],
          block_identifiers: []
        },
        attrs
      )

  defp slot(name, children \\ []),
    do: block(type: :slot, slot_kind: :region, slot_name: name, slot_module_set: "all", children: children)

  setup do
    user = Factory.insert(:random_user)
    attrs = [name: %{"en" => "Lifecycle"}, namespace: %{"en" => "tests"}, help_text: %{"en" => "Tests"}]
    child_module = Factory.insert(:module, attrs)
    module = Factory.insert(:module, attrs ++ [refs: [region_ref("sidebar")]])
    page = Factory.insert(:page, creator: user)

    children =
      for n <- [1, 2],
          do: block(module_id: child_module.id, creator_id: user.id, description: "Child #{n}", sequence: n - 1)

    region = slot("sidebar", children)

    owner =
      block(
        module_id: module.id,
        creator_id: user.id,
        source: Brando.Pages.Page.Blocks,
        refs: [region_ref("sidebar")],
        children: [region]
      )

    entry = Brando.Repo.insert!(%Brando.Pages.Page.Blocks{entry_id: page.id, block: owner, sequence: 0})

    # Exercise the actual module-sync routine: definitions rename the ref,
    # instance refs and the owned subtree must both remain recoverable.
    module = module |> Changeset.change() |> Changeset.put_assoc(:refs, [region_ref("related")]) |> Brando.Repo.update!()
    Brando.Cache.Query.evict(module)
    entry = reload(entry.id)
    entry.block |> ContentBlocks.sync_module(module) |> Brando.Repo.update!()
    entry = reload(entry.id)
    {:ok, user: user, entry: entry, module: module, child_module: child_module}
  end

  defp reload(id) do
    Brando.Repo.get!(Brando.Pages.Page.Blocks, id)
    |> Brando.Repo.preload(
      block: [
        :vars,
        refs: Ref.preloads(),
        table_rows: :vars,
        block_identifiers: :identifier,
        children: &ContentBlocks.preload_child_trees/1
      ]
    )
  end

  defp remap_ops(entry, module) do
    [source] = entry.block.children
    {:ok, destination, params} = Lifecycle.remap(entry.block, module.refs, source.uid, "related")
    ops = Ops.from_entry_blocks([entry])
    {:ok, ops} = Ops.apply_op(ops, {:update, hd(source.children).uid, %{"description" => "Unsaved child edit"}})
    {:ok, ops} = Ops.apply_op(ops, {:remap_slot, source.uid, destination, params})
    ops
  end

  defp materialize(entry, ops, user) do
    {:ok, params} = Ops.materialize_root(ops, entry.block.uid)
    Brando.Pages.Page.Blocks.changeset(entry, params, user.id, true)
  end

  test "module sync retains the renamed region and detection uses current definitions", %{entry: entry, module: module} do
    assert Enum.sort(Enum.map(entry.block.refs, & &1.name)) == ["related", "sidebar"]
    assert [%{slot_name: "sidebar"}] = Lifecycle.unused(entry.block, module.refs)
    assert length(hd(entry.block.children).children) == 2
    assert Lifecycle.unused(entry.block, [region_ref("sidebar")]) == []
    assert [%{slot_name: "sidebar"}] = Lifecycle.unused(entry.block, [%Ref{name: "sidebar", data: %TextBlock{}}])

    fields = %{"blocks" => [Brando.Drafts.Params.snapshot(entry)]}
    assert {recovered, []} = Brando.Drafts.Modules.check(fields, Brando.Drafts.Modules.manifest(fields))
    assert hd(recovered["blocks"])["block"]["children"] == hd(fields["blocks"])["block"]["children"]
  end

  test "remapping survives save and preserves the slot and child IDs with pending edits", context do
    %{entry: entry, module: module, user: user} = context
    [old_slot] = entry.block.children
    cs = materialize(entry, remap_ops(entry, module), user)
    assert cs.valid?, inspect(cs.errors)
    assert {:ok, _} = Brando.Repo.update(cs)
    saved = reload(entry.id)
    assert [new_slot] = saved.block.children
    assert new_slot.id == old_slot.id
    assert new_slot.uid == old_slot.uid
    assert new_slot.slot_name == "related"
    assert Enum.map(new_slot.children, & &1.id) == Enum.map(old_slot.children, & &1.id)
    assert hd(new_slot.children).description == "Unsaved child edit"
    assert Lifecycle.unused(saved.block, module.refs) == []
    assert new_slot.slot_remap == nil
  end

  test "remapping survives remote snapshots, delete undo and draft reconciliation", %{
    entry: entry,
    module: module,
    user: user
  } do
    ops = remap_ops(entry, module)
    [region] = entry.block.children

    {:ok, remote} =
      Ops.apply_remote_snapshot(
        Ops.from_entry_blocks([entry]),
        entry.block.uid,
        Ops.subtree_snapshot(ops, entry.block.uid)
      )

    assert Ops.materialize_root(remote, entry.block.uid) == Ops.materialize_root(ops, entry.block.uid)
    snapshot = Ops.bin_snapshot(remote, region.uid)
    {:ok, deleted} = Ops.apply_op(remote, {:delete, region.uid})
    {:ok, restored} = Ops.restore_snapshot(deleted, snapshot)
    assert Ops.materialize_root(restored, entry.block.uid) == Ops.materialize_root(ops, entry.block.uid)

    fields = %{"blocks" => [materialize(entry, restored, user) |> Brando.Drafts.Params.snapshot()]}
    assert {recovered, []} = Brando.Drafts.Modules.check(fields, Brando.Drafts.Modules.manifest(fields))
    params = Brando.Drafts.Restore.reconcile(hd(recovered["blocks"]), entry)

    restored_cs = Brando.Pages.Page.Blocks.changeset(entry, params, user.id, true)
    assert restored_cs.valid?
    assert {:ok, _} = Brando.Repo.update(restored_cs)
    assert hd(reload(entry.id).block.children).slot_name == "related"
  end

  test "plain hidden metadata and forged remap operations cannot reassign persisted slots", %{
    entry: entry,
    module: module,
    user: user
  } do
    [region] = entry.block.children
    original = Ops.from_entry_blocks([entry])

    {:ok, changed} =
      Ops.apply_op(original, {:update, region.uid, %{"slot_name" => "related", "slot_module_set" => "other"}})

    kept = materialize(entry, changed, user) |> Changeset.get_assoc(:block, :struct) |> Map.fetch!(:children) |> hd()
    assert kept.slot_name == "sidebar"
    assert kept.slot_module_set == "all"

    {:ok, forged} = Ops.apply_op(original, {:update, region.uid, %{"slot_remap" => "forged"}})
    refute materialize(entry, forged, user).valid?
    {:ok, _, signed} = Lifecycle.remap(entry.block, module.refs, region.uid, "related")

    other =
      slot("sidebar")
      |> Map.put(:id, region.id + 1)
      |> Changeset.change(signed |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end))

    assert Lifecycle.remap_claim(other) == :error
  end

  test "populated, incompatible and missing destinations are refused", %{
    entry: entry,
    module: module,
    child_module: child_module
  } do
    [source] = entry.block.children
    populated = slot("related", [block(module_id: child_module.id)])
    owner = %{entry.block | children: [source, populated]}
    assert Lifecycle.remap(owner, module.refs, source.uid, "related") == {:error, :invalid_destination}
    assert Lifecycle.remap(entry.block, module.refs, source.uid, "missing") == {:error, :invalid_destination}

    assert Lifecycle.remap(entry.block, [region_ref("related", "nonexistent-set")], source.uid, "related") ==
             {:error, :invalid_destination}

    assert Lifecycle.remap(entry.block, [region_ref("sidebar"), region_ref("related")], source.uid, "related") ==
             {:error, :invalid_destination}
  end

  test "a remap is rejected if its owner or destination definition changes before save", context do
    %{entry: entry, module: module, user: user} = context
    ops = remap_ops(entry, module)
    {:ok, params} = Ops.materialize_root(ops, entry.block.uid)
    wrong_owner = put_in(params, ["block", "uid"], Brando.Utils.generate_uid())
    refute Brando.Pages.Page.Blocks.changeset(entry, wrong_owner, user.id, true).valid?

    module = module |> Changeset.change() |> Changeset.put_assoc(:refs, []) |> Brando.Repo.update!()
    Brando.Cache.Query.evict(module)
    refute materialize(entry, ops, user).valid?
  end

  test "an unsaved region can be remapped, saved and duplicated without reusing its authorization", context do
    %{entry: entry, module: module, user: user} = context

    owner =
      entry.block |> Changeset.change() |> ContentBlocks.duplicate_block(user_id: user.id) |> Changeset.apply_changes()

    entry = %Brando.Pages.Page.Blocks{entry_id: entry.entry_id, block: owner, sequence: 1}
    [region] = owner.children
    {:ok, _, params} = Lifecycle.remap(owner, module.refs, region.uid, "related")
    {:ok, ops} = Ops.apply_op(Ops.new([]), {:insert, owner.uid, 0, Ops.snapshot_params(Changeset.change(entry))})
    {:ok, ops} = Ops.apply_op(ops, {:remap_slot, region.uid, nil, params})
    {:ok, params} = Ops.materialize_root(ops, owner.uid)
    cs = Brando.Pages.Page.Blocks.changeset(%Brando.Pages.Page.Blocks{}, params, user.id, true)
    assert cs.valid?, inspect(Changeset.traverse_errors(cs, fn {message, _} -> message end))

    copy =
      cs |> Changeset.get_assoc(:block) |> ContentBlocks.duplicate_block(user_id: user.id) |> Changeset.apply_changes()

    assert [%{slot_name: "related", slot_remap: nil}] = copy.children
    assert {:ok, saved} = Brando.Repo.insert(cs)
    assert hd(reload(saved.id).block.children).slot_name == "related"
  end

  test "a remapped region can be explicitly deleted before saving", context do
    %{entry: entry, module: module, user: user} = context
    [region] = entry.block.children
    {:ok, ops} = Ops.apply_op(remap_ops(entry, module), {:delete, region.uid})
    cs = materialize(entry, ops, user)
    assert cs.valid?
    assert {:ok, _} = Brando.Repo.update(cs)
    assert reload(entry.id).block.children == []
  end

  test "an already instantiated empty destination is replaced atomically", %{entry: entry, module: module, user: user} do
    [source] = entry.block.children
    empty = slot("related") |> Map.put(:parent_id, entry.block.id) |> Brando.Repo.insert!()
    entry = reload(entry.id)
    {:ok, destination, params} = Lifecycle.remap(entry.block, module.refs, source.uid, "related")
    assert destination == empty.uid
    {:ok, ops} = Ops.apply_op(Ops.from_entry_blocks([entry]), {:remap_slot, source.uid, destination, params})
    cs = materialize(entry, ops, user)
    assert cs.valid?
    assert {:ok, _} = Brando.Repo.update(cs)
    assert [%{id: id, slot_name: "related"}] = reload(entry.id).block.children
    assert id == source.id
    refute Brando.Repo.get(Block, empty.id)
  end

  test "footnotes become unused only when their last owner-local marker is gone" do
    note = %{slot("text") | slot_kind: :footnote, uid: "note"}
    marker = ~s(<sup data-footnote-uid="note">•</sup>)
    definitions = [text_ref("")]

    for html <- [marker, marker <> marker] do
      assert Lifecycle.unused(block(refs: [text_ref(html)], children: [note]), definitions) == []
      assert Lifecycle.unused_notes([note], :text, html) == []
    end

    assert [^note] = Lifecycle.unused(block(refs: [text_ref("<p>No reference</p>")], children: [note]), definitions)
    assert [^note] = Lifecycle.unused_notes([note], :text, "")
    assert Lifecycle.unused_notes([note], :other, "") == []
    assert [^note] = Lifecycle.unused(block(refs: [text_ref(marker)], children: [note]), [])
  end

  test "region recovery does not bypass review of removed or retyped content refs", %{entry: entry} do
    params = Brando.Drafts.Params.snapshot(entry)

    for ref <- [text_ref("Retained prose"), %{text_ref("Former text") | name: "related"}] do
      fields =
        put_in(%{"blocks" => [params]}, ["blocks", Access.at(0), "block", "refs"], [Brando.Drafts.Params.snapshot(ref)])

      assert {%{"blocks" => []}, [_]} = Brando.Drafts.Modules.check(fields, Brando.Drafts.Modules.manifest(fields))
    end
  end
end
