Code.require_file("../../support/mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Brando.GenTenantMigrationTest do
  use ExUnit.Case, async: false

  import MixHelper

  test "generates migrations in the tenant migration path" do
    in_tmp("tenant_migration_generator", fn ->
      path = Path.expand("priv/repo/tenant_migrations")

      Mix.Tasks.Brando.Gen.TenantMigration.run([
        "add_projects",
        "--migrations-path",
        path
      ])

      assert [migration] = Path.wildcard(Path.join(path, "*_add_projects.exs"))
      contents = File.read!(migration)
      assert contents =~ "defmodule BrandoIntegration.Repo.Migrations.AddProjects"
      assert contents =~ "use Ecto.Migration"
    end)
  end

  test "requires exactly one migration name" do
    assert_raise Mix.Error, ~r/Usage/, fn ->
      Mix.Tasks.Brando.Gen.TenantMigration.run([])
    end
  end
end
