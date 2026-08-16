defmodule BrandoAdmin.Sites.EnvironmentLiveTest do
  use Brando.LiveCase

  alias Brando.Environments
  alias Brando.Environments.OperationLog
  alias Brando.Environments.Schema
  alias Brando.Tenant
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

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
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

  test "editors cannot invoke environment lifecycle events", %{site: site} do
    editor =
      Brando.Factory.insert(:random_user,
        role: :editor,
        config: %Brando.Users.UserConfig{}
      )

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
