defmodule Brando.EnvironmentsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Environments
  alias Brando.Environments.Environment
  alias Brando.Environments.Schema
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

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
    Tenant.put_prefix("tenant_unrelated-context_preview")
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
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
end
