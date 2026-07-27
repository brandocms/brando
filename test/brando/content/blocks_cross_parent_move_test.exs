defmodule Brando.Content.BlocksCrossParentMoveTest do
  # Regression coverage for the outline's cross-parent move at SAVE time.
  #
  # Moving a persisted child between two containers reparents it in the op
  # store ({:insert_child} with a known uid → {:move_to_parent}). At save,
  # the old parent's cast no longer lists the child (children are
  # on_replace: :delete_if_exists → row deleted) while the new parent's cast
  # sees an unknown id → fresh insert (:id is not castable on children).
  # The MOVE must survive that mechanic: content ends up under the new
  # parent, nothing is duplicated, nothing is lost.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Factory
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset

  defp insert_page_with_containers(user) do
    page = Factory.insert(:page, creator: user)

    entry_blocks =
      for {container_uid, children} <- [
            {"containerA",
             [
               %{
                 uid: "childC",
                 type: :module,
                 active: true,
                 source: "Elixir.Brando.Pages.Page.Blocks",
                 creator_id: user.id,
                 sequence: 0,
                 description: "the moving child",
                 vars: [],
                 refs: [],
                 children: []
               }
             ]},
            {"containerB", []}
          ],
          reduce: [] do
        acc ->
          entry_block =
            %Brando.Pages.Page.Blocks{}
            |> Changeset.change(%{entry_id: page.id, sequence: length(acc)})
            |> Changeset.put_assoc(:block, %{
              uid: container_uid,
              type: :container,
              active: true,
              source: "Elixir.Brando.Pages.Page.Blocks",
              creator_id: user.id,
              sequence: length(acc),
              children: children
            })
            |> Brando.Repo.insert!()

          acc ++ [entry_block]
      end

    {page, entry_blocks}
  end

  defp preloaded_entry_blocks(page_id) do
    import Ecto.Query

    # same tree preload the form uses — every level's children loaded
    Brando.Pages.Page.Blocks
    |> where([eb], eb.entry_id == ^page_id)
    |> order_by([eb], eb.sequence)
    |> Brando.Repo.all()
    |> Brando.Repo.preload(
      block: [
        :vars,
        :refs,
        :table_rows,
        :block_identifiers,
        children: &ContentBlocks.preload_child_trees/1
      ]
    )
  end

  # the exact save path BlockField's fetch_root_blocks + the Form run:
  # materialize each root from the op store, cast over the persisted entry
  # block, put_assoc the lot on the entry and update.
  defp save_from_ops(page, entry_blocks, ops, user) do
    by_uid = Map.new(entry_blocks, &{&1.block.uid, &1})

    root_changesets =
      Enum.map(ops.order, fn uid ->
        {:ok, params} = Ops.materialize_root(ops, uid)
        # recursive?: true, exactly as BlockField's save clause does — the
        # default cast drops "children" params entirely
        Brando.Pages.Page.Blocks.changeset(by_uid[uid], params, user.id, true)
      end)

    updated =
      root_changesets
      |> ContentBlocks.reject_deleted(true)
      |> ContentBlocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)

    page
    |> Brando.Repo.preload(:entry_blocks)
    |> Changeset.change()
    |> Changeset.put_assoc(:entry_blocks, updated)
    |> Brando.Repo.update()
  end

  test "outline cross-parent move of a persisted child survives save" do
    user = Factory.insert(:random_user)
    {page, _} = insert_page_with_containers(user)

    entry_blocks = preloaded_entry_blocks(page.id)

    assert [%{block: %{uid: "containerA", children: [child]}}, %{block: %{uid: "containerB", children: []}}] =
             entry_blocks

    assert child.uid == "childC"
    original_child_id = child.id

    # the outline move lands as insert_child with a known uid (reparent);
    # the diff ships the child's current content, as the extract path does
    ops = Ops.from_entry_blocks(entry_blocks)

    child_diff = %{
      "uid" => "childC",
      "type" => "module",
      "active" => true,
      "description" => "the moving child",
      "creator_id" => user.id
    }

    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childC", 0, child_diff})

    assert {:ok, _page} = save_from_ops(page, entry_blocks, ops, user)

    # persisted truth after save
    reloaded = preloaded_entry_blocks(page.id)

    assert [%{block: %{uid: "containerA", children: a_children}}, %{block: %{uid: "containerB", children: b_children}}] =
             reloaded

    assert a_children == [], "child must be gone from the old parent"
    assert [moved] = b_children
    assert moved.uid == "childC"
    assert moved.description == "the moving child"

    # no orphaned/duplicated rows: exactly one childC block in the table
    import Ecto.Query

    child_rows =
      Brando.Content.Block
      |> where([b], b.uid == "childC")
      |> Brando.Repo.all()

    assert length(child_rows) == 1

    # row identity is allowed to change (delete+insert move) — document
    # whichever mechanic is in effect so a behavior change is visible
    if moved.id == original_child_id do
      assert moved.parent_id != nil
    else
      refute Brando.Repo.get(Brando.Content.Block, original_child_id)
    end
  end

  test "editing a nested child persists through save as an UPDATE" do
    user = Factory.insert(:random_user)
    {page, _} = insert_page_with_containers(user)

    entry_blocks = preloaded_entry_blocks(page.id)
    [%{block: %{children: [child]}}, _] = entry_blocks
    original_child_id = child.id

    ops = Ops.from_entry_blocks(entry_blocks)
    {:ok, ops} = Ops.apply_op(ops, {:update, "childC", %{"description" => "edited child"}})

    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    [_, %{block: %{children: []}}] = reloaded = preloaded_entry_blocks(page.id)
    assert [%{block: %{children: [moved]}}, _] = reloaded
    assert moved.description == "edited child"
    # an edit must be an UPDATE on the same row, never delete+reinsert
    assert moved.id == original_child_id
  end

  test "deleting a parent's last child persists through save" do
    user = Factory.insert(:random_user)
    {page, _} = insert_page_with_containers(user)

    entry_blocks = preloaded_entry_blocks(page.id)
    ops = Ops.from_entry_blocks(entry_blocks)
    {:ok, ops} = Ops.apply_op(ops, {:delete, "childC"})

    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    reloaded = preloaded_entry_blocks(page.id)
    assert [%{block: %{uid: "containerA", children: []}}, _] = reloaded

    import Ecto.Query
    assert Brando.Content.Block |> where([b], b.uid == "childC") |> Brando.Repo.all() == []
  end

  test "a brand-new root block (fresh base struct) saves through the recursive cast" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    # what BlockField's insert path stores + materializes for a new block
    ops = Ops.new([])

    {:ok, ops} =
      Ops.apply_op(
        ops,
        {:insert, "newroot", 0,
         %{
           "entry_id" => page.id,
           "block" => %{
             "uid" => "newroot",
             "type" => "module",
             "active" => true,
             "creator_id" => user.id,
             "source" => "Elixir.Brando.Pages.Page.Blocks"
           }
         }}
      )

    {:ok, params} = Ops.materialize_root(ops, "newroot")

    # materialize_base_struct's fresh-base branch
    base_block = %Brando.Content.Block{vars: [], refs: [], table_rows: [], children: [], block_identifiers: []}
    base = %Brando.Pages.Page.Blocks{} |> Map.put(:block, base_block)

    cs = Brando.Pages.Page.Blocks.changeset(base, params, user.id, true)

    updated =
      [cs]
      |> ContentBlocks.reject_deleted(true)
      |> ContentBlocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)

    assert {:ok, _} =
             page
             |> Brando.Repo.preload(:entry_blocks)
             |> Changeset.change()
             |> Changeset.put_assoc(:entry_blocks, updated)
             |> Brando.Repo.update()

    assert [%{block: %{uid: "newroot"}}] = preloaded_entry_blocks(page.id)
  end

  test "a UI-shaped child insert (build_block diff) persists through save" do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        %{
          name: %{"en" => "Member"},
          namespace: %{"en" => "test"},
          help_text: %{"en" => "help"},
          class: "member",
          code: "<div>{% ref refs.text %} {{ title }}</div>",
          refs: [
            %{
              name: "text",
              uid: "testref01",
              description: "text ref",
              data: %{
                type: "text",
                data: %{text: "Default text", type: "paragraph"}
              }
            }
          ],
          vars: [
            %{
              type: :string,
              label: "Title",
              key: "title",
              value: "Default title",
              placement: :content,
              width: :full
            }
          ]
        },
        user
      )

    {page, _} = insert_page_with_containers(user)
    entry_blocks = preloaded_entry_blocks(page.id)
    ops = Ops.from_entry_blocks(entry_blocks)

    # exactly what Block's insert_block handler emits for a new child
    empty_block_cs =
      BrandoAdmin.Components.Form.BlockField.build_block(
        module.id,
        user.id,
        nil,
        "Elixir.Brando.Pages.Page.Blocks",
        :module
      )

    child_uid = Changeset.get_field(empty_block_cs, :uid)
    diff = Ops.block_diff_params(empty_block_cs)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", child_uid, 0, diff})

    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    reloaded = preloaded_entry_blocks(page.id)
    assert [_, %{block: %{uid: "containerB", children: [inserted]}}] = reloaded
    assert inserted.uid == child_uid
    assert inserted.module_id == module.id
    assert length(inserted.refs) == 1
    assert length(inserted.vars) == 1
  end

  test "CREATE flow: new entry + new root + new child in one insert cascade" do
    user = Factory.insert(:random_user)

    # new multi root with a new child — the create-form flow (nothing persisted)
    ops = Ops.new([])

    {:ok, ops} =
      Ops.apply_op(
        ops,
        {:insert, "newmulti", 0,
         %{
           "block" => %{
             "uid" => "newmulti",
             "type" => "module",
             "multi" => true,
             "active" => true,
             "creator_id" => user.id,
             "source" => "Elixir.Brando.Pages.Page.Blocks"
           }
         }}
      )

    {:ok, ops} =
      Ops.apply_op(
        ops,
        {:insert_child, "newmulti", "newkid", 0,
         %{
           "uid" => "newkid",
           "type" => "module",
           "active" => true,
           "creator_id" => user.id,
           "description" => "brand new child",
           "source" => "Elixir.Brando.Pages.Page.Blocks"
         }}
      )

    {:ok, params} = Ops.materialize_root(ops, "newmulti")

    base_block = %Brando.Content.Block{vars: [], refs: [], table_rows: [], children: [], block_identifiers: []}
    base = %Brando.Pages.Page.Blocks{} |> Map.put(:block, base_block)
    cs = Brando.Pages.Page.Blocks.changeset(base, params, user.id, true)

    updated =
      [cs]
      |> ContentBlocks.reject_deleted(true)
      |> ContentBlocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)

    page_params = Factory.params_for(:page) |> Map.put(:creator_id, user.id)

    assert {:ok, page} =
             %Brando.Pages.Page{}
             |> Brando.Pages.Page.changeset(page_params, user)
             |> Changeset.put_assoc(:entry_blocks, updated)
             |> Brando.Repo.insert()

    assert [%{block: %{uid: "newmulti", children: [kid]}}] = preloaded_entry_blocks(page.id)
    assert kid.uid == "newkid"
    assert kid.description == "brand new child"
  end

  test "a second save after the move is a no-op for the moved child" do
    user = Factory.insert(:random_user)
    {page, _} = insert_page_with_containers(user)

    entry_blocks = preloaded_entry_blocks(page.id)
    ops = Ops.from_entry_blocks(entry_blocks)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childC", 0, %{"uid" => "childC"}})
    {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    # a fresh session: re-init from persisted state, save untouched
    entry_blocks = preloaded_entry_blocks(page.id)
    ops = Ops.from_entry_blocks(entry_blocks)
    {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    reloaded = preloaded_entry_blocks(page.id)
    assert [%{block: %{children: []}}, %{block: %{uid: "containerB", children: [moved]}}] = reloaded
    assert moved.uid == "childC"
  end
end
