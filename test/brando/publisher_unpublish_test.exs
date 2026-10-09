defmodule Brando.PublisherUnpublishTest do
  # Scheduled expiry: `unpublish_at` on `Brando.Trait.ScheduledPublishing`,
  # the job `Brando.Publisher` schedules for it and `Brando.Worker.EntryPublisher`
  # running it.
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog, only: [with_log: 2]

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

  describe "stale publishing jobs" do
    defp publish_jobs(page) do
      BrandoIntegration.Repo.all(
        from j in Oban.Job,
          where:
            j.worker == "Brando.Worker.EntryPublisher" and fragment("?->>'status' = 'published'", j.args) and
              fragment("(?->>'id')::int", j.args) == ^page.id
      )
    end

    test "clearing publish_at or moving it into the past drops the publishing job", %{user: user} do
      page = create_page(user, %{status: :pending, publish_at: at(3600)})
      assert [_job] = publish_jobs(page)

      {:ok, _} = update_page(page, %{publish_at: nil, status: :draft}, user)
      assert publish_jobs(page) == []

      {:ok, _} = update_page(page, %{publish_at: at(3600), status: :pending}, user)
      assert [_job] = publish_jobs(page)
      {:ok, _} = update_page(page, %{publish_at: at(-60), status: :draft}, user)
      assert publish_jobs(page) == []
    end

    test "a publishing job left behind does not publish an entry set back to draft", %{user: user} do
      page = create_page(user, %{status: :pending, publish_at: at(3600)})
      [job] = publish_jobs(page)
      {:ok, _} = update_page(page, %{status: :draft}, user)

      # It runs at its time all the same
      {1, _} = BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [publish_at: at(-5)])
      assert :ok = EntryPublisher.perform(job)
      assert Repo.get!(Page, page.id).status == :draft
    end
  end

  describe "deleting a job" do
    defp delete_job(job, user),
      do: Oban.Testing.with_testing_mode(:manual, fn -> Brando.Publisher.delete_job(job.id, user) end)

    test "clears the publishing date, and a pending entry goes back to draft", %{user: user} do
      page = create_page(user, %{status: :pending, publish_at: at(3600)})
      [job] = publish_jobs(page)

      assert {_, _} = delete_job(job, user)
      assert %{status: :draft, publish_at: nil} = Repo.get!(Page, page.id)
      assert publish_jobs(page) == []
    end

    test "clears the expiry, and keeps the entry published", %{user: user} do
      page = create_page(user, %{unpublish_at: at(3600)})
      [job] = unpublish_jobs(page)

      assert {_, _} = delete_job(job, user)
      assert %{status: :published, unpublish_at: nil} = Repo.get!(Page, page.id)
    end

    test "leaves a date that moved since the job was made", %{user: user} do
      page = create_page(user, %{unpublish_at: at(3600)})
      [job] = unpublish_jobs(page)
      moved = at(7200)
      {1, _} = BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [unpublish_at: moved])

      assert {_, _} = delete_job(job, user)
      assert Repo.get!(Page, page.id).unpublish_at == moved
    end
  end

  describe "an expiry that has passed" do
    test "is cleared when the entry is published again", %{user: user} do
      page = create_page(user, %{publish_at: at(-7200)})
      {:ok, expired} = Pages.update_page(page.id, %{unpublish_at: at(-60)}, user)
      assert expired.status == :disabled

      {:ok, republished} = update_page(expired, %{status: :published}, user)
      assert republished.status == :published
      assert republished.unpublish_at == nil

      # and a save of another field afterwards has nothing to trip over
      assert {:ok, _} = update_page(republished, %{title: "Renamed"}, user)
    end

    test "a new expiry set as the entry is published again is kept", %{user: user} do
      page = create_page(user, %{publish_at: at(-7200)})
      {:ok, expired} = Pages.update_page(page.id, %{unpublish_at: at(-60)}, user)
      later = at(3600)

      {:ok, republished} = update_page(expired, %{status: :published, unpublish_at: later}, user)
      assert republished.unpublish_at == later
      assert [_job] = unpublish_jobs(republished)
    end
  end

  describe "copies" do
    test "a duplicate, or a translation, starts without the expiry", %{user: user} do
      page = create_page(user, %{unpublish_at: at(3600)})
      {:ok, copy} = Oban.Testing.with_testing_mode(:manual, fn -> Pages.duplicate_page(page.id, user) end)

      assert copy.status == :draft
      assert copy.unpublish_at == nil
      assert Repo.get!(Page, page.id).unpublish_at != nil
    end
  end

  describe "the sweep" do
    # Dates without jobs, as an environment clone or an archive restore leaves them
    defp without_jobs(page, set) do
      {1, _} = BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: set)

      BrandoIntegration.Repo.delete_all(
        from j in Oban.Job,
          where: j.worker == "Brando.Worker.EntryPublisher" and fragment("? @> ?", j.args, ^%{"id" => page.id})
      )
    end

    test "publishes and deactivates entries whose dates passed with no job, once", %{user: user} do
      pending = create_page(user, %{status: :draft})
      without_jobs(pending, status: :pending, publish_at: at(-3600))
      expiring = create_page(user)
      without_jobs(expiring, unpublish_at: at(-3600))
      expired_pending = create_page(user, %{status: :draft})
      without_jobs(expired_pending, status: :pending, publish_at: at(-7200), unpublish_at: at(-3600))
      # Not yet: the jobs get a few minutes first
      recent = create_page(user, %{status: :draft})
      without_jobs(recent, status: :pending, publish_at: at(-60))
      later = create_page(user)
      without_jobs(later, unpublish_at: at(3600))
      collected()

      assert Brando.Publisher.sweep() |> Enum.map(&{&1.id, &1.action, &1.result}) |> Enum.sort() ==
               Enum.sort([
                 {pending.id, :publish, :ok},
                 {expiring.id, :unpublish, :ok},
                 {expired_pending.id, :unpublish, :ok}
               ])

      assert Repo.get!(Page, pending.id).status == :published
      assert Repo.get!(Page, expiring.id).status == :disabled
      assert Repo.get!(Page, expired_pending.id).status == :disabled
      assert Repo.get!(Page, recent.id).status == :pending
      assert Repo.get!(Page, later.id).status == :published

      # The pending entry that expired was never live: an update, not an unpublish
      assert collected() |> Enum.map(&{&1.entry_id, &1.type}) |> Enum.sort() ==
               Enum.sort([
                 {pending.id, "entry.published"},
                 {expiring.id, "entry.unpublished"},
                 {expired_pending.id, "entry.updated"}
               ])

      assert collected() == []

      # Again: nothing left to do
      assert Brando.Publisher.sweep() == []
    end

    test "leaves dates from more than a week ago alone", %{user: user} do
      old = create_page(user, %{status: :draft})
      without_jobs(old, status: :pending, publish_at: at(-8 * 86_400))
      old_expiry = create_page(user)
      without_jobs(old_expiry, unpublish_at: at(-8 * 86_400))

      assert Brando.Publisher.sweep() == []
      assert Repo.get!(Page, old.id).status == :pending
      assert Repo.get!(Page, old_expiry.id).status == :published
    end

    test "a dry run lists what it would do and changes nothing", %{user: user} do
      pending = create_page(user, %{status: :draft, title: "Launch"})
      without_jobs(pending, status: :pending, publish_at: at(-3600))

      assert [%{id: id, title: "Launch", action: :publish, result: :dry_run}] = Brando.Publisher.sweep(dry_run: true)
      assert id == pending.id
      assert Repo.get!(Page, pending.id).status == :pending
    end

    test "an entry it cannot save is left alone until it is saved again", %{user: user} do
      broken = create_page(user, %{status: :draft})
      without_jobs(broken, status: :pending, publish_at: at(-3600), title: nil)
      fine = create_page(user, %{status: :draft})
      without_jobs(fine, status: :pending, publish_at: at(-3600))

      previous = Logger.level()
      Logger.configure(level: :warning)
      on_exit(fn -> Logger.configure(level: previous) end)

      {results, log} = with_log([level: :warning], fn -> Brando.Publisher.sweep() end)
      assert log =~ "sweep could not publish"
      assert %{result: {:error, _}} = Enum.find(results, &(&1.id == broken.id))
      assert Repo.get!(Page, fine.id).status == :published

      # Not tried again on the next run
      assert Brando.Publisher.sweep() == []

      # Saving it changes updated_at, and the sweep takes it again
      {1, _} =
        BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^broken.id),
          set: [title: "Fixed", updated_at: NaiveDateTime.add(broken.updated_at, 60)]
        )

      assert [%{id: id, result: :ok}] = Brando.Publisher.sweep()
      assert id == broken.id
    end

    test "the cron worker runs it", %{user: user} do
      pending = create_page(user, %{status: :draft})
      without_jobs(pending, status: :pending, publish_at: at(-3600))

      assert :ok = perform_job(Brando.Worker.ScheduledPublishingSweep, %{})
      assert Repo.get!(Page, pending.id).status == :published
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
