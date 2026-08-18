defmodule Brando.TenantMigrationTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Environments.Schema
  alias Brando.Tenant.Migration
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

  defmodule PublicMigrator do
    @behaviour Brando.Tenant.PublicDataMigrator

    @impl true
    def migrate(source_prefix, target_prefix) do
      send(self(), {:public_data_migrated, source_prefix, target_prefix})
      :ok
    end
  end

  defmodule FailingPublicMigrator do
    @behaviour Brando.Tenant.PublicDataMigrator

    @impl true
    def migrate(_source_prefix, _target_prefix), do: {:error, :public_copy_failed}
  end

  defmodule FailingMediaMigrator do
    @behaviour Brando.Tenant.PublicMediaMigrator

    @impl true
    def migrate(_site), do: {:error, :media_copy_failed}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-tenant-migration-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()
    end)

    creator = Brando.Factory.insert(:random_user, role: :superuser)
    %{creator: creator}
  end

  test "copies public content into Production before creating Staging", %{creator: creator} do
    legacy_file = Path.join([Brando.config(:media_path), "images", "legacy.txt"])
    File.mkdir_p!(Path.dirname(legacy_file))
    File.write!(legacy_file, "legacy media")

    assert {:ok, site} =
             Migration.migrate_public(site_attrs("legacy-migration"), creator, public_data_migrator: PublicMigrator)

    assert_received {:public_data_migrated, "public", "tenant_legacy-migration_production"}

    assert Enum.map(site.environments, &{&1.key, &1.live}) |> Enum.sort() ==
             [{"production", true}, {"staging", false}]

    assert Schema.exists?("tenant_legacy-migration_production")
    assert Schema.exists?("tenant_legacy-migration_staging")

    assert File.read!(Path.join([Brando.config(:media_path), site.key, "images", "legacy.txt"])) ==
             "legacy media"

    assert File.read!(legacy_file) == "legacy media"
  end

  test "removes the partial site when public data copying fails", %{creator: creator} do
    assert {:error, {:public_migration_failed, :public_copy_failed, :ok}} =
             Migration.migrate_public(site_attrs("failed-legacy-migration"), creator,
               public_data_migrator: FailingPublicMigrator
             )

    refute Registry.get_site_by_key("failed-legacy-migration")
    refute Schema.exists?("tenant_failed-legacy-migration_production")
  end

  test "removes the partial tenant but preserves legacy media when media copying fails", %{creator: creator} do
    legacy_file = Path.join([Brando.config(:media_path), "files", "legacy.txt"])
    File.mkdir_p!(Path.dirname(legacy_file))
    File.write!(legacy_file, "keep me")

    assert {:error, {:public_migration_failed, :media_copy_failed, :ok}} =
             Migration.migrate_public(site_attrs("failed-media-migration"), creator,
               public_data_migrator: PublicMigrator,
               public_media_migrator: FailingMediaMigrator
             )

    refute Registry.get_site_by_key("failed-media-migration")
    assert File.read!(legacy_file) == "keep me"
    refute File.exists?(Path.join(Brando.config(:media_path), "failed-media-migration"))
  end

  defp site_attrs(key) do
    %{
      name: "Legacy",
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    }
  end
end
