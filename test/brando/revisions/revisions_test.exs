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

  test "returns an error for a corrupt snapshot without changing the entry", %{user: user} do
    page = Factory.insert(:page, creator: user)
    assert {:ok, revision} = Revisions.create_revision(page, user)

    from(r in Revision,
      where: r.entry_type == ^to_string(Page) and r.entry_id == ^page.id,
      update: [set: [encoded_entry: <<0, 1, 2>>]]
    )
    |> Brando.Repo.update_all([])

    assert {:error, {:revision, :invalid_snapshot}} =
             Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

    assert Brando.Repo.get!(Page, page.id).title == page.title
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

    from(r in Revision,
      where: r.entry_type == ^to_string(Page) and r.entry_id == ^changed.id and r.revision == 0,
      update: [set: [encoded_entry: <<0, 1, 2>>]]
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
