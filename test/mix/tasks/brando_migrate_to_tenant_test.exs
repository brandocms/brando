defmodule Mix.Tasks.BrandoMigrateToTenantTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Environments.Schema
  alias Mix.Tasks.Brando.MigrateToTenant

  defmodule PublicMigrator do
    @behaviour Brando.Tenant.PublicDataMigrator

    @impl true
    def migrate(source_prefix, target_prefix) do
      send(self(), {:public_data_migrated, source_prefix, target_prefix})
      :ok
    end
  end

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
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

  describe "media size reporting" do
    test "sums a directory tree recursively" do
      root = Path.join(System.tmp_dir!(), "brando-media-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "images/thumb"))
      File.write!(Path.join(root, "images/a.jpg"), String.duplicate("x", 1000))
      File.write!(Path.join(root, "images/thumb/b.jpg"), String.duplicate("x", 500))
      on_exit(fn -> File.rm_rf(root) end)

      assert MigrateToTenant.directory_size(root) == 1500
    end

    test "a missing path is zero rather than a crash" do
      assert MigrateToTenant.directory_size("/nope/does/not/exist") == 0
    end

    test "reports sizes in the unit an operator reads" do
      assert MigrateToTenant.format_bytes(512) == "512 B"
      assert MigrateToTenant.format_bytes(5_700_000_000) == "5.7 GB"
      assert MigrateToTenant.format_bytes(88_000_000) == "88.0 MB"
    end
  end

  test "requires a site key" do
    Mix.Task.reenable("brando.migrate_to_tenant")

    assert_raise Mix.Error, ~r/--site-key is required/, fn ->
      Mix.Tasks.Brando.MigrateToTenant.run([])
    end
  end

  describe "--source-schema" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
      Mix.Task.reenable("brando.migrate_to_tenant")
      :ok
    end

    test "is refused outside :multi" do
      put_test_env(:tenancy_mode, :single)

      assert_raise Mix.Error, ~r/needs tenancy_mode: :multi/, fn ->
        MigrateToTenant.run(~w(--site-key=acme --source-schema=import_acme --source-media=/tmp --creator-email=a@b.c))
      end
    end

    test "refuses --move, as the source is only read" do
      put_test_env(:tenancy_mode, :multi)

      assert_raise Mix.Error, ~r/--move cannot be used with --source-schema/, fn ->
        MigrateToTenant.run(
          ~w(--site-key=acme --source-schema=import_acme --source-media=/tmp --creator-email=a@b.c --move)
        )
      end
    end

    test "requires --creator-email and --source-media" do
      put_test_env(:tenancy_mode, :multi)

      assert_raise Mix.Error, ~r/--creator-email is required/, fn ->
        MigrateToTenant.run(~w(--site-key=acme --source-schema=import_acme --source-media=/tmp))
      end

      Mix.Task.reenable("brando.migrate_to_tenant")

      assert_raise Mix.Error, ~r/--source-media is required/, fn ->
        MigrateToTenant.run(~w(--site-key=acme --source-schema=import_acme --creator-email=a@b.c))
      end
    end

    test "--source-media is refused without it" do
      put_test_env(:tenancy_mode, :multi)

      assert_raise Mix.Error, ~r/--source-media needs --source-schema/, fn ->
        MigrateToTenant.run(~w(--site-key=acme --source-media=/tmp))
      end
    end

    test "stops on a schema that does not exist, before creating anything" do
      put_test_env(:tenancy_mode, :multi)
      Brando.Factory.insert(:random_user, email: "importer@example.com", role: :superuser)

      assert_raise Mix.Error, ~r/source_schema_not_found/, fn ->
        MigrateToTenant.run(
          ~w(--site-key=acme --source-schema=import_missing --source-media=/tmp --creator-email=importer@example.com)
        )
      end

      refute Brando.Tenant.Registry.get_site_by_key("acme")
    end
  end

  describe "a failed migration's message" do
    test "says the new site was removed" do
      message = MigrateToTenant.failure_message("acme", {:public_migration_failed, :public_copy_failed, :ok})

      assert message =~ ":public_copy_failed"
      assert message =~ "The new site acme was removed"
    end

    test "says what is left, and how to remove it, when removing the site failed" do
      message =
        MigrateToTenant.failure_message("acme", {:public_migration_failed, :public_copy_failed, {:error, :busy}})

      assert message =~ "The new site acme could not be removed (:busy)"
      assert message =~ "tenant_acme_"
      assert message =~ "media/acme"
      assert message =~ ~s|Brando.Tenant.Setup.delete_site(site, force: true, actor: :system)|
    end

    test "says nothing was created when the site was never made" do
      assert MigrateToTenant.failure_message("acme", {:site_setup_failed, :seed_failed, :ok}) =~ ":seed_failed"
      refute MigrateToTenant.failure_message("acme", :forbidden) =~ "removed"
    end
  end

  describe "without --source-schema" do
    setup do
      root = Path.join(System.tmp_dir!(), "brando-migrate-task-#{System.unique_integer([:positive])}")
      put_test_env(:tenancy_mode, :multi)
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, StructureCloner)
      put_test_env(:environment_schema_cloner, SchemaCloner)
      put_test_env(:tenant_public_data_migrator, PublicMigrator)
      put_test_env(:media_path, Path.join(root, "media"))
      put_test_env(:sites_path, Path.join(root, "sites"))
      Brando.Tenant.Cache.clear()
      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("brando.migrate_to_tenant")

      on_exit(fn ->
        Mix.shell(Mix.Shell.IO)
        File.rm_rf(root)
        Brando.Tenant.put_prefix(nil)
        Brando.Tenant.Cache.clear()
      end)

      Brando.Factory.insert(:random_user, role: :superuser)
      :ok
    end

    test "copies this installation's public schema, as before" do
      legacy_file = Path.join([Brando.config(:media_path), "images", "legacy.txt"])
      File.mkdir_p!(Path.dirname(legacy_file))
      File.write!(legacy_file, "legacy media")

      MigrateToTenant.run(~w(--site-key=legacy-task))

      assert_received {:public_data_migrated, "public", "tenant_legacy-task_production"}

      assert_received {:mix_shell, :info,
                       ["Copied public content into site legacy-task with Production and Staging environments"]}

      assert File.read!(Path.join([Brando.config(:media_path), "legacy-task", "images", "legacy.txt"])) == "legacy media"
      assert File.read!(legacy_file) == "legacy media"
    end
  end
end
