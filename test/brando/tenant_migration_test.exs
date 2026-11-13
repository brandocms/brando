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

  defmodule RaisingPublicMigrator do
    @behaviour Brando.Tenant.PublicDataMigrator

    @impl true
    def migrate(_source_prefix, _target_prefix), do: raise("copy blew up")
  end

  defmodule RelocatingPublicMigrator do
    @behaviour Brando.Tenant.PublicDataMigrator

    @impl true
    def migrate(source_prefix, target_prefix) do
      send(self(), {:public_data_migrated, source_prefix, target_prefix})
      :ok
    end

    @impl true
    def relocates?, do: true
  end

  defmodule FailingRelocatingPublicMigrator do
    @behaviour Brando.Tenant.PublicDataMigrator

    @impl true
    def migrate(_source_prefix, _target_prefix), do: {:error, :public_copy_failed}

    @impl true
    def relocates?, do: true
  end

  defmodule FailingMediaMigrator do
    @behaviour Brando.Tenant.PublicMediaMigrator

    @impl true
    def migrate(_site), do: {:error, :media_copy_failed}
  end

  defmodule RaisingMediaMigrator do
    @behaviour Brando.Tenant.PublicMediaMigrator

    @impl true
    def migrate(_site), do: raise("media blew up")
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

  test "removes the partial site under group authorization, with no scope in the process" do
    put_test_env(:authorization_mode, :groups)
    owner = Brando.Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Brando.Authorization.Migration.run()
    scope = Brando.Authorization.Scope.installation(owner)

    # May create sites, not delete them
    {:ok, group} =
      Brando.Authorization.Groups.create(scope, %{name: "Site provisioners"}, [
        "brando.admin.access",
        "brando.sites.create"
      ])

    provisioner = Brando.Factory.insert(:random_user, role: :admin)
    {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, provisioner.id)
    refute Brando.Authorization.Boundary.current_scope()

    assert {:error, {:public_migration_failed, :public_copy_failed, :ok}} =
             Migration.migrate_public(site_attrs("grouped-failed-migration"), provisioner,
               public_data_migrator: FailingPublicMigrator
             )

    refute Registry.get_site_by_key("grouped-failed-migration")
    refute Schema.exists?("tenant_grouped-failed-migration_production")
    refute File.exists?(Path.join(Brando.config(:media_path), "grouped-failed-migration"))
  end

  test "removes the partial site when the copy raises", %{creator: creator} do
    assert {:error, {:public_migration_failed, {:raised, message}, :ok}} =
             Migration.migrate_public(site_attrs("raising-migration"), creator,
               public_data_migrator: RaisingPublicMigrator
             )

    assert message =~ "copy blew up"
    refute Registry.get_site_by_key("raising-migration")
    refute Schema.exists?("tenant_raising-migration_production")
  end

  describe "after a migrator that relocates the content" do
    test "keeps the site and its Production schema when a later step fails", %{creator: creator} do
      assert {:error, {:migration_incomplete, :media, :media_copy_failed}} =
               Migration.migrate_public(site_attrs("relocated-media"), creator,
                 public_data_migrator: RelocatingPublicMigrator,
                 public_media_migrator: FailingMediaMigrator
               )

      assert_received {:public_data_migrated, "public", "tenant_relocated-media_production"}
      assert %{} = Registry.get_site_by_key("relocated-media")
      assert Schema.exists?("tenant_relocated-media_production")
    end

    test "the task says where the content is and how to finish, and its commands do", %{creator: creator} do
      legacy_file = Path.join([Brando.config(:media_path), "images", "legacy.txt"])
      File.mkdir_p!(Path.dirname(legacy_file))
      File.write!(legacy_file, "legacy media")

      assert {:error, reason} =
               Migration.migrate_public(site_attrs("relocated-finish"), creator,
                 public_data_migrator: RelocatingPublicMigrator,
                 public_media_migrator: FailingMediaMigrator
               )

      message = Mix.Tasks.Brando.MigrateToTenant.failure_message("relocated-finish", reason)
      assert message =~ "Copying the media failed: :media_copy_failed"
      assert message =~ "now lives in the schema tenant_relocated-finish_production"
      refute message =~ "removed"

      [_, command] = Regex.run(~r/mix run -e '(.*)'/s, message)
      Code.eval_string(command)

      site = Registry.get_site_by_key("relocated-finish")
      assert Enum.map(site.environments, & &1.key) |> Enum.sort() == ["production", "staging"]
      assert File.read!(Path.join([Brando.config(:media_path), site.key, "images", "legacy.txt"])) == "legacy media"
    end

    test "keeps the site when a later step raises", %{creator: creator} do
      assert {:error, {:migration_incomplete, :media, {:raised, message}}} =
               Migration.migrate_public(site_attrs("relocated-raise"), creator,
                 public_data_migrator: RelocatingPublicMigrator,
                 public_media_migrator: RaisingMediaMigrator
               )

      assert message =~ "media blew up"
      assert Registry.get_site_by_key("relocated-raise")
      assert Schema.exists?("tenant_relocated-raise_production")
    end

    test "removes the site when the relocation itself fails", %{creator: creator} do
      assert {:error, {:public_migration_failed, :public_copy_failed, :ok}} =
               Migration.migrate_public(site_attrs("relocation-failed"), creator,
                 public_data_migrator: FailingRelocatingPublicMigrator
               )

      refute Registry.get_site_by_key("relocation-failed")
    end
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
