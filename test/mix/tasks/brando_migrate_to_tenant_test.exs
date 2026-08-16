defmodule Mix.Tasks.BrandoMigrateToTenantTest do
  use ExUnit.Case, async: false

  test "requires a site key" do
    Mix.Task.reenable("brando.migrate_to_tenant")

    assert_raise Mix.Error, ~r/--site-key is required/, fn ->
      Mix.Tasks.Brando.MigrateToTenant.run([])
    end
  end
end
