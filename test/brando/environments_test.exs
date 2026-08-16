defmodule Brando.EnvironmentsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Environments
  alias Brando.Environments.Environment
  alias Brando.Environments.OperationLog
  alias Brando.Environments.Schema
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Worker.EnvironmentCopy
  alias Brando.Worker.EnvironmentSetLive

  defmodule SuccessfulMigrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(site, environment) do
      send(self(), {:tenant_migrated, site.key, environment.key})
      {:ok, [20_260_816_000_001]}
    end
  end

  defmodule FailingMigrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:error, :migration_broke}
  end

  defmodule SuccessfulSchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(source_prefix, target_prefix) do
      send(self(), {:schema_cloned, source_prefix, target_prefix})
      Brando.Environments.Schema.create(target_prefix)
    end
  end

  defmodule RecoveringSchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(source_prefix, target_prefix) do
      send(self(), {:schema_cloned, source_prefix, target_prefix})

      if target_prefix == Process.get(:fail_clone_target) and
           is_nil(Process.get(:target_clone_failed)) do
        Process.put(:target_clone_failed, true)
        Brando.Environments.Schema.create(target_prefix)
        {:error, :simulated_copy_failure}
      else
        Brando.Environments.Schema.create(target_prefix)
      end
    end
  end

  @site_attrs %{
    name: "Acme",
    key: "acme",
    languages: ["en"],
    default_language: "en",
    status: :active,
    delivery_mode: :dynamic
  }

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, SuccessfulMigrator)
    put_test_env(:environment_schema_cloner, SuccessfulSchemaCloner)
    Tenant.put_prefix("tenant_unrelated-context_preview")
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
      Process.delete(:fail_clone_target)
      Process.delete(:target_clone_failed)
    end)

    {:ok, site} = Registry.create_site(@site_attrs)
    %{site: site}
  end

  test "creates a schema and migrates a named environment", %{site: site} do
    assert {:ok, %Environment{} = environment} =
             Environments.create_environment(site, %{
               name: "Spring Redesign",
               key: "spring-redesign",
               live: false
             })

    assert_received {:tenant_migrated, "acme", "spring-redesign"}
    assert Schema.exists?(Tenant.prefix(site, environment))
    assert Registry.get_environment(environment.id)
    assert Cache.get_env("acme", "spring-redesign")

    assert [%OperationLog{operation: :create, target_environment_id: environment_id}] =
             operation_logs(site)

    assert environment_id == environment.id
  end

  test "compensates the registry and schema when migrations fail", %{site: site} do
    put_test_env(:tenant_migrator, FailingMigrator)

    assert {:error, {:migration_failed, :migration_broke}} =
             Environments.create_environment(site, %{
               name: "Broken",
               key: "broken",
               live: false
             })

    refute Schema.exists?(Tenant.prefix("acme", "broken"))
    refute Registry.get_environment_by_key(site, "broken")
    refute Cache.get_env("acme", "broken")
  end

  test "deletes non-live environments but protects the live environment", %{site: site} do
    {:ok, preview} =
      Environments.create_environment(site, %{
        name: "Preview",
        key: "preview",
        live: false
      })

    {:ok, production} =
      Environments.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    assert {:error, :live_environment} = Environments.delete_environment(production)
    assert Schema.exists?(Tenant.prefix(site, production))

    assert {:ok, %Environment{id: preview_id}} = Environments.delete_environment(preview)
    assert preview_id == preview.id
    refute Schema.exists?(Tenant.prefix(site, preview))
    refute Registry.get_environment(preview.id)

    assert Enum.any?(operation_logs(site), &(&1.operation == :delete))
  end

  test "sets one environment live atomically and refreshes routing cache", %{site: site} do
    {:ok, production} =
      Environments.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    {:ok, staging} =
      Environments.create_environment(site, %{
        name: "Staging",
        key: "staging",
        live: false
      })

    assert {:ok, %Environment{id: staging_id, live: true}} = Environments.set_live(staging)
    assert staging_id == staging.id
    assert %Environment{id: ^staging_id} = Cache.get_live_env("acme")
    refute Registry.get_environment(production.id).live
    assert Registry.get_environment(staging.id).live

    # The original struct is stale (`live: true`) after the first switch. The
    # operation must consult public registry state and still switch it back.
    assert {:ok, %Environment{id: production_id, live: true}} =
             Environments.set_live(production)

    assert production_id == production.id
    assert %Environment{id: ^production_id} = Cache.get_live_env("acme")
    assert Enum.count(operation_logs(site), &(&1.operation == :set_live)) == 2
    assert Enum.count(Environments.list_archives(site), &(&1.operation == :set_live)) == 2
  end

  test "stale structs cannot delete the current live environment", %{site: site} do
    {:ok, production} =
      Environments.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    stale_non_live = %{production | live: false}

    assert {:error, :live_environment} = Environments.delete_environment(stale_non_live)
    assert Schema.exists?(Tenant.prefix(site, production))
    assert Registry.get_environment(production.id)
  end

  test "migrates every environment for a site or installation", %{site: site} do
    {:ok, first} =
      Environments.create_environment(site, %{name: "One", key: "one", live: true})

    {:ok, second} =
      Environments.create_environment(site, %{name: "Two", key: "two", live: false})

    assert {:ok, site_results} = Environments.migrate_site(site)
    assert Enum.map(site_results, &elem(&1, 0).id) == [first.id, second.id]

    assert {:ok, all_results} = Environments.migrate_all()
    assert Enum.map(all_results, &elem(&1, 0).id) == [first.id, second.id]
  end

  test "archives the target before copying and supports pruning", %{site: site} do
    {:ok, source} =
      Environments.create_environment(site, %{name: "Source", key: "source", live: true})

    {:ok, target} =
      Environments.create_environment(site, %{name: "Target", key: "target", live: false})

    assert {:ok, %{archive_schema: archive_schema, target: copied_target}} =
             Environments.copy_environment(source, target, note: "Approved release")

    assert copied_target.id == target.id
    assert Schema.exists?(archive_schema)
    assert Schema.exists?(Tenant.prefix(site, target))

    assert [%{schema: ^archive_schema, operation: :copy}] = Environments.list_archives(site)

    assert [%OperationLog{operation: :copy, note: "Approved release"}] =
             Enum.filter(operation_logs(site), &(&1.operation == :copy))

    assert {:ok, [^archive_schema]} = Environments.prune_archives(site, 0)
    refute Schema.exists?(archive_schema)
    assert Environments.list_archives(site) == []
  end

  test "restores the target archive when a copy fails", %{site: site} do
    put_test_env(:environment_schema_cloner, RecoveringSchemaCloner)

    {:ok, source} =
      Environments.create_environment(site, %{name: "Source", key: "source", live: true})

    {:ok, target} =
      Environments.create_environment(site, %{name: "Target", key: "target", live: false})

    target_prefix = Tenant.prefix(site, target)
    Process.put(:fail_clone_target, target_prefix)

    assert {:error, {:copy_failed, :simulated_copy_failure, :ok}} =
             Environments.copy_environment(source, target)

    assert Schema.exists?(target_prefix)
    assert [%{schema: archive_schema}] = Environments.list_archives(site)
    assert Schema.exists?(archive_schema)
    refute Enum.any?(operation_logs(site), &(&1.operation == :copy))
  end

  test "restores the newest archive as a new non-live environment", %{site: site} do
    {:ok, source} =
      Environments.create_environment(site, %{name: "Source", key: "source", live: true})

    {:ok, target} =
      Environments.create_environment(site, %{name: "Target", key: "target", live: false})

    assert {:ok, %{archive_schema: archive_schema}} =
             Environments.copy_environment(source, target)

    assert {:ok, %Environment{live: false} = restored} =
             Environments.rollback(site, note: "Restore checkpoint")

    assert String.starts_with?(restored.key, "rollback-")
    assert Schema.exists?(Tenant.prefix(site, restored))

    assert [%OperationLog{archive_schema: ^archive_schema, note: "Restore checkpoint"}] =
             Enum.filter(operation_logs(site), &(&1.operation == :rollback))
  end

  test "schedules, lists, and cancels environment operations", %{site: site} do
    {:ok, source} =
      Environments.create_environment(site, %{name: "Source", key: "source", live: true})

    {:ok, target} =
      Environments.create_environment(site, %{name: "Target", key: "target", live: false})

    scheduled_at = DateTime.add(DateTime.utc_now(), 3600, :second)

    {copy_job, live_job} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, copy_job} =
                 Environments.schedule_copy(source, target, scheduled_at, note: "Nightly release")

        assert {:ok, live_job} = Environments.schedule_set_live(target, scheduled_at)
        {copy_job, live_job}
      end)

    assert copy_job.worker == Oban.Worker.to_string(EnvironmentCopy)
    assert live_job.worker == Oban.Worker.to_string(EnvironmentSetLive)

    assert Enum.map(Environments.list_scheduled_operations(site), & &1.id) ==
             [copy_job.id, live_job.id]

    assert :ok =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Environments.cancel_scheduled_operation(site, copy_job.id)
             end)

    assert Enum.map(Environments.list_scheduled_operations(site), & &1.id) == [live_job.id]
  end

  test "scheduled workers execute through the environment lifecycle API", %{site: site} do
    {:ok, source} =
      Environments.create_environment(site, %{name: "Source", key: "source", live: true})

    {:ok, target} =
      Environments.create_environment(site, %{name: "Target", key: "target", live: false})

    assert :ok =
             EnvironmentCopy.perform(%Oban.Job{
               args: %{
                 "source_environment_id" => source.id,
                 "target_environment_id" => target.id,
                 "note" => "Scheduled copy"
               }
             })

    assert :ok =
             EnvironmentSetLive.perform(%Oban.Job{
               args: %{"environment_id" => target.id, "note" => "Scheduled promotion"}
             })

    assert Registry.get_environment(target.id).live
  end

  defp operation_logs(site) do
    import Ecto.Query, only: [from: 2]

    from(log in OperationLog,
      where: log.site_id == ^site.id,
      order_by: [asc: log.id]
    )
    |> Brando.Repo.all(prefix: "public")
  end
end
