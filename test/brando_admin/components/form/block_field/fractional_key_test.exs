defmodule BrandoAdmin.Components.Form.BlockField.FractionalKeyTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.BlockField.FractionalKey
  alias BrandoAdmin.Components.Form.BlockField.Ops

  doctest FractionalKey

  defp apply!(state, op) do
    {:ok, state} = Ops.apply_op(state, op)
    state
  end

  defp sorted_by_keys?(list, keys), do: Enum.map(list, &keys[&1]) == Enum.sort(Enum.map(list, &keys[&1]))

  describe "keys" do
    test "there is always a key between two, and they stay ordered" do
      :rand.seed(:exsss, {1, 2, 3})

      keys =
        Enum.reduce(1..500, [FractionalKey.between(nil, nil)], fn _, keys ->
          index = :rand.uniform(length(keys) + 1) - 1
          before = if index > 0, do: Enum.at(keys, index - 1)
          next = Enum.at(keys, index)
          key = FractionalKey.between(before, next)
          assert is_nil(before) or before < key
          assert is_nil(next) or key < next
          refute String.ends_with?(key, "0")
          List.insert_at(keys, index, key)
        end)

      assert keys == Enum.sort(keys)
      assert length(Enum.uniq(keys)) == 501
    end

    test "spread keys are ordered, distinct and short" do
      keys = FractionalKey.spread(1000)
      assert keys == Enum.sort(keys)
      assert length(Enum.uniq(keys)) == 1000
      assert Enum.all?(keys, &(byte_size(&1) <= 3))
    end

    test "rekey keeps what still sorts and fills in the rest" do
      keys = %{"a" => "V", "b" => "Z", "c" => "X"}
      rekeyed = FractionalKey.rekey(["a", "b", "c"], keys)
      assert rekeyed["a"] == "V" and rekeyed["b"] == "Z"
      assert sorted_by_keys?(["a", "b", "c"], rekeyed)
    end

    test "a key before another needs a strictly lower one" do
      assert_raise ArgumentError, fn -> FractionalKey.between("V", "V") end
    end
  end

  describe "block order in the store" do
    test "two inserts at the same place both stay, in the same order everywhere" do
      base = Ops.new(["x", "y"])
      # Both editors put a block between x and y in their own view.
      from_a = Ops.keyed(base, {:insert, "from_a", 1, %{}})
      from_b = Ops.keyed(base, {:insert, "from_b", 1, %{}})
      assert {:insert, _, {:key, key}, _} = from_a
      assert {:insert, _, {:key, ^key}, _} = from_b

      one_way = base |> apply!(from_a) |> apply!(from_b)
      other_way = base |> apply!(from_b) |> apply!(from_a)

      assert one_way.order == ["x", "from_a", "from_b", "y"]
      assert other_way.order == one_way.order
    end

    test "a keyed insert keeps its neighbours when an earlier insert shifted the indexes" do
      base = Ops.new(["x", "y", "z"])
      # A puts a block between y and z (index 2); B inserts at the top first.
      from_a = Ops.keyed(base, {:insert, "from_a", 2, %{}})
      state = base |> apply!({:insert, "top", 0, %{}}) |> apply!(from_a)

      assert state.order == ["top", "x", "y", "from_a", "z"]

      # The same op as an index would have landed between x and y.
      by_index = base |> apply!({:insert, "top", 0, %{}}) |> apply!({:insert, "from_a", 2, %{}})
      assert by_index.order == ["top", "x", "from_a", "y", "z"]
    end

    test "moves, reorders, child inserts and restores keep sibling keys in order" do
      state =
        Ops.new(["a", "b", "c"])
        |> apply!({:move, "c", 0})
        |> apply!({:insert_child, "a", "a1", :end, %{}})
        |> apply!({:insert_child, "a", "a0", 0, %{}})
        |> apply!({:reorder, ["b", "a", "c"]})

      snapshot = Ops.bin_snapshot(state, "a")
      state = state |> apply!({:delete, "a"}) |> apply!({:restore, snapshot})

      assert state.order == ["b", "a", "c"]
      assert state.child_order["a"] == ["a0", "a1"]
      assert sorted_by_keys?(state.order, state.keys)
      assert sorted_by_keys?(state.child_order["a"], state.keys)
    end

    test "rows loaded after a save take the keys the session uses" do
      state = Ops.new(["a", "b"]) |> apply!({:insert, "n", 1, %{}})
      saved = Ops.new(["a", "n", "b"])

      adopted = Ops.adopt_keys(saved, state)
      assert Map.take(adopted.keys, ["a", "n", "b"]) == Map.take(state.keys, ["a", "n", "b"])

      # An op made before the save still lands where it was meant.
      late = Ops.keyed(state, {:insert, "late", 2, %{}})
      assert apply!(adopted, late).order == ["a", "n", "late", "b"]
    end
  end
end
