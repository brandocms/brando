defmodule BrandoAdmin.Sites.EnvironmentLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments
  alias Brando.Environments.OperationLog
  alias Brando.Environments.Schema
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, [20_260_816_000_001]}
  end

  defmodule SchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix), do: Schema.create(target_prefix)
  end

  defmodule StructureCloner do
    @behaviour Brando.Environments.StructureCloner

    @impl true
    def clone_structure(_source_prefix, _target_prefix), do: :ok
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    Cache.clear()
    Tenant.put_prefix(nil)

    on_exit(fn ->
      Cache.clear()
      Tenant.put_prefix(nil)
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme-environment-live",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, production} =
      Environments.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    %{site: site, production: production}
  end

  test "copying into the live environment has to be ticked", %{conn: conn, site: site, production: production} do
    {:ok, preview} =
      Environments.create_environment(site, %{name: "Preview", key: "preview-copy-live", domain: "p.example.com"})

    {:ok, view, _html} = live(conn, "/admin/config/environments")

    copies = fn ->
      Brando.Repo.all(from(l in OperationLog, where: l.target_environment_id == ^production.id and l.operation == :copy),
        prefix: "public"
      )
    end

    view
    |> form("#copy-environment-form", operation: %{source_id: preview.id, target_id: production.id})
    |> render_submit()

    assert copies.() == []

    view
    |> form("#copy-environment-form", operation: %{source_id: preview.id, target_id: production.id, replace_live: "true"})
    |> render_submit()

    assert [%OperationLog{operation: :copy}] = copies.()
  end

  test "creates an environment and exposes a queued copy that can be cancelled", %{
    conn: conn,
    site: site,
    production: production
  } do
    {:ok, view, html} = live(conn, "/admin/config/environments")

    assert html =~ "Environments"
    assert has_element?(view, "#environment-#{production.id}", "Production")

    view
    |> form("#create-environment-form",
      environment: %{
        name: "Spring Redesign",
        key: "spring-redesign",
        domain: "spring.example.com"
      }
    )
    |> render_submit()

    preview = Registry.get_environment_by_key(site, "spring-redesign")

    assert preview
    assert has_element?(view, "#environment-#{preview.id}", "Spring Redesign")

    view
    |> form("#copy-environment-form",
      operation: %{
        source_id: production.id,
        target_id: preview.id,
        note: "Release rehearsal"
      }
    )
    |> render_submit()

    assert %OperationLog{note: "Release rehearsal"} =
             Brando.Repo.get_by(
               OperationLog,
               [site_id: site.id, operation: :copy],
               prefix: "public"
             )

    scheduled_at = DateTime.add(DateTime.utc_now(), 3_600, :second)

    job =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, job} =
                 Environments.schedule_copy(production, preview, scheduled_at, note: "Release rehearsal")

        job
      end)

    view
    |> element("button", "Refresh")
    |> render_click()

    assert [listed_job] = Environments.list_scheduled_operations(site)
    assert listed_job.id == job.id
    assert has_element?(view, "#environment-job-#{job.id}", "Copy Production → Spring Redesign")
    assert has_element?(view, "#environment-job-#{job.id} .environment-state", "Scheduled")

    view
    |> element("#environment-job-#{job.id} button", "Cancel")
    |> render_click()

    # The test suite runs Oban's inline engine, whose cancel callback is a
    # deliberate no-op. Exercise the persistence side in manual mode, then
    # verify that the management screen removes the cancelled operation.
    assert :ok =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Environments.cancel_scheduled_operation(site, job.id)
             end)

    view
    |> element("button", "Refresh")
    |> render_click()

    assert Environments.list_scheduled_operations(site) == []
    refute has_element?(view, "#environment-job-#{job.id}")
  end

  # Scheduled by someone who may no longer promote the site's environments:
  # the open screen shows the operation cancelled, and why
  test "shows a scheduled operation cancelled when it was due", %{conn: conn, site: site} do
    {:ok, preview} = Environments.create_environment(site, %{name: "Preview", key: "preview-cancelled"})
    scheduler = Brando.Factory.insert(:random_user, role: :user, name: "Sam Scheduler")

    {:ok, view, _html} = live(conn, "/admin/config/environments")

    job =
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, job} =
          %{site_id: site.id, environment_id: preview.id, creator_id: scheduler.id}
          |> Brando.Worker.EnvironmentSetLive.new()
          |> Oban.insert()

        assert %{cancelled: 1} = Oban.drain_queue(queue: :environment_operations)
        job
      end)

    row = "#environment-job-#{job.id}.environment-job--cancelled"
    assert has_element?(view, row, "Preview")
    assert has_element?(view, "#{row} .environment-job__reason", "Sam Scheduler")
    assert has_element?(view, "#{row} .environment-state.cancelled")
    refute has_element?(view, "#{row} button")
  end

  defmodule RaisingSchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix) do
      :ok = Schema.create(target_prefix)
      raise "the clone broke halfway"
    end
  end

  @tag :capture_log
  test "a restore that fails says so, and leaves nothing behind", %{
    conn: conn,
    site: site,
    production: production,
    current_user: user
  } do
    {:ok, preview} = Environments.create_environment(site, %{name: "Preview", key: "preview-restore"})
    assert {:ok, _} = Environments.copy_environment(production, preview)
    put_test_env(:environment_schema_cloner, RaisingSchemaCloner)
    Brando.endpoint().subscribe("user:#{user.id}")

    {:ok, view, _html} = live(conn, "/admin/config/environments")

    view
    |> element("button[phx-click=rollback]:not([phx-value-schema])")
    |> render_click()

    # The restore runs in its own task, which reports back to the page
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{level: :error}}, 5_000
    assert render(view)
    refute Enum.any?(Registry.list_environments(site), &String.starts_with?(&1.key, "rollback"))

    assert BrandoIntegration.Repo.query!(
             "SELECT count(*) FROM pg_namespace WHERE nspname LIKE 'tenant_acme-environment-live_rollback%'"
           ).rows ==
             [[0]]
  end

  # The log names each operation, not its atom (`set_live`, `copy`), and an
  # archive the operation it was saved before
  test "the operation log and the archives name their operations", %{conn: conn, site: site, production: production} do
    {:ok, preview} = Environments.create_environment(site, %{name: "Preview", key: "preview-log"})
    assert {:ok, _} = Environments.copy_environment(production, preview)

    {:ok, view, _html} = live(conn, "/admin/config/environments")

    assert has_element?(view, ".environment-log__operation", "Created")
    assert has_element?(view, ".environment-log__operation", "Copied")
    refute has_element?(view, ".environment-log__operation", ~r/^\s*(copy|create)\s*$/)
    assert has_element?(view, ".environment-archive__meta span", "Saved before a copy")
  end

  test "editors cannot invoke environment lifecycle events", %{site: site} do
    editor =
      Brando.Factory.insert(:random_user,
        role: :editor,
        config: %Brando.Users.UserConfig{}
      )

    assert {:ok, _assignment} = Access.grant(editor, site, :editor)

    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)
    {:ok, view, _html} = live(conn, "/admin/config/environments")

    assert has_element?(view, "#create-environment-form button[disabled]")

    view
    |> form("#create-environment-form",
      environment: %{name: "Forbidden", key: "forbidden", domain: ""}
    )
    |> render_submit()

    refute Registry.get_environment_by_key(site, "forbidden")
  end
end
