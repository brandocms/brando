defmodule Mix.Tasks.BrandoMigrateToTenantTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Brando.MigrateToTenant

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
end
