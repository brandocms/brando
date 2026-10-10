defmodule Brando.PublisherRefusedTest do
  # A publication or expiry that `Brando.Worker.EntryPublisher` runs as the
  # user who scheduled it, refused when it runs: the user lost the right, or
  # their account is gone. `Brando.Publisher.sweep/1` must not carry it out
  # as the system instead.
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Activity.Event
  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Worker.EntryPublisher
  alias Ecto.Adapters.SQL

  @keys ~w(brando.admin.access brando.pages.create brando.pages.read brando.pages.update
           brando.pages.publish brando.pages.schedule)

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    {:ok, _} = Migration.run()
    scope = Scope.standalone(owner)
    {:ok, group} = Groups.create(scope, %{name: "Scheduled publishers"}, @keys)
    {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
    %{owner: owner, scope: scope, group: group, editor: editor}
  end

  defp at(seconds), do: DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.truncate(:second)

  # A page the editor scheduled, whose time has now come
  defp scheduled_page(editor, attrs) do
    params =
      Map.merge(
        %{
          title: "Scheduled page",
          uri: "scheduled-#{System.unique_integer([:positive])}",
          language: "en",
          template: "default.html",
          status: :published
        },
        attrs
      )

    {:ok, page} = Oban.Testing.with_testing_mode(:manual, fn -> Pages.create_page(params, editor) end)
    page
  end

  defp set_dates(page, set), do: {1, _} = Repo.update_all(from(p in Page, where: p.id == ^page.id), set: set)

  defp revoke(%{scope: scope, group: group, editor: editor}),
    do: {:ok, :ok} = Groups.remove_member(scope, group.id, editor.id)

  defp run_job(page, status, user_id),
    do:
      perform_job(EntryPublisher, %{
        "schema" => to_string(Page),
        "id" => page.id,
        "status" => status,
        "user_id" => user_id
      })

  defp jobs(page, status) do
    Repo.all(
      from j in Oban.Job,
        where:
          j.worker == "Brando.Worker.EntryPublisher" and fragment("?->>'status' = ?", j.args, ^status) and
            fragment("(?->>'id')::int", j.args) == ^page.id
    )
  end

  # Runs `change` once, the next time this process queries `source`
  defp meanwhile(source \\ "users", change) do
    id = make_ref()
    test = self()

    :telemetry.attach(
      id,
      Repo.config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, _config ->
        if self() == test and metadata.source == source do
          :telemetry.detach(id)
          change.()
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  # The job made for `date`, to run at `scheduled_at`
  defp on_date(job, date, scheduled_at) do
    {1, _} =
      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
        set: [scheduled_at: scheduled_at, meta: Map.put(job.meta, "at", DateTime.to_iso8601(date))]
      )
  end

  # What the sweep did with `page`
  defp swept(page), do: Enum.filter(Brando.Publisher.sweep(), &for_page?(&1, page))

  defp for_page?(result, page), do: result.schema == Page and result.id == page.id

  defp refused_events(page) do
    Repo.all(
      from e in Event,
        where: e.entry_id == ^page.id and fragment("? \\? 'schedule_refused'", e.details),
        order_by: e.id
    )
  end

  describe "a publication refused when it runs" do
    test "its user lost the right: the job is cancelled, the entry goes back to draft and the sweep leaves it", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      assert page.status == :pending
      revoke(c)
      set_dates(page, publish_at: at(-600))

      assert {:cancel, :forbidden} = run_job(page, "published", c.editor.id)

      refused = Repo.get!(Page, page.id)
      assert refused.status == :draft
      assert refused.publish_at == nil

      assert [%{action: :updated, source: :scheduler, user_id: nil} = event] = refused_events(page)
      assert event.details["schedule_refused"] == %{"action" => "publish", "reason" => "forbidden"}
      assert event.details["status"] == %{"from" => "pending", "to" => "draft"}

      assert swept(page) == []
      assert Repo.get!(Page, page.id).status == :draft
    end

    test "its user no longer exists", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      set_dates(page, publish_at: at(-600))

      assert {:cancel, :scheduler_missing} = run_job(page, "published", -1)

      assert %{status: :draft, publish_at: nil} = Repo.get!(Page, page.id)
      assert [%{details: %{"schedule_refused" => %{"reason" => "scheduler_missing"}}}] = refused_events(page)
      assert swept(page) == []
    end

    test "its user was deactivated, even without group authorization", c do
      put_test_env(:authorization_mode, :roles)
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      Repo.update!(Ecto.Changeset.change(c.editor, active: false))
      set_dates(page, publish_at: at(-600))

      assert {:cancel, :scheduler_inactive} = run_job(page, "published", c.editor.id)
      assert %{status: :draft, publish_at: nil} = Repo.get!(Page, page.id)
    end

    test "its user was deleted", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      Repo.update!(Ecto.Changeset.change(c.editor, deleted_at: DateTime.truncate(DateTime.utc_now(), :second)))
      set_dates(page, publish_at: at(-600))

      assert {:cancel, reason} = run_job(page, "published", c.editor.id)
      assert reason in [:scheduler_missing, :scheduler_inactive]
      assert %{status: :draft, publish_at: nil} = Repo.get!(Page, page.id)
    end

    test "an entry that no longer validates still loses the date, so the sweep leaves it", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      revoke(c)
      set_dates(page, publish_at: at(-600), title: nil)

      assert {:cancel, :forbidden} = run_job(page, "published", c.editor.id)
      assert %{status: :draft, publish_at: nil} = Repo.get!(Page, page.id)
      assert [%{details: %{"schedule_refused" => %{"action" => "publish"}}}] = refused_events(page)
      assert swept(page) == []
    end

    test "leaves a date or status an editor changed while the job ran", c do
      moved = scheduled_page(c.editor, %{publish_at: at(3600)})
      published = scheduled_page(c.editor, %{publish_at: at(3600)})
      revoke(c)
      set_dates(moved, publish_at: at(-600))
      set_dates(published, publish_at: at(-600))
      tomorrow = at(86_400)

      # Between the job reading the entry and refusing it: when it looks up
      # the user who scheduled it
      meanwhile(fn -> set_dates(moved, publish_at: tomorrow) end)
      assert {:cancel, :forbidden} = run_job(moved, "published", c.editor.id)
      assert %{status: :pending, publish_at: ^tomorrow} = Repo.get!(Page, moved.id)

      meanwhile(fn -> set_dates(published, status: :published) end)
      assert {:cancel, :forbidden} = run_job(published, "published", c.editor.id)
      assert %{status: :published} = Repo.get!(Page, published.id)

      assert refused_events(moved) == []
      assert refused_events(published) == []
    end

    test "a user who still may publishes as before", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      set_dates(page, publish_at: at(-30))

      assert :ok = run_job(page, "published", c.editor.id)
      assert Repo.get!(Page, page.id).status == :published
      assert refused_events(page) == []
    end

    test "Activity says why, apart from an ordinary status change", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      revoke(c)
      set_dates(page, publish_at: at(-600))
      {:cancel, :forbidden} = run_job(page, "published", c.editor.id)
      [event] = refused_events(page)

      refused = render_component(&BrandoAdmin.Components.Activity.details/1, event: event, states: %{})
      plain = Map.update!(event, :details, &Map.delete(&1, "schedule_refused"))
      ordinary = render_component(&BrandoAdmin.Components.Activity.details/1, event: plain, states: %{})

      assert length(String.split(refused, "activity-detail")) == 3
      refute refused == ordinary
    end
  end

  describe "an expiry refused when it runs" do
    test "clears the expiry, keeps the entry published and cancels the job", c do
      page = scheduled_page(c.editor, %{unpublish_at: at(3600)})
      assert page.status == :published
      revoke(c)
      set_dates(page, unpublish_at: at(-600))

      assert {:cancel, :forbidden} = run_job(page, "disabled", c.editor.id)

      assert %{status: :published, unpublish_at: nil} = Repo.get!(Page, page.id)
      assert [%{details: %{"schedule_refused" => %{"action" => "unpublish"}}}] = refused_events(page)
      assert swept(page) == []
      assert Repo.get!(Page, page.id).status == :published
    end
  end

  describe "a schedule in a site's environment" do
    setup c do
      put_test_env(:tenancy_mode, :multi)
      Tenant.put_prefix(nil)
      page = Factory.insert(:page, status: :draft)

      {:ok, site} =
        Registry.create_site(%{
          name: "Scheduled site",
          key: "scheduled-site",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      environment = environment(site, "production")
      site_scope = Scope.site(c.owner, site, environment)
      {:ok, group} = Groups.create(site_scope, %{name: "Site publishers"}, @keys)
      {:ok, :ok} = Groups.add_member(site_scope, group.id, c.editor.id)

      on_exit(fn ->
        Tenant.put_prefix(nil)
        Tenant.Cache.clear()
      end)

      %{site: site, prefix: Tenant.prefix(site, environment), site_scope: site_scope, site_group: group, page: page}
    end

    test "is retried while the site is suspended, and taken back once its user may no longer run it", c do
      {1, _} =
        Repo.update_all(from(p in Page, where: p.id == ^c.page.id), [set: [status: :pending, publish_at: at(-600)]],
          prefix: c.prefix
        )

      args = %{"schema" => to_string(Page), "id" => c.page.id, "status" => "published", "user_id" => c.editor.id}
      args = Map.put(args, "tenant_prefix", c.prefix)

      {:ok, suspended} = Registry.update_site(c.site, %{status: :suspended})
      assert {:error, :forbidden} = perform_job(EntryPublisher, args)
      assert %{status: :pending, publish_at: %DateTime{}} = Repo.get!(Page, c.page.id, prefix: c.prefix)

      {:ok, _} = Registry.update_site(suspended, %{status: :active})
      {:ok, :ok} = Groups.remove_member(c.site_scope, c.site_group.id, c.editor.id)
      assert {:cancel, :forbidden} = perform_job(EntryPublisher, args)
      assert %{status: :draft, publish_at: nil} = Repo.get!(Page, c.page.id, prefix: c.prefix)
    end
  end

  describe "the sweep" do
    test "leaves a date to its job while the job waits or retries, and catches up once there is none", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      date = at(-600)
      set_dates(page, publish_at: date)
      assert [job] = jobs(page, "published")
      # The job made for this date, its time come
      on_date(job, date, date)

      for state <- ~w(scheduled available executing retryable) do
        {1, _} = Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: state])
        assert swept(page) == [], state
        assert Repo.get!(Page, page.id).status == :pending
      end

      # Retrying later, after a failed attempt
      on_date(job, date, at(600))
      assert swept(page) == []

      # A job for the entry's expiry is not its publication's
      {1, _} =
        Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
          set: [state: "retryable", args: Map.put(job.args, "status", "disabled")]
        )

      assert [%{action: :publish, result: :ok}] = swept(page)
      assert Repo.get!(Page, page.id).status == :published
    end

    test "leaves an expiry to its job, even when the publication before it has no job", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600), unpublish_at: at(7200)})
      for job <- jobs(page, "published"), do: Repo.delete!(job)
      [expiry] = jobs(page, "disabled")
      Repo.update!(Ecto.Changeset.change(expiry, state: "retryable"))
      set_dates(page, publish_at: at(-1200), unpublish_at: at(-600))
      on_date(expiry, at(-600), at(600))

      assert swept(page) == []
      assert Repo.get!(Page, page.id).status == :pending
    end

    test "does not wait for a job made for another, later date", c do
      # An archive restored into the environment: the entry's date passed,
      # while the queue still holds the job for the date it had before
      page = scheduled_page(c.editor, %{publish_at: at(3 * 86_400)})
      set_dates(page, publish_at: at(-600))
      assert [%{state: "scheduled"}] = jobs(page, "published")

      assert [%{action: :publish, result: :ok}] = swept(page)
      assert Repo.get!(Page, page.id).status == :published
    end

    test "leaves an entry a refused job took back while the sweep ran", c do
      page = scheduled_page(c.editor, %{publish_at: at(3600)})
      set_dates(page, publish_at: at(-600))
      for job <- jobs(page, "published"), do: Repo.delete!(job)

      # Between the sweep finding the entry and saving it: when it looks for jobs
      meanwhile("oban_jobs", fn -> set_dates(page, status: :draft, publish_at: nil) end)
      assert swept(page) == []
      assert %{status: :draft, publish_at: nil} = Repo.get!(Page, page.id)
    end

    test "publishes a date whose job is gone or done", c do
      lost = scheduled_page(c.editor, %{publish_at: at(3600)})
      set_dates(lost, publish_at: at(-600))
      for job <- jobs(lost, "published"), do: Repo.delete!(job)

      discarded = scheduled_page(c.editor, %{publish_at: at(3600)})
      set_dates(discarded, publish_at: at(-600))

      for job <- jobs(discarded, "published"), do: Repo.update!(Ecto.Changeset.change(job, state: "discarded"))

      results = Brando.Publisher.sweep()
      assert [%{action: :publish, result: :ok}] = Enum.filter(results, &for_page?(&1, lost))
      assert [%{action: :publish, result: :ok}] = Enum.filter(results, &for_page?(&1, discarded))
      assert Repo.get!(Page, lost.id).status == :published
      assert Repo.get!(Page, discarded.id).status == :published
    end
  end

  defp environment(site, key) do
    {:ok, environment} = Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
    prefix = Tenant.prefix(site, environment)
    SQL.query!(Repo, ~s(CREATE SCHEMA "#{prefix}"))
    %{rows: rows} = SQL.query!(Repo, "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")

    rows
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")
      SQL.query!(Repo, ~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
      SQL.query!(Repo, ~s(INSERT INTO "#{prefix}"."#{escaped}" SELECT * FROM public."#{escaped}"))
    end)

    environment
  end
end
