defmodule Brando.Revisions.RevisionsTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Revisions
  alias Brando.Revisions.Revision
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    {:ok, %{user: user}}
  end

  test "create_revision", %{user: user} do
    s1a = %Page{
      title: "My title!",
      alternate_entries: [],
      alternates: [],
      children: [],
      entry_blocks: [],
      fragments: [],
      parent: nil,
      meta_image: nil,
      updated_by: nil,
      vars: []
    }

    p1 = Brando.repo().insert!(s1a)
    {:ok, r1} = Revisions.create_revision(p1, user)

    p2 =
      p1
      |> Ecto.Changeset.change(title: "New title")
      |> Brando.repo().update!()

    {:ok, r2} = Revisions.create_revision(p2, user)

    refute r1 == r2
    assert r1.revision == 0
    assert r2.revision == 1
    refute r1.encoded_entry == r2.encoded_entry

    assert :erlang.binary_to_term(r1.encoded_entry) == p1
    assert :erlang.binary_to_term(r2.encoded_entry) == p2
  end

  test "captures the supplied unsaved state without reloading scalar fields", %{user: user} do
    page = Factory.insert(:page, creator: user)
    draft = %{page | title: "Unsaved editor title"}

    assert {:ok, revision} = Revisions.create_revision(draft, user, false)
    assert {:ok, {^revision, {0, snapshot}}} = Revisions.get_revision(Page, page.id, 0)
    assert snapshot.title == "Unsaved editor title"
    assert Brando.Repo.get!(Page, page.id).title == page.title

    assert {:ok, [metadata]} = Revisions.list_revision_metadata(Page, page.id)
    assert metadata.encoded_entry == nil
    assert metadata.creator.avatar.id == user.avatar.id
  end

  test "the form's manual revision path captures its unsaved working copy", %{user: user} do
    page =
      :page
      |> Factory.insert(creator: user)
      |> Brando.Repo.preload(Brando.Blueprint.preloads_for(Page))

    form_blueprint = Page.__form__()
    changeset = Page.changeset(page, %{title: "Manual working copy"}, user)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        block_changesets: Map.new(form_blueprint.blocks, &{&1.name, []}),
        current_user: user,
        form: Phoenix.Component.to_form(changeset, as: :page),
        form_blueprint: form_blueprint,
        id: "page-form",
        schema: Page,
        transformer_changesets: %{}
      }
    }

    BrandoAdmin.Components.Form.event_tag_received(socket, :store_revision)

    assert {:ok, {_revision, {0, snapshot}}} = Revisions.get_revision(Page, page.id, 0)
    assert snapshot.title == "Manual working copy"
    assert Brando.Repo.get!(Page, page.id).title == page.title
  end

  test "system revisions do not require a creator", %{user: user} do
    page = Factory.insert(:page, creator: user)

    assert {:ok, revision} = Revisions.create_revision(page, :system, false)
    assert revision.creator_id == nil

    assert {:ok, [metadata]} = Revisions.list_revision_metadata(Page, to_string(page.id))
    assert metadata.encoded_entry == nil
    assert metadata.creator == nil
  end

  test "keeps exactly one active revision and enforces retention flags", %{user: user} do
    page = Factory.insert(:page, creator: user)

    assert {:ok, first} = Revisions.create_revision(page, user)
    assert {:ok, second} = Revisions.create_revision(%{page | title: "Second"}, user)

    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, page.id)
    assert Enum.count(revisions, & &1.active) == 1
    assert Enum.find(revisions, & &1.active).revision == second.revision
    assert {0, _} = Revisions.delete_revision(Page, page.id, second.revision)

    assert {1, _} = Revisions.protect_revision(Page, page.id, first.revision, true)
    assert {0, _} = Revisions.delete_revision(Page, page.id, first.revision)
    assert {1, _} = Revisions.protect_revision(Page, page.id, first.revision, false)
    assert {1, _} = Revisions.mark_revision_scheduled(Page, page.id, first.revision, true)
    assert {0, _} = Revisions.delete_revision(Page, page.id, first.revision)
    assert {0, _} = Revisions.purge_revisions(Page, page.id)
  end

  test "get_last_revision", %{user: user} do
    s1a = %Page{title: "My title!"}
    s1b = %{s1a | title: "A new title!"}

    p1 = Brando.repo().insert!(s1a)
    p2 = Brando.repo().insert!(s1b)

    {:ok, _} = Revisions.create_revision(p1, user)
    {:ok, r2} = Revisions.create_revision(p2, user)

    {:ok, {last_revision, {_, _}}} = Revisions.get_last_revision(Page, p2.id)
    assert last_revision.revision == r2.revision
  end

  test "set", %{user: user} do
    {:ok, p1} = Pages.create_page(Factory.params_for(:page, vars: []), user)
    {:ok, p2} = Pages.update_page(p1.id, %{title: "Title no. 2"}, user)
    {:ok, p3} = Pages.update_page(p2.id, %{title: "Title no. 3"}, user)

    assert p3.title == "Title no. 3"

    assert {:ok, _restored_page} = Revisions.set_entry_to_revision(Page, p1.id, 1, user)
    {:ok, p4} = Pages.get_page(%{matches: %{id: p3.id}})
    assert p4.title == "Title no. 2"

    assert {:ok, identifier} = Brando.Content.get_identifier(Page, p4)
    assert identifier.title == "Title no. 2"
  end

  describe "the trash is not content" do
    # Page obfuscates `uri` in the trash (`trait :soft_delete, obfuscated_fields: [:uri]`).
    setup %{user: user} do
      {:ok, page} = Pages.create_page(Factory.params_for(:page, vars: [], uri: "kulturkalender"), user)
      %{page: page}
    end

    test "a revision taken in the trash restores its content, not the trash", %{user: user, page: page} do
      {:ok, trashed} = Brando.Repo.soft_delete(page)
      assert trashed.uri =~ "$$$"
      {:ok, revision} = Revisions.create_revision(%{trashed | title: "Fra papirkurven"}, user, false)

      {:ok, _} = Brando.Repo.restore(Brando.Repo.get!(Page, page.id))
      assert {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

      restored = Brando.Repo.get!(Page, page.id)
      assert restored.title == "Fra papirkurven"
      assert restored.deleted_at == nil
      assert restored.uri == "kulturkalender"
    end

    test "a revision restored in the trash leaves the entry there", %{user: user, page: page} do
      {:ok, revision} = Revisions.create_revision(%{page | title: "Før papirkurven"}, user, false)
      {:ok, trashed} = Brando.Repo.soft_delete(page)

      assert {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

      restored = Brando.Repo.get!(Page, page.id)
      assert restored.title == "Før papirkurven"
      assert restored.deleted_at == trashed.deleted_at
      assert restored.uri == trashed.uri
    end

    test "an obfuscated field outside the trash is content", %{user: user, page: page} do
      {:ok, revision} = Revisions.create_revision(page, user, false)
      {:ok, _} = Pages.update_page(page.id, %{uri: "ny-adresse"}, user)

      assert {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)
      assert Brando.Repo.get!(Page, page.id).uri == "kulturkalender"
    end

    test "a working copy from a revision taken in the trash carries neither", %{user: user, page: page} do
      {:ok, trashed} = Brando.Repo.soft_delete(page)
      {:ok, revision} = Revisions.create_revision(trashed, user, false)
      {:ok, {_, {_, snapshot}}} = Revisions.get_revision(Page, page.id, revision.revision)

      params = Revisions.restore_params(snapshot, Brando.Repo.restore!(trashed))
      refute Map.has_key?(params, :deleted_at)
      refute Map.has_key?(params, :uri)
    end
  end

  test "restores nested block content", %{user: user} do
    page = Factory.insert(:page, creator: user)

    entry_block =
      %Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "revision-container",
        type: :container,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        description: "Original block content",
        children: []
      })
      |> Brando.Repo.insert!()

    assert {:ok, original_revision} = Revisions.create_revision(page, user)

    entry_block.block
    |> Changeset.change(description: "Changed block content")
    |> Brando.Repo.update!()

    assert {:ok, _changed_revision} = Revisions.create_revision(page, user)

    assert {:ok, _restored_page} =
             Revisions.set_entry_to_revision(Page, page.id, original_revision.revision, user)

    restored_entry_block =
      Page.Blocks
      |> Brando.Repo.get!(entry_block.id)
      |> Brando.Repo.preload(:block)

    assert restored_entry_block.block.description == "Original block content"
  end

  test "recreates blocks that were deleted after the target revision", %{user: user} do
    page = Factory.insert(:page, creator: user)

    entry_block =
      %Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "deleted-revision-container",
        type: :container,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        description: "Restore this deleted block",
        children: []
      })
      |> Brando.Repo.insert!()

    assert {:ok, original_revision} = Revisions.create_revision(page, user)
    Brando.Repo.delete!(entry_block)
    assert {:ok, _without_block_revision} = Revisions.create_revision(page, user)

    assert {:ok, _restored_page} =
             Revisions.set_entry_to_revision(Page, page.id, original_revision.revision, user)

    restored_blocks =
      from(entry_block in Page.Blocks, where: entry_block.entry_id == ^page.id)
      |> Brando.Repo.all()
      |> Brando.Repo.preload(:block)

    assert [%{block: %{description: "Restore this deleted block"}}] = restored_blocks
  end

  test "recreates nested child blocks deleted after the target revision", %{user: user} do
    page = Factory.insert(:page, creator: user)

    entry_block =
      %Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "revision-parent",
        type: :container,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        children: [
          %{
            uid: "revision-child",
            type: :container,
            active: true,
            source: "Elixir.Brando.Pages.Page.Blocks",
            creator_id: user.id,
            sequence: 0,
            description: "Restore this child",
            children: []
          }
        ]
      })
      |> Brando.Repo.insert!()

    assert {:ok, original_revision} = Revisions.create_revision(page, user)
    [child] = entry_block.block.children
    Brando.Repo.delete!(child)
    assert {:ok, _without_child_revision} = Revisions.create_revision(page, user)

    assert {:ok, _restored_page} =
             Revisions.set_entry_to_revision(Page, page.id, original_revision.revision, user)

    restored_entry_block =
      Page.Blocks
      |> Brando.Repo.get!(entry_block.id)
      |> Brando.Repo.preload(block: [children: &Brando.Content.Blocks.preload_child_trees/1])

    assert [%{description: "Restore this child"}] = restored_entry_block.block.children
  end

  # A child that moved to another container after the revision (the
  # outline saves a move as a new row, the same uid) goes back where the
  # revision had it, as the revision had it: its content and module
  # version, and the sync uid it keeps throughout. A child deleted since
  # comes back the same way; one added since goes.
  describe "restoring blocks moved, deleted and added since" do
    defp restore_block(user, uid, description, children \\ []),
      do: %{
        uid: uid,
        type: if(children == [], do: :module, else: :container),
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        description: description,
        children: Enum.with_index(children, &Map.put(&1, :sequence, &2))
      }

    defp restore_roots!(page, roots) do
      for {block, n} <- Enum.with_index(roots) do
        %Page.Blocks{}
        |> Changeset.change(%{entry_id: page.id, sequence: n})
        |> Changeset.put_assoc(:block, Map.put(block, :sequence, n))
        |> Brando.Repo.insert!()
      end
    end

    defp restore_row(uid),
      do: Brando.Repo.get_by!(Brando.Content.Block, uid: uid) |> Brando.Repo.preload(:parent)

    defp restore_stamp!(uid, fields) do
      import Ecto.Query, only: [from: 2]
      Brando.Repo.update_all(from(b in Brando.Content.Block, where: b.uid == ^uid), set: fields)
    end

    # each root's uid with its children's, as the entry has them now
    defp restore_tree(page) do
      import Ecto.Query, only: [from: 2]

      Page.Blocks
      |> Brando.Repo.all()
      |> Enum.filter(&(&1.entry_id == page.id))
      |> Enum.sort_by(& &1.sequence)
      |> Brando.Repo.preload(block: [children: &Brando.Content.Blocks.preload_child_trees/1])
      |> Enum.map(&restore_subtree(&1.block))
    end

    defp restore_subtree(block),
      do: {block.uid, block.children |> Enum.sort_by(& &1.sequence) |> Enum.map(&restore_subtree/1)}

    test "puts them back as the revision had them", %{user: user} do
      page = Factory.insert(:page, creator: user)

      restore_roots!(page, [
        restore_block(user, "boxA", nil, [
          restore_block(user, "keepA", "Stays in A"),
          restore_block(user, "moved", "As in the revision"),
          restore_block(user, "gone", "Deleted since")
        ]),
        restore_block(user, "boxB", nil, [restore_block(user, "keepB", "Stays in B")])
      ])

      restore_stamp!("moved", sync_uid: "moved-sync", module_version: 3)
      restore_stamp!("gone", sync_uid: "gone-sync", module_version: 2)
      restore_stamp!("keepA", module_version: 1)
      restore_stamp!("keepB", module_version: 1)
      saved = restore_tree(page)
      assert {:ok, revision} = Revisions.create_revision(page, user)

      # since: moved to the top of B (a new row), edited, its module
      # migrated; another child deleted and one added
      moved = restore_row("moved")
      Brando.Repo.delete!(moved)
      Brando.Repo.delete!(restore_row("gone"))
      [%{block: box_b}] = Enum.filter(Brando.Repo.all(Page.Blocks), &(&1.sequence == 1)) |> Brando.Repo.preload(:block)

      for {uid, description, seq, parent} <- [
            {"moved", "Moved on", 0, box_b},
            {"added", "Added since", 1, restore_row("boxA")}
          ] do
        user
        |> restore_block(uid, description)
        |> Map.merge(%{parent_id: parent.id, sequence: seq})
        |> then(&struct(Brando.Content.Block, &1))
        |> Brando.Repo.insert!()
      end

      restore_stamp!("keepB", sequence: 1, description: "Edited since", module_version: 2)
      restore_stamp!("moved", sync_uid: "moved-sync", module_version: 4)
      # a module change that left its content as it was
      restore_stamp!("keepA", module_version: 2)
      assert restore_tree(page) != saved

      assert {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

      assert restore_tree(page) == saved
      moved = restore_row("moved")
      assert {moved.description, moved.sync_uid, moved.module_version} == {"As in the revision", "moved-sync", 3}
      gone = restore_row("gone")
      assert {gone.description, gone.sync_uid, gone.module_version} == {"Deleted since", "gone-sync", 2}
      # the restore did not change it
      assert restore_row("keepA").module_version == 2
      # it wrote the revision's content to this one
      assert {restore_row("keepB").description, restore_row("keepB").module_version} == {"Stays in B", 1}
    end
  end

  # Sol audit: a table row deleted since came back with a new sync uid, so
  # its translation no longer matched it.
  test "a table row deleted since comes back with its sync uid", %{user: user} do
    page = Factory.insert(:page, creator: user)

    rows = fn uid ->
      [%{sequence: 0, sync_uid: "#{uid}-kept", vars: []}, %{sequence: 1, sync_uid: "#{uid}-gone", vars: []}]
    end

    blocks =
      for uid <- ["inPlace", "moved"] do
        %{
          uid: uid,
          type: :module,
          active: true,
          source: "Elixir.Brando.Pages.Page.Blocks",
          creator_id: user.id,
          table_rows: rows.(uid),
          children: []
        }
      end

    for {uid, children, n} <- [{"boxA", blocks, 0}, {"boxB", [], 1}] do
      %Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: n})
      |> Changeset.put_assoc(:block, %{
        uid: uid,
        type: :container,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: n,
        children: Enum.with_index(children, &Map.put(&1, :sequence, &2))
      })
      |> Brando.Repo.insert!()
    end

    assert {:ok, revision} = Revisions.create_revision(page, user)

    import Ecto.Query, only: [from: 2]
    Brando.Repo.delete_all(from(r in Brando.Content.TableRow, where: r.sync_uid in ["inPlace-gone", "moved-gone"]))

    # moved to B since, as the outline saves a move: a new row
    moved = Brando.Repo.get_by!(Brando.Content.Block, uid: "moved") |> Brando.Repo.preload(:table_rows)
    box_b = Brando.Repo.get_by!(Brando.Content.Block, uid: "boxB")
    Brando.Repo.delete!(moved)

    %Brando.Content.Block{}
    |> Changeset.change(%{uid: "moved", sync_uid: moved.sync_uid, type: :module, active: true, parent_id: box_b.id})
    |> Changeset.change(%{source: Brando.Pages.Page.Blocks, creator_id: user.id, sequence: 0})
    |> Changeset.put_assoc(:table_rows, [%{sequence: 0, sync_uid: "moved-kept", vars: []}])
    |> Brando.Repo.insert!()

    assert {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

    for uid <- ["inPlace", "moved"] do
      block = Brando.Repo.get_by!(Brando.Content.Block, uid: uid) |> Brando.Repo.preload([:parent, :table_rows])
      assert block.parent.uid == "boxA"
      assert block.table_rows |> Enum.sort_by(& &1.sequence) |> Enum.map(& &1.sync_uid) == ["#{uid}-kept", "#{uid}-gone"]
    end
  end

  test "returns an error for a corrupt snapshot without changing the entry", %{user: user} do
    page = Factory.insert(:page, creator: user)
    assert {:ok, revision} = Revisions.create_revision(page, user)

    corrupt = <<0, 1, 2>>

    from(r in Revision,
      where: r.entry_type == ^to_string(Page) and r.entry_id == ^page.id,
      update: [set: [encoded_entry: ^corrupt]]
    )
    |> Brando.Repo.update_all([])

    assert {:error, {:revision, :invalid_snapshot}} =
             Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

    assert Brando.Repo.get!(Page, page.id).title == page.title
  end

  test "rejects a revision blob belonging to another entry", %{user: user} do
    page = Factory.insert(:page, creator: user, title: "Original entry")
    other_page = Factory.insert(:page, creator: user, title: "Other entry")
    assert {:ok, revision} = Revisions.create_revision(page, user)

    from(r in Revision,
      where: r.entry_type == ^to_string(Page) and r.entry_id == ^page.id,
      update: [set: [encoded_entry: ^Brando.Utils.term_to_binary(other_page)]]
    )
    |> Brando.Repo.update_all([])

    assert {:error, {:revision, :invalid_snapshot}} =
             Revisions.get_revision(Page, page.id, revision.revision)

    assert {:error, {:revision, :invalid_snapshot}} =
             Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

    assert Brando.Repo.get!(Page, page.id).title == "Original entry"
  end

  test "scheduled revisions are retained, cancellable, and publish as active", %{user: user} do
    {:ok, original} =
      Pages.create_page(Factory.params_for(:page, title: "Scheduled original", vars: []), user)

    {:ok, changed} = Pages.update_page(original.id, %{title: "Current title"}, user)
    publish_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    assert {:ok, _job} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Revisions.get_revision(Page, changed.id, 0)
               |> schedule_revision(publish_at, user)
             end)

    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, changed.id)
    assert Enum.find(revisions, &(&1.revision == 0)).scheduled
    assert {0, _} = Revisions.purge_revisions(Page, changed.id)

    assert :ok = Brando.Publisher.cancel_scheduled_revision(Page, changed.id, 0)
    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, changed.id)
    refute Enum.find(revisions, &(&1.revision == 0)).scheduled

    job = %Oban.Job{
      args: %{
        "schema" => to_string(Page),
        "id" => changed.id,
        "revision" => 0,
        "user_id" => user.id
      }
    }

    assert {:ok, published} = Brando.Worker.EntryPublisher.perform(job)
    assert published.title == "Scheduled original"
    assert published.status == :published

    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, changed.id)
    assert Enum.find(revisions, &(&1.revision == 0)).active
    assert Enum.count(revisions, & &1.active) == 1
  end

  # Nothing surprising after a restore: the schedule is dropped, with a note
  # in Activity, and an editor can schedule the revision again.
  test "a scheduled revision due while its entry is in the trash is cancelled, with a note", %{user: user} do
    {:ok, original} = Pages.create_page(Factory.params_for(:page, vars: [], status: :draft), user)
    {:ok, changed} = Pages.update_page(original.id, %{title: "Current title"}, user)
    assert {_, _} = Revisions.mark_revision_scheduled(Page, changed.id, 0, true)
    {:ok, trashed} = Brando.Repo.soft_delete(changed)
    job = %Oban.Job{args: %{"schema" => to_string(Page), "id" => changed.id, "revision" => 0, "user_id" => user.id}}

    assert {:cancel, :in_trash} = Brando.Worker.EntryPublisher.perform(job)

    page = Brando.Repo.get!(Page, changed.id)
    assert page.title == "Current title"
    assert page.status == :draft
    assert page.deleted_at
    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, changed.id)
    revision = Enum.find(revisions, &(&1.revision == 0))
    refute revision.active
    refute revision.scheduled

    import Ecto.Query, only: [from: 2]

    assert %{
             source: :scheduler,
             user_id: user_id,
             revision: 0,
             details: %{"scheduled_revision" => %{"reason" => "in_trash"}}
           } =
             Brando.Repo.one!(
               from(e in Brando.Activity.Event,
                 where: e.schema == ^to_string(Page) and e.entry_id == ^changed.id and e.action == :updated,
                 order_by: [desc: e.id],
                 limit: 1
               )
             )

    assert user_id == user.id

    # restored, the page is as it was: nothing is published behind the editor's back
    {:ok, _} = Brando.Repo.restore(trashed)
    page = Brando.Repo.get!(Page, changed.id)
    assert page.title == "Current title"
    assert page.status == :draft
  end

  # The job's cleanup runs after the refusal released the lock: by then the
  # entry may be restored and the revision scheduled again, by a new job.
  test "dropping a schedule in the trash leaves one made since alone", %{user: user} do
    {:ok, page} = Pages.create_page(Factory.params_for(:page, vars: [], status: :draft), user)
    {:ok, page} = Pages.update_page(page.id, %{title: "Current title"}, user)

    scheduled? = fn ->
      Enum.find(elem(Revisions.list_revision_metadata(Page, page.id), 1), &(&1.revision == 0)).scheduled
    end

    activity = fn ->
      Brando.Activity.for_entry(Page, page.id) |> Enum.count(&(&1.details["scheduled_revision"] != nil))
    end

    Revisions.mark_revision_scheduled(Page, page.id, 0, true)
    {:ok, trashed} = Brando.Repo.soft_delete(page)

    # another job is the revision's schedule now
    assert :ok = Revisions.drop_schedule_in_trash(Page, page.id, 0, user, fn -> false end)
    assert scheduled?.()
    assert activity.() == 0

    # restored since, but not scheduled again: the refused job was the
    # schedule, so it goes, or the revision would stay scheduled with no job
    {:ok, _} = Brando.Repo.restore(trashed)
    assert :ok = Revisions.drop_schedule_in_trash(Page, page.id, 0, user, fn -> true end)
    refute scheduled?.()
    assert activity.() == 1
  end

  # Checked under the entry's lock, so an entry trashed while the job starts
  # is not published either.
  test "publishing a revision of an entry in the trash is refused, changing nothing", %{user: user} do
    {:ok, original} = Pages.create_page(Factory.params_for(:page, vars: [], status: :draft), user)
    {:ok, changed} = Pages.update_page(original.id, %{title: "Current title"}, user)
    {:ok, _} = Brando.Repo.soft_delete(changed)

    assert {:error, :in_trash} = Revisions.set_entry_to_revision(Page, changed.id, 0, user, publish?: true)

    page = Brando.Repo.get!(Page, changed.id)
    assert page.title == "Current title"
    assert page.status == :draft
    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, changed.id)
    refute Enum.find(revisions, &(&1.revision == 0)).active
  end

  test "manual activation cancels the revision's pending publishing job", %{user: user} do
    {:ok, original} = Pages.create_page(Factory.params_for(:page, vars: []), user)
    {:ok, changed} = Pages.update_page(original.id, %{title: "Later title"}, user)
    publish_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    assert {:ok, scheduled_job} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Brando.Publisher.schedule_revision(Page, changed.id, 0, publish_at, user)
             end)

    assert {:ok, restored} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Revisions.set_entry_to_revision(Page, changed.id, 0, user)
             end)

    assert restored.title == original.title
    assert Brando.Repo.get!(Oban.Job, scheduled_job.id).state == "cancelled"

    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, changed.id)
    refute Enum.find(revisions, &(&1.revision == 0)).scheduled
  end

  test "deleting a publisher job releases its revision from retention", %{user: user} do
    {:ok, original} = Pages.create_page(Factory.params_for(:page, vars: []), user)
    {:ok, changed} = Pages.update_page(original.id, %{title: "Later title"}, user)
    publish_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    assert {:ok, scheduled_job} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Brando.Publisher.schedule_revision(Page, changed.id, 0, publish_at, user)
             end)

    assert {1, _} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Brando.Publisher.delete_job(scheduled_job.id)
             end)

    refute Brando.Repo.get(Oban.Job, scheduled_job.id)
    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, changed.id)
    refute Enum.find(revisions, &(&1.revision == 0)).scheduled
  end

  test "a terminal publisher failure releases its revision from retention", %{user: user} do
    {:ok, original} = Pages.create_page(Factory.params_for(:page, vars: []), user)
    {:ok, changed} = Pages.update_page(original.id, %{title: "Later title"}, user)
    assert {1, _} = Revisions.mark_revision_scheduled(Page, changed.id, 0, true)

    corrupt = <<0, 1, 2>>

    from(r in Revision,
      where: r.entry_type == ^to_string(Page) and r.entry_id == ^changed.id and r.revision == 0,
      update: [set: [encoded_entry: ^corrupt]]
    )
    |> Brando.Repo.update_all([])

    job = %Oban.Job{
      attempt: 10,
      max_attempts: 10,
      args: %{
        "schema" => to_string(Page),
        "id" => changed.id,
        "revision" => 0,
        "user_id" => user.id
      }
    }

    assert {:error, {:revision, :invalid_snapshot}} = Brando.Worker.EntryPublisher.perform(job)
    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, changed.id)
    refute Enum.find(revisions, &(&1.revision == 0)).scheduled
  end

  defp schedule_revision({:ok, {_revision, {revision_number, snapshot}}}, publish_at, user) do
    Brando.Publisher.schedule_revision(snapshot.__struct__, snapshot.id, revision_number, publish_at, user)
  end
end
