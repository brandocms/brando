defmodule Brando.ContentEventsTest do
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity
  alias Brando.ContentEvents
  alias Brando.ContentEvents.Event
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Revisions
  alias Brando.Worker.ContentEventDispatcher

  # Receives every event in the test process: with Oban's inline testing
  # mode the dispatcher runs in the process that saved.
  defmodule Collector do
    @behaviour Brando.ContentEvents.Subscriber
    def handle_event(event), do: send(self(), {:collected, event})
  end

  defmodule Exploding do
    @behaviour Brando.ContentEvents.Subscriber
    def handle_event(_event), do: raise("subscriber broke")
  end

  setup do
    put_test_env(Brando.ContentEvents, subscribers: [Collector], debounce_seconds: 0)
    {:ok, %{user: Factory.insert(:random_user)}}
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

  defp collected do
    receive do
      {:collected, event} -> [event | collected()]
    after
      0 -> []
    end
  end

  defp types(events), do: Enum.map(events, & &1.type)

  describe "derived from Activity" do
    test "creating an entry: entry.created with what the event carries", %{user: user} do
      page = create_page(user)

      assert [%Event{} = event] = collected()
      assert event.type == "entry.created"
      assert event.entry_id == page.id
      assert event.schema == Page
      assert event.entry_type == "pages.page"
      assert event.language == "en"
      assert event.status == "draft"
      assert event.actor == "person"
      assert "title" in event.changed_fields
      assert event.url =~ page.uri
      assert String.starts_with?(event.url, "http")
      assert %DateTime{} = event.occurred_at
      assert {:ok, _} = Ecto.UUID.cast(event.id)
      # No tenancy: the site is the application, without an environment
      assert is_binary(event.site)
      assert event.environment == nil
    end

    test "creating a published entry is also entry.published", %{user: user} do
      create_page(user, %{status: :published})
      assert types(collected()) == ["entry.created", "entry.published"]
    end

    test "an update names the changed fields, never their values", %{user: user} do
      page = create_page(user)
      collected()
      {:ok, _} = Pages.update_page(page.id, %{title: "Secret plans", meta_description: "Hush"}, user)

      assert [event] = collected()
      assert event.type == "entry.updated"
      assert event.changed_fields == ["meta_description", "title"]
      refute inspect(event) =~ "Secret plans"
    end

    test "publishing and unpublishing", %{user: user} do
      page = create_page(user)
      collected()
      {:ok, _} = Pages.update_page(page.id, %{status: :published}, user)
      {:ok, _} = Pages.update_page(page.id, %{status: :draft}, user)

      assert [published, unpublished] = collected()
      assert published.type == "entry.published"
      assert published.status == "published"
      assert unpublished.type == "entry.unpublished"
      assert unpublished.status == "draft"
    end

    test "a status change from the listing", %{user: user} do
      page = create_page(user)
      collected()
      Brando.Trait.Status.update_status(Page, page.id, "published", user)
      assert types(collected()) == ["entry.published"]
    end

    test "trash, restore, and emptying the trash", %{user: user} do
      page = create_page(user)
      collected()
      {:ok, trashed} = Pages.delete_page(page.id, user)
      assert [deleted] = collected()
      assert deleted.type == "entry.deleted"
      assert deleted.url =~ page.uri

      {:ok, _} = Brando.Authorization.Boundary.restore(user, trashed)
      assert types(collected()) == ["entry.restored"]

      # The trash purge records `deleted` with "purged": already announced
      Activity.deleted(page, :system, false, %{"purged" => true})
      assert collected() == []
    end

    test "a duplicate is entry.created", %{user: user} do
      page = create_page(user)
      collected()
      {:ok, copy} = Pages.duplicate_page(page.id, user)
      assert [event] = collected()
      assert event.type == "entry.created"
      assert event.entry_id == copy.id
    end

    test "restoring a revision is entry.updated", %{user: user} do
      page = create_page(user)
      {:ok, _} = Pages.update_page(page.id, %{title: "Second"}, user)
      collected()
      {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, 0, user)
      assert types(collected()) == ["entry.updated"]
    end

    test "scheduled publishing fires entry.published like a manual publish, from the scheduler", %{user: user} do
      page = create_page(user)
      # Waiting to be published, as scheduling leaves it
      Brando.Repo.update_all(Ecto.Query.from(p in Page, where: p.id == ^page.id), set: [status: :pending])
      collected()

      assert :ok =
               perform_job(Brando.Worker.EntryPublisher, %{
                 "schema" => to_string(Page),
                 "id" => page.id,
                 "status" => "published",
                 "user_id" => user.id
               })

      assert [event] = collected()
      assert event.type == "entry.published"
      assert event.actor == "scheduler"
      assert event.status == "published"
    end

    test "a scheduled revision fires entry.published", %{user: user} do
      page = create_page(user)
      {:ok, _} = Pages.update_page(page.id, %{title: "Second"}, user)
      collected()

      Activity.with_source(:scheduler, fn ->
        {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, 0, user, publish?: true)
      end)

      assert [%{type: "entry.published", actor: "scheduler"}] = collected()
    end

    test "the actor kind follows the source", %{user: user} do
      page = create_page(user)
      collected()

      Activity.with_source(:assistant, fn -> Pages.update_page(page.id, %{title: "A"}, user) end)
      Activity.with_source(:mcp, %{"client" => "Claude Code"}, fn -> Pages.update_page(page.id, %{title: "B"}, user) end)
      Pages.update_page(page.id, %{title: "C"}, :system)

      assert Enum.map(collected(), & &1.actor) == ["assistant", "mcp", "system"]
    end

    test "users and Activity's ignored schemas send nothing", %{user: user} do
      {:ok, _} = Brando.Users.update_user(user.id, %{name: "Renamed"}, user)
      assert collected() == []
    end

    test "nothing is queued when events are turned off", %{user: user} do
      put_test_env(Brando.ContentEvents, enabled: false, subscribers: [Collector])
      create_page(user)
      assert collected() == []
    end
  end

  describe "subscribers" do
    test "one that fails makes the job run again, after the others had it", %{user: user} do
      put_test_env(Brando.ContentEvents, subscribers: [Exploding, Collector], debounce_seconds: 0)

      Oban.Testing.with_testing_mode(:manual, fn ->
        create_page(user)
        [job] = all_enqueued(worker: ContentEventDispatcher)

        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, message} = perform_job(ContentEventDispatcher, job.args)
          assert message =~ "Exploding"
        end)

        assert [%Event{type: "entry.created", id: id}] = collected()

        # Again: the same event, the same id
        ExUnit.CaptureLog.capture_log(fn -> perform_job(ContentEventDispatcher, job.args) end)
        assert [%Event{id: ^id}] = collected()
      end)
    end

    test "one that raises does not stop the others, or the save", %{user: user} do
      put_test_env(Brando.ContentEvents, subscribers: [Exploding, Collector], debounce_seconds: 0)

      ExUnit.CaptureLog.capture_log(fn ->
        assert %Page{} = create_page(user)
      end) =~ "subscriber broke"

      assert ["entry.created"] = types(collected())
    end

    test "PubSub listeners get the event after the subscribers", %{user: user} do
      :ok = ContentEvents.subscribe()
      page = create_page(user)
      assert_receive {:content_event, %Event{type: "entry.created", entry_id: id}}
      assert id == page.id
    end

    test "Brando's webhooks are subscribed unless turned off" do
      assert Brando.Webhooks in ContentEvents.subscribers()
      put_test_env(Brando.Webhooks, enabled: false)
      refute Brando.Webhooks in ContentEvents.subscribers()
    end
  end

  describe "delivery after commit" do
    test "a save that rolls back sends nothing", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        Brando.Repo.transaction(fn ->
          create_page(user)
          Brando.Repo.rollback(:changed_my_mind)
        end)

        refute_enqueued(worker: ContentEventDispatcher)
      end)
    end

    test "a failed enqueue leaves the save's transaction usable", %{user: user} do
      put_test_env(Brando.ContentEvents, subscribers: [Collector], debounce_seconds: 5)

      Oban.Testing.with_testing_mode(:manual, fn ->
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %Page{} = page} =
                   Brando.Repo.transaction(fn ->
                     # Like a save under group authorization, when queueing the event fails
                     Brando.Repo.repo().query!(
                       "ALTER TABLE public.oban_jobs ADD CONSTRAINT no_content_events CHECK (worker <> 'Brando.Worker.ContentEventDispatcher') NOT VALID"
                     )

                     page = create_page(user)
                     {:ok, _} = Pages.update_page(page.id, %{title: "Changed"}, user)
                     Brando.Repo.repo().query!("ALTER TABLE public.oban_jobs DROP CONSTRAINT no_content_events")
                     page
                   end)

          assert Brando.Repo.get(Page, page.id).title == "Changed"
        end)

        # The events were not queued, and the save went through
        refute_enqueued(worker: ContentEventDispatcher)
      end)
    end

    test "inside a transaction, the job row is inserted and debounced in savepoints", %{user: user} do
      put_test_env(Brando.ContentEvents, subscribers: [Collector], debounce_seconds: 5)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, page} =
          Brando.Repo.transaction(fn ->
            page = create_page(user)
            {:ok, _} = Pages.update_page(page.id, %{title: "One"}, user)
            {:ok, _} = Pages.update_page(page.id, %{meta_description: "Two"}, user)
            page
          end)

        assert [created, updated] =
                 all_enqueued(worker: ContentEventDispatcher) |> Enum.sort_by(& &1.id)

        assert created.args["entry_id"] == page.id
        assert updated.args["fields"] == ["meta_description", "title"]
      end)
    end

    test "the event waits in a job, not in the save", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        page = create_page(user)
        assert collected() == []
        assert [job] = all_enqueued(worker: ContentEventDispatcher)
        assert job.queue == "content_events"
        assert job.args["entry_id"] == page.id
        refute Map.has_key?(job.args, "title")

        assert :ok = perform_job(ContentEventDispatcher, job.args)
        assert [%Event{type: "entry.created"}] = collected()
      end)
    end
  end

  describe "debounce" do
    setup do
      put_test_env(Brando.ContentEvents, subscribers: [Collector], debounce_seconds: 5)
    end

    defp dispatcher_jobs do
      Brando.Repo.all(
        from(j in Oban.Job, where: j.worker == ^inspect(ContentEventDispatcher), order_by: j.id),
        prefix: "public"
      )
    end

    test "several saves within the window are one entry.updated with every field", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        page = create_page(user)
        {:ok, _} = Pages.update_page(page.id, %{title: "One"}, user)
        {:ok, _} = Pages.update_page(page.id, %{meta_description: "Two"}, user)
        {:ok, _} = Pages.update_page(page.id, %{title: "Three"}, user)

        assert [created, updated] = dispatcher_jobs()
        assert created.args["type"] == "entry.created"
        assert updated.args["type"] == "entry.updated"
        assert updated.state == "scheduled"
        assert DateTime.diff(updated.scheduled_at, DateTime.utc_now()) in 1..5
        assert updated.args["fields"] == ["meta_description", "title"]

        assert :ok = perform_job(ContentEventDispatcher, updated.args)
        assert [%Event{type: "entry.updated", changed_fields: ["meta_description", "title"]}] = collected()
      end)
    end

    test "different entries are not merged", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        first = create_page(user)
        second = create_page(user)
        {:ok, _} = Pages.update_page(first.id, %{title: "One"}, user)
        {:ok, _} = Pages.update_page(second.id, %{title: "Two"}, user)

        updates = Enum.filter(dispatcher_jobs(), &(&1.args["type"] == "entry.updated"))
        assert Enum.map(updates, & &1.args["entry_id"]) == [first.id, second.id]
      end)
    end

    test "a publish in the window takes the pending update's fields and replaces it", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        page = create_page(user)
        {:ok, _} = Pages.update_page(page.id, %{meta_description: "Edited"}, user)
        {:ok, _} = Pages.update_page(page.id, %{status: :published}, user)

        assert ["entry.created", "entry.published"] = Enum.map(dispatcher_jobs(), & &1.args["type"])
        published = List.last(dispatcher_jobs())
        assert published.state == "available"
        assert published.args["fields"] == ["meta_description", "status"]
      end)
    end
  end
end
