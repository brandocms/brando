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
    test "replaces the diff wholesale" do
      state =
        Ops.new(["a"])
        |> apply!({:update, "a", %{"block" => %{"refs" => [%{"name" => "p"}]}}})
        |> apply!({:update, "a", %{"block" => %{"uid" => "a"}}})

      assert state.diffs["a"] == %{"block" => %{"uid" => "a"}}
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

  describe "remote sync snapshots" do
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

    test "subtree_snapshot/2 carries diffs, structure and DFS order" do
      state =
        sync_state()
        |> apply!({:update, "a2", %{"type" => "module"}})
        |> apply!({:update, "a2x", %{"uid" => "a2x"}})

      snapshot = Ops.subtree_snapshot(state, "a2")

      assert snapshot.uids == ["a2", "a2x"]
      assert snapshot.diffs == %{"a2" => %{"type" => "module"}, "a2x" => %{"uid" => "a2x"}}
      assert snapshot.parents == %{"a2" => "a", "a2x" => "a2"}
      assert snapshot.child_order == %{"a2" => ["a2x"]}
    end

    test "apply_remote_snapshot/3 updates known uids" do
      sender = apply!(sync_state(), {:update, "a2", %{"type" => "module"}})
      snapshot = Ops.subtree_snapshot(sender, "a2")

      assert {:ok, receiver} = Ops.apply_remote_snapshot(sync_state(), "a2", snapshot)
      assert receiver.diffs["a2"] == %{"type" => "module"}
      assert receiver.order == sync_state().order
    end

    test "apply_remote_snapshot/3 attaches unknown children under their shipped parent" do
      sender =
        sync_state()
        |> apply!({:insert_child, "a", "new1", 1, %{"uid" => "new1", "type" => "module"}})
        |> apply!({:update, "a", %{"block" => %{"description" => "edited"}}})

      snapshot = Ops.subtree_snapshot(sender, "a")

      assert {:ok, receiver} = Ops.apply_remote_snapshot(sync_state(), "a", snapshot)
      assert receiver.parents["new1"] == "a"
      assert receiver.statuses["new1"] == :inserted
      # shipped child order applied, so the remote insert lands at position 1
      assert receiver.child_order["a"] == ["a1", "new1", "a2"]
      assert receiver.diffs["new1"]["type"] == "module"
    end

    test "apply_remote_snapshot/3 rejects a fully unknown subtree" do
      snapshot = %{uids: ["ghost"], diffs: %{}, parents: %{}, child_order: %{}}
      assert {:error, {:unknown_uid, "ghost"}} = Ops.apply_remote_snapshot(sync_state(), "ghost", snapshot)
    end
  end

  describe "materialize_root/2" do
    test "unknown root is rejected" do
      assert {:error, {:unknown_uid, "x"}} = Ops.materialize_root(Ops.new([]), "x")
    end

    test "untouched persisted blocks materialize as id+sequence-only params" do
      state = Ops.from_entry_blocks([entry_block("a", 1, 10), entry_block("b", 2, 20)])

      assert {:ok, params} = Ops.materialize_root(state, "b")
      assert params == %{"id" => 2, "sequence" => 1, "block" => %{"id" => 20, "uid" => "b", "sequence" => 1}}
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
