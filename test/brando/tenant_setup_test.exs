defmodule Brando.Tenant.SetupTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Environments.Schema
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup
  alias Brando.Tenant.Storage

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(site, environment) do
      send(self(), {:migrated, site.key, environment.key})
      {:ok, [20_260_816_000_001]}
    end
  end

  defmodule SchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(source_prefix, target_prefix) do
      send(self(), {:cloned, source_prefix, target_prefix})
      Schema.create(target_prefix)
    end
  end

  defmodule StructureCloner do
    @behaviour Brando.Environments.StructureCloner

    @impl true
    def clone_structure(source_prefix, target_prefix) do
      send(self(), {:structure_cloned, source_prefix, target_prefix})
      :ok
    end
  end

  defmodule Seeder do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(site, environment, creator) do
      send(self(), {:seeded, site.key, environment.key, creator.id})
      :ok
    end
  end

  defmodule FailingSeeder do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(_site, _environment, _creator), do: {:error, :seed_failed}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-tenant-setup-#{System.unique_integer([:positive])}")
    media_path = Path.join(root, "media")
    sites_path = Path.join(root, "sites")

    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    put_test_env(:tenant_seeder, Seeder)
    put_test_env(:media_path, media_path)
    put_test_env(:sites_path, sites_path)

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()
    end)

    creator = Brando.Factory.insert(:random_user, role: :admin)
    %{creator: creator, root: root}
  end

  test "creates, seeds, copies, and assigns a complete site", %{creator: creator} do
    assert {:ok, site} = Setup.create_site(site_attrs("provisioned-site"), creator)

    assert Enum.map(site.environments, &{&1.key, &1.live}) |> Enum.sort() ==
             [{"production", true}, {"staging", false}]

    assert_received {:migrated, "provisioned-site", "production"}
    assert_received {:migrated, "provisioned-site", "staging"}
    assert_received {:seeded, "provisioned-site", "production", creator_id}
    assert creator_id == creator.id
    assert_received {:cloned, "tenant_provisioned-site_production", "tenant_provisioned-site_staging"}

    assert Schema.exists?("tenant_provisioned-site_production")
    assert Schema.exists?("tenant_provisioned-site_staging")
    assert File.dir?(Storage.media_root(site))
    assert File.dir?(Storage.assets_root(site))
    assert Access.role_for(creator, site) == :admin
  end

  test "compensates all persisted resources when provisioning fails", %{creator: creator} do
    put_test_env(:tenant_seeder, FailingSeeder)

    assert {:error, {:site_setup_failed, :seed_failed, _compensation}} =
             Setup.create_site(site_attrs("broken-site"), creator)

    refute Registry.get_site_by_key("broken-site")
    refute Schema.exists?("tenant_broken-site_production")
    refute File.exists?(Path.join(Brando.config(:media_path), "broken-site"))
    refute File.exists?(Path.join(Brando.config(:sites_path), "broken-site"))
  end

  test "never deletes storage that existed before provisioning", %{creator: creator} do
    existing_root = Path.join(Brando.config(:media_path), "existing-site")
    existing_file = Path.join(existing_root, "keep.txt")
    File.mkdir_p!(existing_root)
    File.write!(existing_file, "legacy")

    assert {:error, {:site_setup_failed, {:site_storage_already_exists, ^existing_root}, _compensation}} =
             Setup.create_site(site_attrs("existing-site"), creator)

    refute Registry.get_site_by_key("existing-site")
    assert File.read!(existing_file) == "legacy"
  end

  test "suspends, archives, and only permanently deletes after retention", %{creator: creator} do
    assert {:ok, site} = Setup.create_site(site_attrs("retained-site"), creator)
    assert {:ok, suspended} = Setup.suspend_site(site)
    assert suspended.status == :suspended
    refute Brando.Tenant.Cache.get_live_env(site.key)

    archived_at = DateTime.utc_now()
    assert {:ok, archived} = Setup.archive_site(suspended, now: archived_at)
    assert archived.status == :archived
    assert archived.archived_at == archived_at

    assert {:error, {:retention_period, 30}} =
             Setup.delete_site(archived, now: DateTime.add(archived_at, 29, :day))

    assert Registry.get_site(archived.id)
    assert Schema.exists?("tenant_retained-site_production")

    assert {:ok, deleted} =
             Setup.delete_site(archived, now: DateTime.add(archived_at, 30, :day))

    assert deleted.id == archived.id
    refute Registry.get_site(archived.id)
    refute Schema.exists?("tenant_retained-site_production")
    refute Schema.exists?("tenant_retained-site_staging")
    refute File.exists?(Storage.media_root(archived))
    refute File.exists?(Storage.site_root(archived))
  end

  defp site_attrs(key) do
    %{
      name: "Tenant #{key}",
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    }
  end
end
