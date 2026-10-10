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
        by_uid[uid]
        |> Brando.Pages.Page.Blocks.changeset(params, user.id, true)
        |> BrandoAdmin.Components.Form.BlockField.keep_moved_identity(entry_blocks)
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

    # The outline move lands as insert_child with a known uid (reparent). The
    # diff below stands in for the child's CURRENT content — which is what the
    # extract path ships now that it materializes from the op store rather than
    # from the parent's mount-time seed form. See "a child edited before an
    # outline move keeps its edits" for the case where the two differ.
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

  # B3: the outline used to ship `children_forms[uid].source` — a mount-time
  # seed — as the moved child's content, so the target re-registered that stale
  # diff and every edit made before the move was discarded. The move now
  # materializes the child from the op store instead.
  test "a child edited before an outline move keeps its edits" do
    user = Factory.insert(:random_user)
    {page, _} = insert_page_with_containers(user)

    entry_blocks = preloaded_entry_blocks(page.id)
    ops = Ops.from_entry_blocks(entry_blocks)

    # the user edits the child while it still sits under containerA
    {:ok, ops} = Ops.apply_op(ops, {:update, "childC", %{"description" => "edited before moving"}})

    # ... then drags it to containerB. The move ships what the store holds now,
    # which is what `Ops.materialize_child/2` returns.
    assert {:ok, moved_params} = Ops.materialize_child(ops, "childC")
    assert moved_params["description"] == "edited before moving"

    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childC", 0, moved_params})

    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    reloaded = preloaded_entry_blocks(page.id)
    assert [%{block: %{children: []}}, %{block: %{uid: "containerB", children: [moved]}}] = reloaded
    assert moved.uid == "childC"

    assert moved.description == "edited before moving",
           "the edit made before the move must survive it"
  end

  # Containers A (holding `child`) and B, empty.
  defp insert_containers(page, user, child) do
    for {uid, children, seq} <- [{"containerA", [child], 0}, {"containerB", [], 1}] do
      %Brando.Pages.Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: seq})
      |> Changeset.put_assoc(:block, %{
        uid: uid,
        type: :container,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: seq,
        children: children
      })
      |> Brando.Repo.insert!()
    end
  end

  # Review: the move ships the child as BlockField's insert_extracted_child
  # builds it, a changeset over its row (`Ops.block_diff_params/1`), which
  # holds only its changes. Under the new parent the child is a new row, so
  # whatever it did not change has to travel too.
  test "a moved child keeps its refs, vars and fields it did not change" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    child = %{
      uid: "childR",
      type: :module,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      description: "unchanged",
      anchor: "kept-anchor",
      refs: [
        %{
          name: "body",
          uid: "refR",
          data: %Brando.Villain.Blocks.TextBlock{data: %Brando.Villain.Blocks.TextBlock.Data{text: "<p>Ref text</p>"}}
        }
      ],
      vars: [%{type: :string, key: "heading", label: "Heading", value: "Var value"}],
      children: [
        %{
          uid: "grandR",
          type: :module,
          active: true,
          source: "Elixir.Brando.Pages.Page.Blocks",
          creator_id: user.id,
          sequence: 0,
          description: "the grandchild",
          children: []
        }
      ]
    }

    insert_containers(page, user, child)

    entry_blocks = preloaded_entry_blocks(page.id)
    [%{block: %{children: [row]}} | _] = entry_blocks
    ops = Ops.from_entry_blocks(entry_blocks)

    # as BlockField's insert_extracted_child and the target Block do it
    {:ok, params} = Ops.materialize_child(ops, "childR")
    block_cs = Brando.Content.Block.recursive_block_changeset(row, params, user.id)
    moved_cs = BrandoAdmin.Components.Form.BlockField.moved_child_changeset(block_cs, user.id)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childR", 0, Ops.block_diff_params(moved_cs)})

    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    assert [%{block: %{children: []}}, %{block: %{children: [moved]}}] = preloaded_entry_blocks(page.id)
    assert moved.uid == "childR"
    assert moved.type == :module
    assert moved.anchor == "kept-anchor"
    assert [%{name: "body", data: %{data: %{text: "<p>Ref text</p>"}}}] = moved.refs
    assert [%{key: "heading", value: "Var value"}] = moved.vars
    assert [%{uid: "grandR", description: "the grandchild", type: :module}] = moved.children
  end

  # Sol audit: a moved child's ref keeps its saved gallery by id, which
  # dropped the gallery changes the move carried.
  test "a moved child keeps the unsaved changes to its ref's gallery" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    [first, second] = for _ <- 1..2, do: Factory.insert(:image, creator_id: user.id)

    child = %{
      uid: "childG",
      type: :module,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      refs: [
        %{
          name: "gallery",
          uid: "refG",
          data: %Brando.Villain.Blocks.TextBlock{data: %Brando.Villain.Blocks.TextBlock.Data{text: ""}},
          gallery: %{gallery_objects: [%{image_id: first.id, sequence: 0}]}
        }
      ],
      children: []
    }

    insert_containers(page, user, child)

    entry_blocks = preloaded_entry_blocks(page.id)
    [%{block: %{children: [row]}} | _] = entry_blocks
    row = Brando.Repo.preload(row, refs: [gallery: :gallery_objects])
    [%{id: ref_id, gallery: %{id: gallery_id, gallery_objects: [%{id: object_id}]}}] = row.refs
    ops = Ops.from_entry_blocks(entry_blocks)

    # an image added to the gallery, not saved yet
    gallery = %{
      "id" => gallery_id,
      "gallery_objects" => [%{"id" => object_id}, %{"image_id" => second.id, "sequence" => 1}]
    }

    {:ok, ops} = Ops.apply_op(ops, {:update, "childG", %{"refs" => [%{"id" => ref_id, "gallery" => gallery}]}})

    {:ok, params} = Ops.materialize_child(ops, "childG")
    block_cs = Brando.Content.Block.recursive_block_changeset(row, params, user.id)
    moved_cs = BrandoAdmin.Components.Form.BlockField.moved_child_changeset(block_cs, user.id)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childG", 0, Ops.block_diff_params(moved_cs)})
    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    assert [%{block: %{children: []}}, %{block: %{children: [moved]}}] = preloaded_entry_blocks(page.id)
    [ref] = Brando.Repo.preload(moved, refs: [gallery: :gallery_objects]).refs
    assert ref.gallery.gallery_objects |> Enum.map(& &1.image_id) |> Enum.sort() == Enum.sort([first.id, second.id])
  end

  # Review: removing a gallery's last image clears the ref's gallery
  # (`put_assoc(:gallery, nil)`). The move must not bring it back by the
  # ref's old `gallery_id` (`apply_changes/1` nils it with the gallery).
  test "a moved child keeps its ref's gallery cleared before the move" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    image = Factory.insert(:image, creator_id: user.id)

    child = %{
      uid: "childX",
      type: :module,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      refs: [
        %{
          name: "gallery",
          uid: "refX",
          data: %Brando.Villain.Blocks.TextBlock{data: %Brando.Villain.Blocks.TextBlock.Data{text: ""}},
          gallery: %{gallery_objects: [%{image_id: image.id, sequence: 0}]}
        }
      ],
      children: []
    }

    insert_containers(page, user, child)

    entry_blocks = preloaded_entry_blocks(page.id)
    [%{block: %{children: [row]}} | _] = entry_blocks
    row = Brando.Repo.preload(row, refs: [gallery: :gallery_objects])
    [%{id: ref_id, gallery: %{id: gallery_id}}] = row.refs
    assert gallery_id
    ops = Ops.from_entry_blocks(entry_blocks)

    # the gallery's last image removed, as Block does it, not saved yet
    ref_cs = row.refs |> hd() |> Changeset.change() |> Changeset.put_assoc(:gallery, nil)
    removed = row |> Changeset.change() |> Changeset.put_assoc(:refs, [ref_cs])
    {:ok, ops} = Ops.apply_op(ops, {:update, "childX", Ops.changes_to_params(removed)})

    {:ok, params} = Ops.materialize_child(ops, "childX")
    block_cs = Brando.Content.Block.recursive_block_changeset(row, params, user.id)
    assert [%Changeset{changes: %{gallery: nil}}] = Changeset.get_change(block_cs, :refs)
    moved_cs = BrandoAdmin.Components.Form.BlockField.moved_child_changeset(block_cs, user.id)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childX", 0, Ops.block_diff_params(moved_cs)})
    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    assert [%{block: %{children: []}}, %{block: %{children: [moved]}}] = preloaded_entry_blocks(page.id)
    assert [%{uid: "refX", id: new_ref_id, gallery_id: nil}] = Brando.Repo.preload(moved, :refs, force: true).refs
    assert new_ref_id != ref_id
  end

  # Sol audit: a var's gallery came along as a nested gallery the var's
  # cast does not take, so the moved var lost it.
  test "a moved child's gallery var keeps its gallery" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    gallery = Brando.Repo.insert!(%Brando.Galleries.Gallery{})

    child = %{
      uid: "childV",
      type: :module,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      vars: [%{type: :gallery, key: "pics", label: "Pics", gallery_id: gallery.id}],
      table_rows: [%{sequence: 0, vars: [%{type: :gallery, key: "cell", label: "Cell", gallery_id: gallery.id}]}],
      children: []
    }

    insert_containers(page, user, child)
    entry_blocks = preloaded_entry_blocks(page.id)
    [%{block: %{children: [row]}} | _] = entry_blocks
    row = Brando.Repo.preload(row, [vars: :gallery, table_rows: [vars: :gallery]], force: true)
    ops = Ops.from_entry_blocks(entry_blocks)

    {:ok, params} = Ops.materialize_child(ops, "childV")
    block_cs = Brando.Content.Block.recursive_block_changeset(row, params, user.id)
    moved_cs = BrandoAdmin.Components.Form.BlockField.moved_child_changeset(block_cs, user.id)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childV", 0, Ops.block_diff_params(moved_cs)})
    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    assert [%{block: %{children: []}}, %{block: %{children: [moved]}}] = preloaded_entry_blocks(page.id)
    moved = Brando.Repo.preload(moved, [:vars, table_rows: :vars], force: true)
    assert [%{key: "pics", gallery_id: gallery_id}] = moved.vars
    assert gallery_id == gallery.id
    assert [%{vars: [%{key: "cell", gallery_id: cell_gallery_id}]}] = moved.table_rows
    assert cell_gallery_id == gallery.id
  end

  # Sol audit: a moved block is a new row, which the cast gives a new
  # sync uid (translations match blocks and table rows by it) and no
  # module version (it then reads as stale). Both are the server's, from
  # the row the block leaves.
  test "a moved child keeps its sync uids and module version" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    child = %{
      uid: "childS",
      sync_uid: "source-child",
      module_version: 3,
      type: :module,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      table_rows: [%{sequence: 0, sync_uid: "source-row", vars: []}],
      children: [
        %{
          uid: "grandS",
          sync_uid: "source-grand",
          module_version: 2,
          type: :module,
          active: true,
          source: "Elixir.Brando.Pages.Page.Blocks",
          creator_id: user.id,
          sequence: 0,
          children: []
        }
      ]
    }

    insert_containers(page, user, child)
    entry_blocks = preloaded_entry_blocks(page.id)
    [%{block: %{children: [row]}} | _] = entry_blocks
    ops = Ops.from_entry_blocks(entry_blocks)

    {:ok, params} = Ops.materialize_child(ops, "childS")
    block_cs = Brando.Content.Block.recursive_block_changeset(row, params, user.id)
    moved_cs = BrandoAdmin.Components.Form.BlockField.moved_child_changeset(block_cs, user.id)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childS", 0, Ops.block_diff_params(moved_cs)})
    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    assert [%{block: %{children: []}}, %{block: %{children: [moved]}}] = preloaded_entry_blocks(page.id)
    assert {moved.sync_uid, moved.module_version} == {"source-child", 3}
    assert [%{sync_uid: "source-row"}] = moved.table_rows
    assert [%{sync_uid: "source-grand", module_version: 2}] = moved.children
  end

  # Sol audit: a gallery picked or cleared before the move went back to the
  # saved one, which the var still had loaded.
  test "a moved child's gallery var keeps the gallery picked before the move" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    [saved, picked] = for _ <- 1..2, do: Brando.Repo.insert!(%Brando.Galleries.Gallery{})

    child = %{
      uid: "childP",
      type: :module,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      vars: [
        %{type: :gallery, key: "picked", label: "Picked", gallery_id: saved.id},
        %{type: :gallery, key: "cleared", label: "Cleared", gallery_id: saved.id}
      ],
      children: []
    }

    insert_containers(page, user, child)
    entry_blocks = preloaded_entry_blocks(page.id)
    [%{block: %{children: [row]}} | _] = entry_blocks
    row = Brando.Repo.preload(row, [vars: :gallery], force: true)
    [picked_var, cleared_var] = Enum.sort_by(row.vars, &(&1.key != "picked"))
    ops = Ops.from_entry_blocks(entry_blocks)

    vars = [%{"id" => picked_var.id, "gallery_id" => picked.id}, %{"id" => cleared_var.id, "gallery_id" => nil}]
    {:ok, ops} = Ops.apply_op(ops, {:update, "childP", %{"vars" => vars}})

    {:ok, params} = Ops.materialize_child(ops, "childP")
    block_cs = Brando.Content.Block.recursive_block_changeset(row, params, user.id)
    moved_cs = BrandoAdmin.Components.Form.BlockField.moved_child_changeset(block_cs, user.id)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerB", "childP", 0, Ops.block_diff_params(moved_cs)})
    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    assert [%{block: %{children: []}}, %{block: %{children: [moved]}}] = preloaded_entry_blocks(page.id)
    galleries = moved |> Brando.Repo.preload(:vars, force: true) |> Map.get(:vars) |> Map.new(&{&1.key, &1.gallery_id})
    assert galleries == %{"picked" => picked.id, "cleared" => nil}
  end

  # Sol audit: roots are saved in order, so a child moved into an earlier
  # container was inserted before its old row was deleted, and the uid's
  # unique index refused the save.
  test "a child moved into an earlier container saves" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    for {uid, children, seq} <- [
          {"containerA", [], 0},
          {"containerB",
           [
             %{
               uid: "childE",
               type: :module,
               active: true,
               source: "Elixir.Brando.Pages.Page.Blocks",
               creator_id: user.id,
               sequence: 0,
               description: "moving up",
               refs: [
                 %{
                   name: "body",
                   uid: "refE",
                   data: %Brando.Villain.Blocks.TextBlock{data: %Brando.Villain.Blocks.TextBlock.Data{text: "x"}}
                 }
               ],
               children: []
             }
           ], 1}
        ] do
      %Brando.Pages.Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: seq})
      |> Changeset.put_assoc(:block, %{
        uid: uid,
        type: :container,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: seq,
        children: children
      })
      |> Brando.Repo.insert!()
    end

    entry_blocks = preloaded_entry_blocks(page.id)
    [_, %{block: %{children: [row]}}] = entry_blocks
    ops = Ops.from_entry_blocks(entry_blocks)

    {:ok, params} = Ops.materialize_child(ops, "childE")
    block_cs = Brando.Content.Block.recursive_block_changeset(row, params, user.id)
    moved_cs = BrandoAdmin.Components.Form.BlockField.moved_child_changeset(block_cs, user.id)
    {:ok, ops} = Ops.apply_op(ops, {:insert_child, "containerA", "childE", 0, Ops.block_diff_params(moved_cs)})
    assert {:ok, _} = save_from_ops(page, entry_blocks, ops, user)

    assert [%{block: %{children: [moved]}}, %{block: %{children: []}}] = preloaded_entry_blocks(page.id)
    assert {moved.uid, moved.description} == {"childE", "moving up"}
    assert [%{uid: "refE"}] = moved.refs
  end

  test "materialize_child rejects roots and unknown uids" do
    user = Factory.insert(:random_user)
    {page, _} = insert_page_with_containers(user)
    ops = Ops.from_entry_blocks(preloaded_entry_blocks(page.id))

    assert {:error, {:unknown_uid, "containerA"}} = Ops.materialize_child(ops, "containerA")
    assert {:error, {:unknown_uid, "nope"}} = Ops.materialize_child(ops, "nope")
    assert {:ok, _} = Ops.materialize_child(ops, "childC")
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
