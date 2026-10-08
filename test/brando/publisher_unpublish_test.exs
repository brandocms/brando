defmodule Brando.PublisherUnpublishTest do
  # Scheduled expiry: `unpublish_at` on `Brando.Trait.ScheduledPublishing`,
  # the job `Brando.Publisher` schedules for it and `Brando.Worker.EntryPublisher`
  # running it.
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Revisions
  alias Brando.Worker.EntryPublisher

  defmodule Collector do
    @behaviour Brando.ContentEvents.Subscriber
    def handle_event(event), do: send(self(), {:collected, event})
  end

  setup do
    put_test_env(Brando.ContentEvents, subscribers: [Collector], debounce_seconds: 0)
    {:ok, user: Factory.insert(:random_user)}
  end

  defp at(seconds), do: DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.truncate(:second)

  defp create_page(user, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          title: "Campaign",
          uri: "campaign-#{System.unique_integer([:positive])}",
          language: "en",
          template: "default.html",
          status: :published
        },
        attrs
      )

    {:ok, page} = Oban.Testing.with_testing_mode(:manual, fn -> Pages.create_page(params, user) end)
    page
  end

  defp update_page(page, params, user),
    do: Oban.Testing.with_testing_mode(:manual, fn -> Pages.update_page(page.id, params, user) end)

  defp unpublish_jobs(page) do
    BrandoIntegration.Repo.all(
      from j in Oban.Job,
        where:
          j.worker == "Brando.Worker.EntryPublisher" and j.state == "scheduled" and
            fragment("?->>'status' = 'disabled'", j.args) and fragment("(?->>'id')::int", j.args) == ^page.id
    )
  end

  defp collected do
    receive do
      {:collected, event} -> [event | collected()]
    after
      0 -> []
    end
  end

  # Runs a job for the entry as the queue would once its time has come
  defp run_unpublish(page, user) do
    perform_job(EntryPublisher, %{
      "schema" => to_string(Page),
      "id" => page.id,
      "status" => "disabled",
      "user_id" => user.id
    })
  end

  describe "scheduling" do
    test "a future unpublish_at schedules one expiry job for that time", %{user: user} do
      unpublish_at = at(3600)
      page = create_page(user, %{unpublish_at: unpublish_at})

      assert [job] = unpublish_jobs(page)
      assert DateTime.compare(job.scheduled_at, unpublish_at) == :eq
      assert "unpublish" in job.tags and "publisher" in job.tags
      assert Brando.Publisher.unpublish_job?(job)
    end

    test "moving the date replaces the job, whoever scheduled it, and clearing it cancels it", %{user: user} do
      page = create_page(user, %{unpublish_at: at(3600)})
      other = Factory.insert(:random_user)

      later = at(7200)
      {:ok, page} = update_page(page, %{unpublish_at: later}, other)
      assert [job] = unpublish_jobs(page)
      assert DateTime.compare(job.scheduled_at, later) == :eq

      {:ok, page} = update_page(page, %{unpublish_at: nil}, user)
      assert unpublish_jobs(page) == []
      assert page.status == :published
    end

    test "a save that leaves the date alone keeps the job", %{user: user} do
      page = create_page(user, %{unpublish_at: at(3600)})
      {:ok, page} = update_page(page, %{title: "Renamed"}, user)
      assert [_job] = unpublish_jobs(page)
    end

    test "unpublish_at must come after publish_at", %{user: user} do
      page = create_page(user, %{status: :draft, publish_at: at(7200)})

      assert {:error, changeset} = update_page(page, %{unpublish_at: at(3600)}, user)
      assert [unpublish_at: {_message, _}] = changeset.errors
      assert unpublish_jobs(page) == []

      assert {:ok, %{unpublish_at: %DateTime{}}} = update_page(page, %{unpublish_at: at(10_800)}, user)
    end

    test "an unpublish_at that has already passed deactivates the entry at once", %{user: user} do
      page = create_page(user, %{publish_at: at(-3600)})
      collected()

      # Inline, so the content event is delivered here
      {:ok, page} = Pages.update_page(page.id, %{unpublish_at: at(-60)}, user)

      assert page.status == :disabled
      assert unpublish_jobs(page) == []
      assert ["entry.unpublished"] = Enum.map(collected(), & &1.type)
    end
  end

  describe "the job" do
    test "deactivates the entry when unpublish_at has passed, like a manual unpublish", %{user: user} do
      page = create_page(user)
      # The time has come: the date is in the past when the queue runs the job
      {1, _} = BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [unpublish_at: at(-5)])
      collected()

      assert :ok = run_unpublish(page, user)

      unpublished = Repo.get!(Page, page.id)
      assert unpublished.status == :disabled
      assert unpublished.creator_id == page.creator_id

      assert [event] = collected()
      assert event.type == "entry.unpublished"
      assert event.actor == "scheduler"
      assert event.status == "disabled"

      assert [%{action: :unpublished}] =
               BrandoIntegration.Repo.all(
                 from e in Brando.Activity.Event,
                   where: e.entry_id == ^page.id and e.action == :unpublished
               )
    end

    test "does nothing when the date has moved later since it was queued", %{user: user} do
      page = create_page(user, %{unpublish_at: at(3600)})
      collected()

      assert :ok = run_unpublish(page, user)
      assert Repo.get!(Page, page.id).status == :published
      assert collected() == []
    end

    test "does nothing when the expiry was cleared or the entry is no longer published", %{user: user} do
      cleared = create_page(user)
      assert :ok = run_unpublish(cleared, user)
      assert Repo.get!(Page, cleared.id).status == :published

      draft = create_page(user, %{status: :draft})
      {1, _} = BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^draft.id), set: [unpublish_at: at(-5)])
      assert :ok = run_unpublish(draft, user)
      assert Repo.get!(Page, draft.id).status == :draft
    end

    test "a publish job whose publish_at has moved later does not publish", %{user: user} do
      page = create_page(user, %{status: :pending, publish_at: at(3600)})

      assert :ok =
               perform_job(EntryPublisher, %{
                 "schema" => to_string(Page),
                 "id" => page.id,
                 "status" => "published",
                 "user_id" => user.id
               })

      assert Repo.get!(Page, page.id).status == :pending
    end

    test "a publish job for an entry that has expired meanwhile does not publish it", %{user: user} do
      page = create_page(user, %{status: :pending, publish_at: at(3600), unpublish_at: at(7200)})

      {1, _} =
        BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^page.id),
          set: [publish_at: at(-120), unpublish_at: at(-60)]
        )

      assert :ok =
               perform_job(EntryPublisher, %{
                 "schema" => to_string(Page),
                 "id" => page.id,
                 "status" => "published",
                 "user_id" => user.id
               })

      assert Repo.get!(Page, page.id).status == :pending
    end
  end

  describe "revisions" do
    test "restoring a revision keeps the expiry the entry has now", %{user: user} do
      page = create_page(user)
      unpublish_at = at(3600)
      {:ok, _} = update_page(page, %{title: "Second", unpublish_at: unpublish_at}, user)

      {:ok, restored} =
        Oban.Testing.with_testing_mode(:manual, fn -> Revisions.set_entry_to_revision(Page, page.id, 0, user) end)

      assert restored.title == "Campaign"
      assert restored.unpublish_at == unpublish_at
      assert [_job] = unpublish_jobs(page)
    end

    test "a revision job left from before the revision was moved later does nothing", %{user: user} do
      page = create_page(user)
      {:ok, _} = update_page(page, %{title: "Second"}, user)

      schedule = fn at ->
        Oban.Testing.with_testing_mode(:manual, fn -> Brando.Publisher.schedule_revision(Page, page.id, 0, at, user) end)
      end

      {:ok, old_job} = schedule.(at(3600))
      # Moved later, as the revisions drawer or the calendar moves it
      {:ok, new_job} = schedule.(at(7200))
      assert new_job.id != old_job.id

      # The old job runs anyway, at its old time
      old_job = BrandoIntegration.Repo.get!(Oban.Job, old_job.id)
      assert :ok = EntryPublisher.perform(%{old_job | scheduled_at: at(-1)})

      unchanged = Repo.get!(Page, page.id)
      assert unchanged.title == "Second"
      assert {:ok, revisions} = Revisions.list_revision_metadata(Page, page.id)
      assert Enum.find(revisions, &(&1.revision == 0)).scheduled

      # Nor does the new one run before its time
      new_job = BrandoIntegration.Repo.get!(Oban.Job, new_job.id)
      assert :ok = EntryPublisher.perform(new_job)
      assert Repo.get!(Page, page.id).title == "Second"

      # At its time, it publishes the revision
      assert {:ok, published} = EntryPublisher.perform(%{new_job | scheduled_at: at(-1)})
      assert published.title == "Campaign"
      assert published.status == :published
    end

    test "a scheduled revision still publishes, keeping the expiry", %{user: user} do
      page = create_page(user)
      unpublish_at = at(3600)
      {:ok, _} = update_page(page, %{title: "Second", unpublish_at: unpublish_at}, user)

      {:ok, published} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Revisions.set_entry_to_revision(Page, page.id, 0, user, publish?: true)
        end)

      assert published.status == :published
      assert published.title == "Campaign"
      assert published.unpublish_at == unpublish_at
    end
  end
end
