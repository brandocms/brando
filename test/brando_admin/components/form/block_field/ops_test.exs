defmodule BrandoAdmin.Components.Form.BlockField.OpsTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset

  doctest Ops

  defp apply!(state, op) do
    assert {:ok, state} = Ops.apply_op(state, op)
    state
  end

  describe "new/1" do
    test "builds persisted state from uid order" do
      state = Ops.new(["a", "b", "c"])

      assert state.order == ["a", "b", "c"]
      assert state.statuses == %{"a" => :persisted, "b" => :persisted, "c" => :persisted}
      assert state.diffs == %{}
      assert state.deleted == []
    end
  end

  describe "insert" do
    test "inserts at position with params and :inserted status" do
      state = apply!(Ops.new(["a", "b"]), {:insert, "x", 1, %{"block" => %{"uid" => "x"}}})

      assert state.order == ["a", "x", "b"]
      assert state.statuses["x"] == :inserted
      assert state.diffs["x"] == %{"block" => %{"uid" => "x"}}
    end

    test ":end and beyond-length positions append" do
      state = apply!(Ops.new(["a"]), {:insert, "x", :end, %{}})
      assert state.order == ["a", "x"]

      state = apply!(Ops.new(["a"]), {:insert, "y", 99, %{}})
      assert state.order == ["a", "y"]
    end

    test "duplicate uid is rejected" do
      assert {:error, {:duplicate_uid, "a"}} = Ops.apply_op(Ops.new(["a"]), {:insert, "a", 0, %{}})
    end

    test "negative position is rejected" do
      assert {:error, {:bad_position, -1}} = Ops.apply_op(Ops.new([]), {:insert, "a", -1, %{}})
    end
  end

  describe "update" do
    # Roots rebase on `changeset.data`, so each diff is already cumulative vs.
    # the DB — replacing is correct. Merging them would resurrect a value the
    # user had edited and then reverted.
    test "replaces a ROOT diff wholesale" do
      state =
        Ops.new(["a"])
        |> apply!({:update, "a", %{"block" => %{"refs" => [%{"name" => "p"}]}}})
        |> apply!({:update, "a", %{"block" => %{"uid" => "a"}}})

      assert state.diffs["a"] == %{"block" => %{"uid" => "a"}}
    end

    # Children rebase on `apply_changes/1`, so each diff is only the delta since
    # the last validate — they must accumulate or earlier edits are lost (B2).
    test "merges a CHILD diff onto the stored one" do
      state =
        Ops.new(["p"])
        |> apply!({:insert_child, "p", "c", 0, %{"uid" => "c"}})
        |> apply!({:update, "c", %{"description" => "abc"}})
        |> apply!({:update, "c", %{"anchor" => "z"}})

      assert state.diffs["c"] == %{"uid" => "c", "description" => "abc", "anchor" => "z"}
    end

    test "a later CHILD edit still overwrites the same key" do
      state =
        Ops.new(["p"])
        |> apply!({:insert_child, "p", "c", 0, %{"uid" => "c"}})
        |> apply!({:update, "c", %{"description" => "abc"}})
        |> apply!({:update, "c", %{"description" => "xyz"}})

      assert state.diffs["c"]["description"] == "xyz"
    end

    # `changes_to_params/1` emits nested relations as LISTS, not index-keyed maps.
    # An earlier version of this test hand-wrote `%{"refs" => %{"0" => ...}}` — a
    # shape the real code never produces — and so passed against a merge that
    # actually replaced ref lists wholesale. Use the real emitter.
    test "CHILD merge is deep — a diff touching one ref keeps the other" do
      round1 = %{"refs" => [%{"id" => "11", "image_id" => 1}, %{"id" => "22"}]}
      round2 = %{"refs" => [%{"id" => "11"}, %{"id" => "22", "image_id" => 2}]}

      state =
        Ops.new(["p"])
        |> apply!({:insert_child, "p", "c", 0, %{"uid" => "c"}})
        |> apply!({:update, "c", round1})
        |> apply!({:update, "c", round2})

      assert [%{"id" => "11", "image_id" => 1}, %{"id" => "22", "image_id" => 2}] =
               state.diffs["c"]["refs"]
    end

    test "CHILD merge correlates unsaved relation rows by uid" do
      state =
        Ops.new(["p"])
        |> apply!({:insert_child, "p", "c", 0, %{"uid" => "c"}})
        |> apply!({:update, "c", %{"vars" => [%{"uid" => "v1", "value" => "a"}]}})
        |> apply!({:update, "c", %{"vars" => [%{"uid" => "v1", "label" => "L"}]}})

      assert [%{"uid" => "v1", "value" => "a", "label" => "L"}] = state.diffs["c"]["vars"]
    end

    # The NEW list defines membership. `change_value/1` drops :replace/:delete
    # changesets, so a row missing from the newer diff was DELETED — carrying it
    # over from the stored diff would resurrect it, which is this bug's mirror.
    test "CHILD merge does not resurrect a relation row the newer diff dropped" do
      state =
        Ops.new(["p"])
        |> apply!({:insert_child, "p", "c", 0, %{"uid" => "c"}})
        |> apply!({:update, "c", %{"refs" => [%{"id" => "11", "image_id" => 1}, %{"id" => "22"}]}})
        |> apply!({:update, "c", %{"refs" => [%{"id" => "22", "image_id" => 2}]}})

      refs = state.diffs["c"]["refs"]
      assert [%{"id" => "22", "image_id" => 2}] = refs
      refute Enum.any?(refs, &(&1["id"] == "11"))
    end

    test "CHILD merge takes identity-less rows from the newer list as-is" do
      state =
        Ops.new(["p"])
        |> apply!({:insert_child, "p", "c", 0, %{"uid" => "c"}})
        |> apply!({:update, "c", %{"table_rows" => [%{"a" => 1}]}})
        |> apply!({:update, "c", %{"table_rows" => [%{"b" => 2}]}})

      assert state.diffs["c"]["table_rows"] == [%{"b" => 2}]
    end

    test "does not change status" do
      state = apply!(Ops.new(["a"]), {:update, "a", %{}})
      assert state.statuses["a"] == :persisted
    end

    test "unknown uid is rejected" do
      assert {:error, {:unknown_uid, "nope"}} = Ops.apply_op(Ops.new(["a"]), {:update, "nope", %{}})
    end
  end

  describe "move" do
    test "moves a uid to a new position" do
      state = apply!(Ops.new(["a", "b", "c"]), {:move, "c", 0})
      assert state.order == ["c", "a", "b"]
    end

    test "beyond-length target appends" do
      state = apply!(Ops.new(["a", "b"]), {:move, "a", 99})
      assert state.order == ["b", "a"]
    end

    test "unknown uid and bad position are rejected" do
      assert {:error, {:unknown_uid, "x"}} = Ops.apply_op(Ops.new(["a"]), {:move, "x", 0})
      assert {:error, {:bad_position, -2}} = Ops.apply_op(Ops.new(["a"]), {:move, "a", -2})
    end
  end

  describe "reorder" do
    test "applies a full new order" do
      state = apply!(Ops.new(["a", "b", "c"]), {:reorder, ["c", "a", "b"]})
      assert state.order == ["c", "a", "b"]
    end

    test "never loses blocks: forgotten uids keep relative order at the end" do
      state = apply!(Ops.new(["a", "b", "c", "d"]), {:reorder, ["d", "b"]})
      assert state.order == ["d", "b", "a", "c"]
    end

    test "unknown and duplicate uids in the new order are dropped" do
      state = apply!(Ops.new(["a", "b"]), {:reorder, ["b", "ghost", "b", "a"]})
      assert state.order == ["b", "a"]
    end
  end

  describe "delete" do
    test "persisted block is tracked in deleted" do
      state = apply!(Ops.new(["a", "b"]), {:delete, "a"})

      assert state.order == ["b"]
      assert state.deleted == ["a"]
      refute Map.has_key?(state.statuses, "a")
    end

    test "inserted block vanishes without a deletion record" do
      state =
        Ops.new([])
        |> apply!({:insert, "x", 0, %{"block" => %{}}})
        |> apply!({:delete, "x"})

      assert state.order == []
      assert state.deleted == []
      assert state.diffs == %{}
    end

    test "unknown uid is rejected" do
      assert {:error, {:unknown_uid, "x"}} = Ops.apply_op(Ops.new([]), {:delete, "x"})
    end
  end

  describe "tree: from_entry_blocks/1" do
    defp entry_block(uid, entry_block_id, block_id, children \\ []) do
      %{id: entry_block_id, block: %{uid: uid, id: block_id, children: children}}
    end

    defp child(uid, block_id, children \\ []), do: %{uid: uid, id: block_id, children: children}

    test "registers roots, nesting, statuses and db ids" do
      state =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11), child("a2", 12, [child("a2x", 13)])]),
          entry_block("b", 2, 20)
        ])

      assert state.order == ["a", "b"]
      assert state.parents == %{"a1" => "a", "a2" => "a", "a2x" => "a2"}
      assert state.child_order == %{"a" => ["a1", "a2"], "a2" => ["a2x"]}
      assert state.statuses["a2x"] == :persisted
      assert state.db_ids["a"] == {1, 10}
      assert state.db_ids["a1"] == {nil, 11}
    end

    test "tolerates not-loaded children" do
      state = Ops.from_entry_blocks([%{id: 1, block: %{uid: "a", id: 10, children: %Ecto.Association.NotLoaded{}}}])
      assert state.order == ["a"]
      assert state.child_order == %{}
    end
  end

  describe "tree: child ops" do
    defp tree_state do
      Ops.from_entry_blocks([
        entry_block("a", 1, 10, [child("a1", 11), child("a2", 12)]),
        entry_block("b", 2, 20)
      ])
    end

    test "insert_child attaches under parent with :inserted status" do
      state = apply!(tree_state(), {:insert_child, "a", "x", 1, %{"uid" => "x"}})

      assert state.child_order["a"] == ["a1", "x", "a2"]
      assert state.parents["x"] == "a"
      assert state.statuses["x"] == :inserted
      assert state.diffs["x"]["uid"] == "x"
    end

    test "insert_child with a known uid reparents (cross-parent move) and refreshes the diff" do
      state = apply!(tree_state(), {:insert_child, "b", "a1", 0, %{"uid" => "a1", "type" => "module"}})

      assert state.child_order["a"] == ["a2"]
      assert state.child_order["b"] == ["a1"]
      assert state.parents["a1"] == "b"
      assert state.statuses["a1"] == :persisted
      assert state.diffs["a1"]["type"] == "module"
    end

    test "insert_child under unknown parent is rejected" do
      assert {:error, {:unknown_uid, "ghost"}} = Ops.apply_op(tree_state(), {:insert_child, "ghost", "x", 0, %{}})
    end

    test "reorder_children sanitizes against the parent's children" do
      state = apply!(tree_state(), {:reorder_children, "a", ["a2", "ghost", "a1"]})
      assert state.child_order["a"] == ["a2", "a1"]
    end

    test "move_to_parent refuses cycles" do
      state = apply!(tree_state(), {:insert_child, "a1", "deep", 0, %{}})
      assert {:error, {:cyclic_move, "a"}} = Ops.apply_op(state, {:move_to_parent, "a", "deep", 0})
    end

    test "update accepts child uids" do
      state = apply!(tree_state(), {:update, "a1", %{"type" => "module"}})
      assert state.diffs["a1"] == %{"type" => "module"}
    end

    test "deleting a parent cascades to descendants" do
      state =
        tree_state()
        |> apply!({:insert_child, "a2", "a2x", 0, %{}})
        |> apply!({:delete, "a"})

      assert state.order == ["b"]
      assert state.parents == %{}
      assert state.child_order == %{}
      # a2x was :inserted — only persisted blocks are tracked for deletion
      assert Enum.sort(state.deleted) == ["a", "a1", "a2"]
      refute Map.has_key?(state.statuses, "a2x")
    end

    test "insert params carrying a children subtree register per-uid diffs" do
      params = %{
        "entry_id" => 1,
        "block" => %{
          "uid" => "dup",
          "children" => [
            %{"uid" => "dup1", "type" => "module"},
            %{"uid" => "dup2", "children" => [%{"uid" => "dup2x"}]}
          ]
        }
      }

      state = apply!(Ops.new([]), {:insert, "dup", 0, params})

      assert state.order == ["dup"]
      assert state.child_order == %{"dup" => ["dup1", "dup2"], "dup2" => ["dup2x"]}
      assert state.statuses["dup2x"] == :inserted
      assert state.diffs["dup1"] == %{"uid" => "dup1", "type" => "module"}
      # the stored root diff no longer carries the children subtree
      refute Map.has_key?(state.diffs["dup"]["block"], "children")
    end
  end

  describe "session helpers" do
    defp sync_state do
      Ops.from_entry_blocks([
        entry_block("a", 1, 10, [child("a1", 11), child("a2", 12, [child("a2x", 13)])]),
        entry_block("b", 2, 20)
      ])
    end

    test "root_of/2 walks to the root" do
      state = sync_state()
      assert Ops.root_of(state, "a2x") == "a"
      assert Ops.root_of(state, "b") == "b"
    end

    test "{:restore, snapshot} undoes a delete like restore_snapshot/2" do
      state = sync_state()
      snapshot = Ops.bin_snapshot(state, "a2")
      deleted = apply!(state, {:delete, "a2"})

      assert apply!(deleted, {:restore, snapshot}) == state
    end

    test "{:replace_state, state} replaces everything" do
      replacement = apply!(Ops.new(["x"]), {:update, "x", %{"block" => %{"description" => "d"}}})
      assert apply!(sync_state(), {:replace_state, replacement}) == replacement
    end

    test "signature/1 compares rows, not edits" do
      edited = apply!(sync_state(), {:update, "a1", %{"description" => "edited"}})
      assert Ops.signature(edited) == Ops.signature(sync_state())

      other_rows = Ops.from_entry_blocks([entry_block("a", 1, 10), entry_block("b", 2, 20)])
      refute Ops.signature(other_rows) == Ops.signature(sync_state())
    end

    test "pristine?/2 is false once anything changed" do
      base = sync_state()
      assert Ops.pristine?(base, base)
      refute Ops.pristine?(apply!(base, {:update, "b", %{"block" => %{"anchor" => "x"}}}), base)
      refute Ops.pristine?(apply!(base, {:reorder, ["b", "a"]}), base)
      refute Ops.pristine?(apply!(base, {:delete, "a1"}), base)
      refute Ops.pristine?(apply!(base, {:insert, "n", :end, %{}}), base)
      # an empty diff is no change
      assert Ops.pristine?(apply!(base, {:update, "a1", %{}}), base)
    end

    test "changed_roots/3 names the roots whose subtree changed" do
      before = sync_state()
      after_state = apply!(before, {:update, "a2x", %{"description" => "deep"}})

      assert Ops.changed_roots(before, after_state) == ["a"]
      assert Ops.changed_roots(before, after_state, ["a2x"]) == ["a"]
      assert Ops.changed_roots(before, after_state, ["b"]) == []

      # appearing and disappearing roots are the caller's to handle
      inserted = apply!(before, {:insert, "n", 0, %{}})
      assert Ops.changed_roots(before, inserted) == []

      child_deleted = apply!(before, {:delete, "a1"})
      assert Ops.changed_roots(before, child_deleted) == ["a"]
    end
  end

  describe "carry/3 (writes from outside the session)" do
    defp base_rows do
      Ops.from_entry_blocks([
        entry_block("a", 1, 10, [child("a1", 11), child("a2", 12)]),
        entry_block("b", 2, 20),
        entry_block("c", 3, 30)
      ])
    end

    test "unsaved field changes, inserts and deletes are carried onto the new rows" do
      old_base = base_rows()

      state =
        old_base
        |> apply!({:update, "b", %{"block" => %{"description" => "editor"}}})
        |> apply!({:update, "a1", %{"description" => "child edit"}})
        |> apply!({:insert, "n", 1, %{"block" => %{"uid" => "n", "type" => "module"}}})
        |> apply!({:insert_child, "a", "nc", 0, %{"uid" => "nc"}})
        |> apply!({:delete, "c"})

      # The assistant appended a block "z" after "c" and gave "b" a new row id.
      new_base =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11), child("a2", 12)]),
          entry_block("b", 4, 21),
          entry_block("c", 3, 30),
          entry_block("z", 5, 50)
        ])

      assert {carried, []} = Ops.carry(state, old_base, new_base)

      assert carried.order == ["a", "n", "b", "z"]
      assert carried.child_order["a"] == ["nc", "a1", "a2"]
      assert carried.diffs["b"] == %{"block" => %{"description" => "editor"}}
      assert carried.diffs["a1"] == %{"description" => "child edit"}
      assert carried.statuses["n"] == :inserted
      assert carried.statuses["nc"] == :inserted
      assert carried.db_ids["b"] == {4, 21}
      assert "c" in carried.deleted
      refute Ops.known?(carried, "c")
    end

    test "the other writer's order wins unless the editors moved blocks" do
      old_base = base_rows()
      new_base = Ops.from_entry_blocks([entry_block("c", 3, 30), entry_block("a", 1, 10), entry_block("b", 2, 20)])

      {kept, []} = Ops.carry(old_base, old_base, new_base)
      assert kept.order == ["c", "a", "b"]

      moved = apply!(old_base, {:move, "a", 2})
      {carried, []} = Ops.carry(moved, old_base, new_base)
      assert carried.order == ["b", "c", "a"]
    end

    test "work on a block the other writer deleted is reported, not replayed" do
      old_base = base_rows()
      state = apply!(old_base, {:update, "c", %{"block" => %{"description" => "lost?"}}})

      new_base =
        Ops.from_entry_blocks([entry_block("a", 1, 10, [child("a1", 11), child("a2", 12)]), entry_block("b", 2, 20)])

      assert {carried, ["c"]} = Ops.carry(state, old_base, new_base)
      assert carried.order == ["a", "b"]
    end

    # `{:carry, state, base}` (a rejoin, a recovery copy) lands on live
    # session state, where a root can hold another editor's changes: an
    # `:update` replaced the root's whole diff, so those changes went without
    # a conflict.
    test "state carried onto live state keeps others' changes to its roots' other fields" do
      base = base_rows()

      live =
        base
        |> apply!({:set_field, "b", ["block", "description"], "other editor", 0})
        |> apply!({:set_field, "b", ["block", "anchor"], "other editor", 0})
        |> apply!({:update, "a1", %{"description" => "other editor"}})

      held =
        base
        |> apply!({:update, "b", %{"block" => %{"anchor" => "carried"}}})
        |> apply!({:update, "a1", %{"anchor" => "carried"}})

      carried = apply!(live, {:carry, held, base})

      assert carried.diffs["b"] == %{"block" => %{"description" => "other editor", "anchor" => "carried"}}
      assert carried.diffs["a1"] == %{"description" => "other editor", "anchor" => "carried"}
    end

    # A rejoin (`carry/4` with `lists: :merge`) merges the lists of a root
    # both sides changed by row.
    defp rejoin(live, held, base) do
      {state, _conflicts} = Ops.carry(held, base, live, lists: :merge)
      state
    end

    test "a rejoin merges rows: each side's additions, removals and row changes stay" do
      base = base_rows()
      rows_then = [%{"id" => 5}, %{"id" => 7}, %{"id" => 9}]

      # The session: a cell of row 5 changed, row 9 removed.
      live =
        base
        |> apply!({:set_field, "b", ["block", {:at, "table_rows", {"id", 5}, rows_then}, "cols"], "live", 0})
        |> apply!({:set_field, "b", ["block", "table_rows"], {:list, rows_then, [%{"id" => 5}, %{"id" => 7}]}, 0})

      # Carried: another cell of row 5 changed, row 7 removed, a row added.
      added = %{"sync_uid" => "new", "cols" => "carried row"}

      held =
        apply!(
          base,
          {:update, "b", %{"block" => %{"table_rows" => [%{"id" => 5, "label" => "carried"}, %{"id" => 9}, added]}}}
        )

      assert rejoin(live, held, base).diffs["b"]["block"]["table_rows"] == [
               %{"id" => 5, "cols" => "live", "label" => "carried"},
               added
             ]
    end

    # Review: a list op left every row as a full copy, so a saved row the
    # rejoiner removed looked changed in the session and came back.
    test "a rejoin's removal of a saved row holds against rows a list op left as they were" do
      base = base_rows()
      rows_then = [%{"id" => 5, "cols" => "saved 5"}, %{"id" => 7, "cols" => "saved 7"}]
      added = %{"sync_uid" => "new", "cols" => "A's row"}
      live = apply!(base, {:set_field, "b", ["block", "table_rows"], {:list, rows_then, rows_then ++ [added]}, 0})
      assert live.diffs["b"]["block"]["table_rows"] == [%{"id" => 5}, %{"id" => 7}, added]

      held = apply!(base, {:update, "b", %{"block" => %{"table_rows" => [%{"id" => 5}]}}})
      assert rejoin(live, held, base).diffs["b"]["block"]["table_rows"] == [%{"id" => 5}, added]
    end

    test "a rejoin merges lists inside a row by row when their rows have ids" do
      base = base_rows()
      vars = [%{"id" => 51}, %{"id" => 52}]
      at_vars = ["block", {:at, "table_rows", {"id", 5}, [%{"id" => 5}]}, "vars"]

      live = apply!(base, {:set_field, "b", at_vars, {:list, vars, [%{"id" => 51}]}, 0})

      held =
        apply!(
          base,
          {:update, "b",
           %{"block" => %{"table_rows" => [%{"id" => 5, "vars" => [%{"id" => 51, "value" => "B"}, %{"id" => 52}]}]}}}
        )

      assert [%{"id" => 5, "vars" => [%{"id" => 51, "value" => "B"}]}] =
               rejoin(live, held, base).diffs["b"]["block"]["table_rows"]
    end

    # Review: below a row, an item can be named by id on one side and by
    # what it holds on the other (a new gallery object by its image), and
    # only top-level rows have ids to name them by: such a list is the
    # carried side's, never both.
    test "a rejoin takes a list inside a row whole when an item has no id" do
      base = base_rows()
      at_objects = ["block", {:at, "refs", {"id", 3}, [%{"id" => 3}]}, "gallery_objects"]
      live = apply!(base, {:set_field, "b", at_objects, {:list, [], [%{"id" => 44, "image_id" => 9}]}, 0})

      held =
        apply!(
          base,
          {:update, "b",
           %{"block" => %{"refs" => [%{"id" => 3, "gallery_objects" => [%{"image_id" => 9, "alt" => "B"}]}]}}}
        )

      assert [%{"id" => 3, "gallery_objects" => [%{"image_id" => 9, "alt" => "B"}]}] =
               rejoin(live, held, base).diffs["b"]["block"]["refs"]
    end

    test "a row the session changed stays when the rejoiner's list leaves it out" do
      base = base_rows()
      live = apply!(base, {:update, "b", %{"block" => %{"table_rows" => [%{"id" => 5, "cols" => "unsaved work"}]}}})
      held = apply!(base, {:update, "b", %{"block" => %{"table_rows" => []}}})

      assert rejoin(live, held, base).diffs["b"]["block"]["table_rows"] == [%{"id" => 5, "cols" => "unsaved work"}]
    end

    # The rejoiner names a row by its sync uid (new when it was made), the
    # session by the id a save gave it since: one row.
    test "a row named by uid on one side and by id on the other is one row" do
      old_base = base_rows()

      saved =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11), child("a2", 12)]),
          %{id: 2, block: %{uid: "b", id: 20, children: [], table_rows: [%{id: 8, sync_uid: "new"}]}},
          entry_block("c", 3, 30)
        ])

      live =
        apply!(saved, {:update, "b", %{"block" => %{"table_rows" => [%{"id" => 8, "sync_uid" => "new", "cols" => "A"}]}}})

      held = apply!(old_base, {:update, "b", %{"block" => %{"table_rows" => [%{"sync_uid" => "new", "cols" => "B"}]}}})

      assert [%{"id" => 8, "cols" => "B"}] = rejoin(live, held, old_base).diffs["b"]["block"]["table_rows"]
    end

    # Review: a recovery copy is cast again, which gives its new table rows
    # fresh sync uids; merged by row, the session's new row and the copy's
    # were two rows.
    test "a recovery copy's lists are the copy's" do
      base = base_rows()

      live =
        apply!(
          base,
          {:update, "b", %{"block" => %{"table_rows" => [%{"id" => 5}, %{"sync_uid" => "s9", "cols" => "x"}]}}}
        )

      copy_rows = [%{"id" => 5}, %{"sync_uid" => "s9-recast", "cols" => "x"}]
      copy = apply!(base, {:update, "b", %{"block" => %{"table_rows" => copy_rows}}})

      assert apply!(live, {:carry, copy, base}).diffs["b"]["block"]["table_rows"] == copy_rows
    end

    # Sol audit: two items named alike in the list as it is made the
    # rewritten merge anchor one on itself, forever.
    test "merge_list keeps items named alike in the list as it is, in order" do
      x1 = %{"value" => "x", "label" => "1"}
      x2 = %{"value" => "x", "label" => "2"}
      y = %{"value" => "y"}
      task = Task.async(fn -> Ops.merge_list([], [y], [x1, x2], "options") end)
      assert Task.await(task, 1_000) == [x1, x2, y]
    end

    test "a rejoin merges a 200-row table quickly" do
      base = base_rows()
      rows = for id <- 1..200, do: %{"id" => id, "cols" => "saved #{id}"}

      live_rows =
        Enum.map(rows, fn %{"id" => id} = row -> if rem(id, 2) == 0, do: %{row | "cols" => "A"}, else: %{"id" => id} end)

      held_rows =
        Enum.map(rows, fn %{"id" => id} = row -> if rem(id, 3) == 0, do: %{row | "cols" => "B"}, else: %{"id" => id} end)

      live = apply!(base, {:update, "b", %{"block" => %{"table_rows" => live_rows ++ [%{"sync_uid" => "a"}]}}})
      held = apply!(base, {:update, "b", %{"block" => %{"table_rows" => held_rows ++ [%{"sync_uid" => "b"}]}}})

      {micros, state} = :timer.tc(fn -> rejoin(live, held, base) end)
      merged = state.diffs["b"]["block"]["table_rows"]
      assert length(merged) == 202
      assert Enum.at(merged, 5) == %{"id" => 6, "cols" => "B"}
      assert Enum.at(merged, 3) == %{"id" => 4, "cols" => "A"}
      IO.puts("200-row rejoin merge: #{micros} µs")
      assert micros < 100_000
    end

    test "rows written outside the session take the editors' root diffs as they are" do
      old_base = base_rows()
      state = apply!(old_base, {:update, "b", %{"block" => %{"anchor" => "editor"}}})
      {carried, []} = Ops.carry(state, old_base, base_rows())
      assert carried.diffs["b"] == %{"block" => %{"anchor" => "editor"}}
    end
  end

  describe "restorable bin snapshots" do
    defp bin_state do
      Ops.from_entry_blocks([
        entry_block("a", 1, 10, [child("a1", 11), child("a2", 12, [child("a2x", 13)])]),
        entry_block("b", 2, 20)
      ])
    end

    test "bin_snapshot/2 records location, statuses and db ids for the subtree" do
      snapshot = Ops.bin_snapshot(bin_state(), "a2")

      assert snapshot.location == {:child, "a", 1}
      assert snapshot.uids == ["a2", "a2x"]
      assert snapshot.statuses == %{"a2" => :persisted, "a2x" => :persisted}
      assert snapshot.db_ids == %{"a2" => {nil, 12}, "a2x" => {nil, 13}}
    end

    test "root delete → restore round-trips the entire state" do
      state = apply!(bin_state(), {:update, "a1", %{"type" => "module"}})
      snapshot = Ops.bin_snapshot(state, "a")

      deleted_state = apply!(state, {:delete, "a"})
      assert Enum.sort(deleted_state.deleted) == ["a", "a1", "a2", "a2x"]

      assert {:ok, restored} = Ops.restore_snapshot(deleted_state, snapshot)
      assert restored == state
    end

    test "restored roots materialize identically to before the delete" do
      state = apply!(bin_state(), {:update, "a", %{"block" => %{"description" => "Edited"}}})
      assert {:ok, before_params} = Ops.materialize_root(state, "a")

      snapshot = Ops.bin_snapshot(state, "a")

      {:ok, restored} =
        state
        |> apply!({:delete, "a"})
        |> Ops.restore_snapshot(snapshot)

      assert {:ok, after_params} = Ops.materialize_root(restored, "a")
      assert after_params == before_params
    end

    test "child delete → restore reattaches under the parent at position" do
      state = bin_state()
      snapshot = Ops.bin_snapshot(state, "a1")

      {:ok, restored} =
        state
        |> apply!({:delete, "a1"})
        |> Ops.restore_snapshot(snapshot)

      assert restored == state
    end

    test "restore positions clamp when the tree shrank in the meantime" do
      state = Ops.new(["a", "b", "c"])
      snapshot = Ops.bin_snapshot(state, "c")

      {:ok, restored} =
        state
        |> apply!({:delete, "c"})
        |> apply!({:delete, "a"})
        |> Ops.restore_snapshot(snapshot)

      assert restored.order == ["b", "c"]
    end

    test "restoring an already-known uid is rejected" do
      state = bin_state()
      snapshot = Ops.bin_snapshot(state, "b")
      assert {:error, {:duplicate_uid, "b"}} = Ops.restore_snapshot(state, snapshot)
    end

    test "restoring a child whose parent is gone is rejected" do
      state = bin_state()
      snapshot = Ops.bin_snapshot(state, "a1")

      deleted_state =
        state
        |> apply!({:delete, "a1"})
        |> apply!({:delete, "a"})

      assert {:error, {:unknown_parent, "a"}} = Ops.restore_snapshot(deleted_state, snapshot)
    end

    test "newest-first restore brings back a child deleted before its parent" do
      state = bin_state()
      child_snapshot = Ops.bin_snapshot(state, "a1")
      state = apply!(state, {:delete, "a1"})
      parent_snapshot = Ops.bin_snapshot(state, "a")
      state = apply!(state, {:delete, "a"})

      {:ok, state} = Ops.restore_snapshot(state, parent_snapshot)
      assert {:ok, restored} = Ops.restore_snapshot(state, child_snapshot)

      assert restored == bin_state()
    end

    test "restoring an inserted (never persisted) block keeps :inserted status without ids" do
      state = apply!(Ops.new([]), {:insert, "x", 0, %{"block" => %{"uid" => "x"}}})
      snapshot = Ops.bin_snapshot(state, "x")

      {:ok, restored} =
        state
        |> apply!({:delete, "x"})
        |> Ops.restore_snapshot(snapshot)

      assert restored.statuses["x"] == :inserted
      assert restored.deleted == []
      assert restored.diffs["x"] == %{"block" => %{"uid" => "x"}}
    end
  end

  describe "materialize_root/2" do
    test "unknown root is rejected" do
      assert {:error, {:unknown_uid, "x"}} = Ops.materialize_root(Ops.new([]), "x")
    end

    test "untouched persisted blocks materialize as id+sequence-only params" do
      state = Ops.from_entry_blocks([entry_block("a", 1, 10), entry_block("b", 2, 20)])

      assert {:ok, params} = Ops.materialize_root(state, "b")

      # "children" is ALWAYS present — dropping it when empty silently kept
      # rows alive (last-child deletes / cross-parent moves never persisted)
      assert params == %{
               "id" => 2,
               "sequence" => 1,
               "block" => %{"id" => 20, "uid" => "b", "sequence" => 1, "children" => []}
             }
    end

    test "diffs merge with tree-derived children, sequence and db ids" do
      state =
        [entry_block("a", 1, 10, [child("a1", 11), child("a2", 12)])]
        |> Ops.from_entry_blocks()
        |> apply!({:update, "a", %{"block" => %{"description" => "Edited"}}})
        |> apply!({:update, "a1", %{"type" => "module"}})
        |> apply!({:reorder_children, "a", ["a2", "a1"]})

      assert {:ok, params} = Ops.materialize_root(state, "a")

      assert params["id"] == 1
      assert params["sequence"] == 0
      assert params["block"]["id"] == 10
      assert params["block"]["description"] == "Edited"

      assert [a2, a1] = params["block"]["children"]
      assert %{"uid" => "a2", "id" => 12, "sequence" => 0} = a2
      assert %{"uid" => "a1", "id" => 11, "sequence" => 1, "type" => "module"} = a1
    end

    test "render artifacts and stale sequence/children keys in diffs are discarded" do
      state =
        [entry_block("a", 1, 10, [child("a1", 11)])]
        |> Ops.from_entry_blocks()
        |> apply!(
          {:update, "a",
           %{"block" => %{"rendered_html" => "<h1>", "rendered_at" => "now", "sequence" => 99, "children" => []}}}
        )

      assert {:ok, params} = Ops.materialize_root(state, "a")

      refute Map.has_key?(params["block"], "rendered_html")
      refute Map.has_key?(params["block"], "rendered_at")
      # the stale sequence 99 is replaced by the tree-derived index
      assert params["block"]["sequence"] == 0
      # the tree still knows a1 even though the stale diff said children: []
      assert [%{"uid" => "a1"}] = params["block"]["children"]
    end

    test "inserted blocks materialize without ids" do
      state = apply!(Ops.new([]), {:insert, "x", 0, %{"entry_id" => 7, "block" => %{"uid" => "x", "type" => "module"}}})

      assert {:ok, params} = Ops.materialize_root(state, "x")
      refute Map.has_key?(params, "id")
      assert params["entry_id"] == 7
      assert params["sequence"] == 0
      assert params["block"]["type"] == "module"
    end
  end

  describe "op sequences" do
    test "insert → update → move → delete round trip" do
      state =
        Ops.new(["a", "b"])
        |> apply!({:insert, "x", 1, %{"entry_id" => 1}})
        |> apply!({:update, "x", %{"entry_id" => 1, "block" => %{"uid" => "x"}}})
        |> apply!({:move, "x", 2})
        |> apply!({:update, "a", %{"block" => %{"uid" => "a"}}})
        |> apply!({:delete, "b"})

      assert state.order == ["a", "x"]
      assert state.statuses == %{"a" => :persisted, "x" => :inserted}
      assert state.deleted == ["b"]
      assert Map.keys(state.diffs) |> Enum.sort() == ["a", "x"]
    end

    test "unknown op shape is rejected" do
      assert {:error, {:unknown_op, _}} = Ops.apply_op(Ops.new([]), {:frobnicate, "a"})
    end
  end

  describe "changes_to_params/1" do
    test "flat changes become string-keyed params" do
      cs = Changeset.change(%Block{}, %{uid: "abc", active: false})
      assert Ops.changes_to_params(cs) == %{"uid" => "abc", "active" => false}
    end

    test "empty changeset produces empty params" do
      assert Ops.changes_to_params(Changeset.change(%Block{})) == %{}
    end

    test "nested assoc changesets become nested maps and lists" do
      var_cs = Changeset.change(%Var{}, %{key: "heading", value: "Hello"})

      cs =
        %Block{}
        |> Changeset.change(%{uid: "abc"})
        |> Changeset.put_assoc(:vars, [var_cs])

      params = Ops.changes_to_params(cs)

      assert params["uid"] == "abc"
      assert [var_params] = params["vars"]
      assert var_params["key"] == "heading"
      assert var_params["value"] == "Hello"
    end

    test "persisted children carry their primary key from data" do
      var_cs = Changeset.change(%Var{id: 42}, %{value: "Updated"})

      cs =
        %Block{}
        |> Changeset.change()
        |> Changeset.put_assoc(:vars, [var_cs])

      assert [%{"id" => 42, "value" => "Updated"}] = Ops.changes_to_params(cs)["vars"]
    end

    test "an explicit id change wins over the data primary key" do
      var_cs = Changeset.change(%Var{id: 42}, %{id: 43})

      cs =
        %Block{}
        |> Changeset.change()
        |> Changeset.put_assoc(:vars, [var_cs])

      assert [%{"id" => 43}] = Ops.changes_to_params(cs)["vars"]
    end

    test "children marked :replace or :delete are dropped from the list" do
      keep = Changeset.change(%Var{id: 1}, %{value: "keep"})
      replaced = %{Changeset.change(%Var{id: 2}) | action: :replace}
      deleted = %{Changeset.change(%Var{id: 3}) | action: :delete}

      cs =
        %Block{}
        |> Changeset.change()
        |> Changeset.put_assoc(:vars, [keep])

      # put_assoc computes :replace internally; splice explicit action-tagged
      # changesets into the change to pin the dropping behaviour
      cs = %{cs | changes: %{cs.changes | vars: [keep, replaced, deleted]}}

      assert [%{"id" => 1, "value" => "keep"}] = Ops.changes_to_params(cs)["vars"]
    end

    test "a :replace changeset in a single-assoc change is dropped entirely" do
      replaced = %{Changeset.change(%Var{id: 2}) | action: :replace}
      cs = %{Changeset.change(%Block{}) | changes: %{creator: replaced}}

      assert Ops.changes_to_params(cs) == %{}
    end

    test "non-changeset values pass through untouched" do
      now = DateTime.utc_now()
      cs = Changeset.change(%Block{}, %{rendered_at: now})
      assert Ops.changes_to_params(cs)["rendered_at"] == now
    end
  end
end
