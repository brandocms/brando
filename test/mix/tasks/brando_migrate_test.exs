defmodule Mix.Tasks.BrandoMigrateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Brando.Migrate

  describe "validate_options!/3" do
    test "accepts a bare invocation" do
      # `nil and ...` raised BadBooleanError, so plain `mix brando.migrate` failed.
      assert :ok = Migrate.validate_options!([], [], [])
    end

    test "accepts each scope on its own" do
      assert :ok = Migrate.validate_options!([tenants: true], [], [])
      assert :ok = Migrate.validate_options!([site: "acme"], [], [])
    end

    test "rejects both scopes together" do
      assert_raise Mix.Error, ~r/Choose either --tenants or --site/, fn ->
        Migrate.validate_options!([tenants: true, site: "acme"], [], [])
      end
    end

    test "rejects positional and unknown arguments" do
      assert_raise Mix.Error, ~r/Invalid arguments/, fn ->
        Migrate.validate_options!([], ["extra"], [])
      end

      assert_raise Mix.Error, ~r/Invalid arguments/, fn ->
        Migrate.validate_options!([], [], [{"--bogus", nil}])
      end
    end
  end
end
