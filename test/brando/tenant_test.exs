defmodule Brando.TenantTest do
  use ExUnit.Case, async: false

  alias Brando.Environments.Environment
  alias Brando.Exception.ConfigError
  alias Brando.Sites.Site
  alias Brando.Tenant

  import Brando.Test.Support

  setup do
    Tenant.put_prefix(nil)
    on_exit(fn -> Tenant.put_prefix(nil) end)
    :ok
  end

  test "tenancy is disabled by default and keeps the public schema" do
    put_test_env(:tenancy_mode, :none)

    refute Tenant.enabled?()
    assert Tenant.mode() == :none

    Tenant.put_prefix("tenant_acme_production")
    assert Tenant.current_prefix() == nil
  end

  test "single and multi modes enable tenancy" do
    put_test_env(:tenancy_mode, :single)
    put_test_env(:site_key, "acme")

    assert Tenant.enabled?()
    assert Tenant.validate_config!() == :ok

    Application.put_env(:brando, :tenancy_mode, :multi)
    assert Tenant.mode() == :multi
    assert Tenant.validate_config!() == :ok
  end

  test "single mode requires a valid configured site key" do
    put_test_env(:tenancy_mode, :single)
    put_test_env(:site_key, nil)

    assert_raise ConfigError, ~r/Invalid or missing :site_key/, fn ->
      Tenant.validate_config!()
    end

    Application.put_env(:brando, :site_key, "Not URL Safe")

    assert_raise ConfigError, ~r/Invalid or missing :site_key/, fn ->
      Tenant.validate_config!()
    end
  end

  test "invalid tenancy modes fail validation instead of silently enabling" do
    put_test_env(:tenancy_mode, :unexpected)

    assert_raise ConfigError, ~r/Invalid :tenancy_mode/, fn ->
      Tenant.validate_config!()
    end
  end

  test "prefixes are derived from generic site and environment keys" do
    site = %Site{key: "acme-corp"}
    environment = %Environment{key: "spring-redesign"}

    assert Tenant.prefix(site, environment) == "tenant_acme-corp_spring-redesign"
    assert Tenant.prefix("acme", "production") == "tenant_acme_production"

    assert_raise ArgumentError, fn -> Tenant.prefix("Acme", "production") end
  end

  test "process prefix context is restored after scoped work, including failures" do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix("tenant_acme_production")

    assert Tenant.with_prefix("tenant_acme_staging", fn -> Tenant.current_prefix() end) ==
             "tenant_acme_staging"

    assert Tenant.current_prefix() == "tenant_acme_production"

    assert_raise RuntimeError, fn ->
      Tenant.with_prefix("tenant_acme_staging", fn -> raise "failure" end)
    end

    assert Tenant.current_prefix() == "tenant_acme_production"
  end

  test "arbitrary schema names cannot enter the process context" do
    assert_raise ArgumentError, ~r/invalid tenant prefix/, fn ->
      Tenant.put_prefix("public; DROP SCHEMA public")
    end
  end
end
