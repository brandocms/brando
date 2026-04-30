defmodule Brando.Villain.DuplicationTest do
  @moduledoc """
  Tests for block duplication logic in ContentBlocks.

  Covers: duplicate_block, duplicate_refs, duplicate_vars, duplicate_table_rows,
  duplicate_child, add_uid_to_refs, and the block_changeset vs
  recursive_block_changeset replace-rejection behavior.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Content.{Block, Ref, Var, TableRow}
  alias Brando.Content.Blocks, as: ContentBlocks
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    {:ok, %{user: user}}
  end

  # -- Helpers --

  defp build_var(attrs \\ %{}) do
    defaults = %{
      id: 100,
      type: :text,
      label: "Test var",
      key: "test_var",
      value: "hello",
      sequence: 0,
      block_id: 50,
      creator_id: 1
    }

    struct(Var, Map.merge(defaults, attrs))
  end

  defp build_ref(attrs \\ %{}) do
    defaults = %{
      id: 200,
      name: "test_ref",
      description: "A test ref",
      uid: "ref-original-uid",
      sequence: 0,
      block_id: 50,
      module_id: 10,
      active: true,
      collapsed: false,
      data: %Brando.Villain.Blocks.TextBlock{
        type: "text",
        data: %Brando.Villain.Blocks.TextBlock.Data{text: "Hello"}
      }
    }

    struct(Ref, Map.merge(defaults, attrs))
  end

  defp build_table_row(attrs \\ %{}) do
    defaults = %{
      id: 300,
      block_id: 50,
      sequence: 0,
      vars: [
        build_var(%{id: 400, key: "col1", value: "cell1"}),
        build_var(%{id: 401, key: "col2", value: "cell2"})
      ]
    }

    struct(TableRow, Map.merge(defaults, attrs))
  end

  defp build_block(attrs \\ %{}) do
    defaults = %{
      id: 50,
      uid: "block-original-uid",
      type: :module,
      active: true,
      creator_id: 1,
      sequence: 0,
      multi: false,
      vars: [build_var()],
      refs: [build_ref()],
      table_rows: [],
      children: [],
      block_identifiers: []
    }

    struct(Block, Map.merge(defaults, attrs))
  end

  # ============================================================
  # duplicate_refs/3
  # ============================================================

  describe "duplicate_refs/3" do
    test "clears id, block_id, module_id and generates new uid", %{user: user} do
      block = build_block()
      refs = block.refs

      changeset =
        block
        |> Map.merge(%{id: nil, uid: "new-uid", refs: []})
        |> Changeset.change()
        |> ContentBlocks.duplicate_refs(refs, user.id)

      duplicated_refs = Changeset.get_change(changeset, :refs)
      assert length(duplicated_refs) == 1

      ref_cs = hd(duplicated_refs)
      assert ref_cs.action == :insert

      # duplicate_ref clears PKs via Map.merge on the struct (in data)
      # and puts new uid as a changeset change
      assert is_nil(ref_cs.data.id), "id should be nil"
      assert is_nil(ref_cs.data.block_id), "block_id should be nil"
      assert is_nil(ref_cs.data.module_id), "module_id should be nil"

      # New UID is in the changeset changes
      new_uid = Changeset.get_field(ref_cs, :uid)
      assert new_uid != "ref-original-uid", "should have a new uid"
    end
  end

  # ============================================================
  # add_uid_to_refs/1 — does NOT clear block_id/module_id
  # ============================================================

  describe "add_uid_to_refs/1 (changeset version)" do
    test "does NOT clear block_id or module_id from refs" do
      block = build_block()

      changeset =
        block
        |> Changeset.change()
        |> Changeset.put_assoc(:refs, block.refs)

      result = ContentBlocks.add_uid_to_refs(changeset)
      ref_changes = Changeset.get_assoc(result, :refs)

      for ref_cs <- ref_changes do
        ref = if is_struct(ref_cs, Ecto.Changeset), do: ref_cs.data, else: ref_cs
        # add_uid_to_refs does NOT clear foreign keys — this is the inconsistency
        assert ref.block_id == 50, "add_uid_to_refs leaves block_id intact"
        assert ref.module_id == 10, "add_uid_to_refs leaves module_id intact"
      end
    end
  end

  # ============================================================
  # duplicate_table_rows/2 — nested vars are NOT duplicated
  # ============================================================

  describe "duplicate_table_rows/3" do
    test "duplicated table rows have nil id and block_id", %{user: user} do
      block = build_block(%{table_rows: [build_table_row()]})
      table_rows = block.table_rows

      changeset =
        block
        |> Map.merge(%{id: nil, table_rows: []})
        |> Changeset.change()
        |> ContentBlocks.duplicate_table_rows(table_rows, user.id)

      dup_rows = Changeset.get_change(changeset, :table_rows)
      assert length(dup_rows) == 1

      row_cs = hd(dup_rows)
      assert row_cs.action == :insert
      assert is_nil(row_cs.data.id), "id should be nil"
      assert is_nil(row_cs.data.block_id), "block_id should be nil"
    end

    test "nested vars in table rows are properly duplicated", %{user: user} do
      table_row = build_table_row()
      assert length(table_row.vars) == 2

      block = build_block(%{table_rows: [table_row]})

      changeset =
        block
        |> Map.merge(%{id: nil, table_rows: []})
        |> Changeset.change()
        |> ContentBlocks.duplicate_table_rows(block.table_rows, user.id)

      dup_rows = Changeset.get_change(changeset, :table_rows)
      row_cs = hd(dup_rows)

      # Vars should now be in changes with fresh IDs
      vars_in_changes = Changeset.get_change(row_cs, :vars)
      assert length(vars_in_changes) == 2, "table row vars should be duplicated"

      for var_cs <- vars_in_changes do
        assert var_cs.action == :insert
        assert is_nil(var_cs.data.id), "var id should be nil"
        assert is_nil(var_cs.data.block_id), "var block_id should be nil"
      end
    end
  end

  # ============================================================
  # block_changeset vs recursive_block_changeset (review #9)
  # ============================================================

  describe "block_changeset/3" do
    test "new block (nil id) sets action to :insert", %{user: user} do
      block = %Block{
        vars: [build_var(%{id: nil, block_id: nil})],
        refs: [build_ref(%{id: nil, block_id: nil, module_id: nil})],
        table_rows: [],
        children: [],
        block_identifiers: []
      }

      attrs = %{
        "uid" => "test-uid-123",
        "type" => "module",
        "active" => "true",
        "sequence" => "0"
      }

      changeset = Block.block_changeset(block, attrs, user)
      assert changeset.action == :insert
    end
  end

  describe "recursive_block_changeset/3" do
    test "new block (nil id) does NOT set action to :insert", %{user: user} do
      block = %Block{
        vars: [build_var(%{id: nil, block_id: nil})],
        refs: [build_ref(%{id: nil, block_id: nil, module_id: nil})],
        table_rows: [],
        children: [],
        block_identifiers: []
      }

      attrs = %{
        "uid" => "test-uid-456",
        "type" => "module",
        "active" => "true",
        "sequence" => "0"
      }

      changeset = Block.recursive_block_changeset(block, attrs, user)

      # recursive_block_changeset does NOT set :insert action —
      # this is fine because it's used in the save path where action
      # is managed by the parent cast_assoc
      assert is_nil(changeset.action),
             "recursive_block_changeset leaves action as nil (managed by parent)"
    end
  end

  # ============================================================
  # duplicate_block/2 — the main entry point
  # ============================================================

  describe "duplicate_block/2" do
    test "duplicates a block changeset with all associations", %{user: user} do
      block =
        build_block(%{
          table_rows: [build_table_row()],
          children: [
            build_block(%{id: 99, uid: "child-uid", parent_id: 50, refs: [], vars: [], table_rows: [], children: []})
          ]
        })

      block_cs = Changeset.change(block)

      result = ContentBlocks.duplicate_block(block_cs, user_id: user.id, sequence: 5, uid: "custom-uid")

      assert result.action == :insert
      assert Changeset.get_field(result, :uid) == "custom-uid"
      assert Changeset.get_field(result, :sequence) == 5
      assert Changeset.get_field(result, :creator_id) == user.id
      assert is_nil(Changeset.get_field(result, :id))
      assert is_nil(Changeset.get_field(result, :parent_id))

      # Vars duplicated
      vars = Changeset.get_change(result, :vars)
      assert length(vars) == 1
      assert hd(vars).action == :insert

      # Refs duplicated
      refs = Changeset.get_change(result, :refs)
      assert length(refs) == 1
      assert hd(refs).action == :insert

      # Table rows duplicated with nested vars
      table_rows = Changeset.get_change(result, :table_rows)
      assert length(table_rows) == 1
      row_cs = hd(table_rows)
      row_vars = Changeset.get_change(row_cs, :vars)
      assert length(row_vars) == 2

      # Children duplicated
      children = Changeset.get_change(result, :children)
      assert length(children) == 1
      child_cs = hd(children)
      assert child_cs.action == :insert
      child_uid = Changeset.get_field(child_cs, :uid)
      assert child_uid != "child-uid", "child should get a new uid"
    end

    test "auto-generates uid when not provided", %{user: user} do
      block = build_block(%{refs: [], vars: [], table_rows: [], children: []})
      block_cs = Changeset.change(block)

      result = ContentBlocks.duplicate_block(block_cs, user_id: user.id)

      uid = Changeset.get_field(result, :uid)
      assert uid != "block-original-uid"
      assert is_binary(uid)
      assert Changeset.get_field(result, :sequence) == 0
    end
  end

  # ============================================================
  # duplicate_child/2
  # ============================================================

  describe "duplicate_child/2" do
    test "child gets new uid, nil id, nil parent_id", %{user: user} do
      child =
        build_block(%{
          id: 99,
          uid: "child-original-uid",
          parent_id: 50,
          refs: [build_ref(%{id: 201, block_id: 99})],
          vars: [build_var(%{id: 101, block_id: 99})],
          table_rows: [],
          children: []
        })

      result = ContentBlocks.duplicate_child(child, user.id)

      assert result.action == :insert
      uid = Changeset.get_field(result, :uid)
      assert uid != "child-original-uid"
      assert is_nil(Changeset.get_field(result, :id))
      assert is_nil(Changeset.get_field(result, :parent_id))
    end

    test "child's refs have nil block_id, module_id, and new uid", %{user: user} do
      child =
        build_block(%{
          id: 99,
          uid: "child-original-uid",
          parent_id: 50,
          refs: [build_ref(%{id: 201, block_id: 99, module_id: 10})],
          vars: [build_var(%{id: 101, block_id: 99})],
          table_rows: [],
          children: []
        })

      result = ContentBlocks.duplicate_child(child, user.id)

      # Refs should now use duplicate_refs (not add_uid_to_refs)
      ref_changes = Changeset.get_change(result, :refs)
      assert length(ref_changes) == 1

      ref_cs = hd(ref_changes)
      assert ref_cs.action == :insert
      assert is_nil(ref_cs.data.id), "id should be nil"
      assert is_nil(ref_cs.data.block_id), "block_id should be nil"
      assert is_nil(ref_cs.data.module_id), "module_id should be nil"

      new_uid = Changeset.get_field(ref_cs, :uid)
      assert new_uid != "ref-original-uid", "should have a new uid"
    end

    test "child vars are properly duplicated with nil IDs", %{user: user} do
      child =
        build_block(%{
          id: 99,
          uid: "child-original-uid",
          parent_id: 50,
          refs: [build_ref(%{id: 201, block_id: 99})],
          vars: [build_var(%{id: 101, block_id: 99, key: "myvar", value: "myval"})],
          table_rows: [],
          children: []
        })

      result = ContentBlocks.duplicate_child(child, user.id)

      vars = Changeset.get_change(result, :vars)
      assert length(vars) == 1

      var_cs = hd(vars)
      assert var_cs.action == :insert
      assert is_nil(var_cs.data.id), "var id should be nil"
      assert is_nil(var_cs.data.block_id), "var block_id should be nil"
    end
  end
end
