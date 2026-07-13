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
