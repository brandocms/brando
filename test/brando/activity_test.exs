defmodule Brando.ActivityTest do
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query

  alias Brando.Activity
  alias Brando.Activity.Event
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Revisions

  setup do
    user = Factory.insert(:random_user)
    {:ok, %{user: user}}
  end

  defp events(page) do
    Repo.all(from(e in Event, where: e.schema == ^to_string(Page) and e.entry_id == ^page.id, order_by: [asc: e.id]))
  end

  defp create_page(user, attrs \\ %{}) do
    {:ok, page} =
      Pages.create_page(
        Map.merge(
          %{
            title: "About",
            uri: "about-#{System.unique_integer([:positive])}",
            language: "en",
            template: "default.html",
            status: :draft
          },
          attrs
        ),
        user
      )

    page
  end

  describe "saves" do
    test "creating an entry records who created it, its title and the first revision", %{user: user} do
      page = create_page(user)

      assert [event] = events(page)
      assert event.action == :created
      assert event.source == :admin
      assert event.user_id == user.id
      assert event.title == "About"
      assert event.language == "en"
      assert event.revision == 0
      assert event.details == %{"status" => %{"to" => "draft"}}
    end

    test "an update names the fields that changed and the revision it saved", %{user: user} do
      page = create_page(user)
      {:ok, _} = Pages.update_page(page.id, %{title: "About us", meta_description: "Who we are"}, user)

      assert [_created, event] = events(page)
      assert event.action == :updated
      assert event.fields == ["meta_description", "title"]
      assert event.title == "About us"
      assert event.revision == 1
    end

    test "publishing and unpublishing are their own actions", %{user: user} do
      page = create_page(user)
      {:ok, _} = Pages.update_page(page.id, %{status: :published}, user)
      {:ok, _} = Pages.update_page(page.id, %{status: :draft}, user)

      assert [_, published, unpublished] = events(page)
      assert published.action == :published
      assert published.details == %{"status" => %{"from" => "draft", "to" => "published"}}
      assert unpublished.action == :unpublished
    end

    test "a save that changes nothing records nothing", %{user: user} do
      page = create_page(user)
      {:ok, _} = Pages.update_page(page.id, %{title: "About"}, user)
      assert [_created] = events(page)
    end

    test "a save made as the system has no person", %{user: user} do
      page = create_page(user)
      {:ok, _} = Pages.update_page(page.id, %{title: "Renamed"}, :system)

      assert [_, event] = events(page)
      assert event.source == :system
      assert event.user_id == nil
    end
  end

  describe "trash, restore and duplicate" do
    test "moving to the trash and back", %{user: user} do
      page = create_page(user)
      {:ok, trashed} = Pages.delete_page(page.id, user)
      assert {:ok, _} = Brando.Authorization.Boundary.restore(user, trashed)

      assert [_, trashed_event, restored_event] = events(page)
      assert trashed_event.action == :trashed
      assert trashed_event.user_id == user.id
      assert restored_event.action == :restored

      page_id = page.id
      assert %{^page_id => %Brando.Users.User{id: user_id}} = Activity.trashed_by(Page, [page.id])
      assert user_id == user.id
    end

    test "a duplicate records where it was copied from", %{user: user} do
      page = create_page(user)
      {:ok, copy} = Pages.duplicate_page(page.id, user)

      assert [event] = events(copy)
      assert event.action == :duplicated
      assert event.details["copied_from"] == %{"id" => page.id, "title" => "About"}
    end
  end

  describe "revisions" do
    test "restoring a revision records it and the revision it replaced", %{user: user} do
      page = create_page(user)
      {:ok, _} = Pages.update_page(page.id, %{title: "Second"}, user)
      {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, 0, user)

      event = List.last(events(page))
      assert event.action == :revision_restored
      assert event.revision == 0
      assert event.details == %{"replaced" => 1}
    end

    test "a scheduled revision is published by the scheduler, for the user who scheduled it", %{user: user} do
      page = create_page(user)
      {:ok, _} = Pages.update_page(page.id, %{title: "Second"}, user)

      Activity.with_source(:scheduler, fn ->
        {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, 0, user, publish?: true)
      end)

      event = List.last(events(page))
      assert event.action == :published
      assert event.source == :scheduler
      assert event.user_id == user.id
      assert event.details["scheduled"] == true
    end
  end

  describe "listing actions" do
    test "a status change from the listing", %{user: user} do
      page = create_page(user)
      Brando.Trait.Status.update_status(Page, page.id, "published", user)

      event = List.last(events(page))
      assert event.action == :published
      assert event.user_id == user.id
    end

    test "a reorder is one event for the whole list", %{user: user} do
      first = create_page(user, %{title: "First"})
      second = create_page(user, %{title: "Second"})

      Brando.Trait.Sequenced.sequence(Page, %{"ids" => [second.id, first.id]}, nil, user: user)

      assert [event] = Activity.list(%{action: :reordered})
      assert event.schema == to_string(Page)
      assert event.entry_id == nil
      assert event.user_id == user.id
      assert event.details == %{"count" => 2, "first" => "Second"}
    end
  end

  describe "what is not logged" do
    test "media and internal records" do
      refute Activity.logged?(Brando.Images.Image)
      refute Activity.logged?(Brando.Content.Block)
      refute Activity.logged?(Brando.Revisions.Revision)
      assert Activity.logged?(Page)
    end

    test "bookkeeping fields alone are not an edit" do
      changeset = Ecto.Changeset.change(%Page{}, updated_at: DateTime.utc_now(), rendered_blocks: "<p>")
      assert Activity.changed_fields(changeset) == []
    end

    test "block fields go by their field name" do
      changeset = %Ecto.Changeset{changes: %{entry_blocks: [], title: "x"}}
      assert Activity.changed_fields(changeset) == ["blocks", "title"]
    end
  end

  test "an event that can't be written leaves the surrounding transaction usable", %{user: user} do
    page = Factory.insert(:page, creator: user)
    put_test_env(:tenancy_mode, :multi)
    Ecto.Adapters.SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "tenant_activity_unmigrated"))

    # Like a site that hasn't run the migration yet: the table isn't there.
    assert {:ok, :still_working} =
             Repo.transaction(fn ->
               assert {:error, _} =
                        Brando.Tenant.with_prefix("tenant_activity_unmigrated", fn ->
                          Activity.record(:updated, page, user)
                        end)

               Repo.one!(from(p in Page, where: p.id == ^page.id, select: count()), prefix: "public")
               :still_working
             end)
  end

  test "handing a user's content to someone else leaves what they did in the log", %{user: user} do
    page = create_page(user)
    other = Factory.insert(:random_user)

    refute Enum.any?(Brando.Users.get_user_content_summary(user.id), &(&1.table == "activity_events"))
    {:ok, _} = Brando.Users.transfer_user_content(user.id, other.id)

    assert [%{user_id: user_id}] = events(page)
    assert user_id == user.id
  end

  describe "reading" do
    test "filters by person, action and title", %{user: user} do
      other = Factory.insert(:random_user)
      create_page(user, %{title: "Sommerro"})
      create_page(other, %{title: "Villa Tide"})

      assert [%{title: "Villa Tide"}] = Activity.list(%{user_id: other.id})
      assert [%{title: "Sommerro"}] = Activity.list(%{q: "sommer"})
      assert Activity.count(%{action: :created}) == 2
      assert [] = Activity.list(%{action: :deleted})
    end

    test "purge removes events past the retention period", %{user: user} do
      page = create_page(user)
      [event] = events(page)

      event
      |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -400 * 86_400, :second))
      |> Repo.update!()

      assert Activity.purge(365) == 1
      assert events(page) == []
    end
  end
end
