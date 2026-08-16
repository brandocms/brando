defmodule Brando.TenantCacheKeyTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Cache.Query
  alias Brando.Tenant

  setup do
    put_test_env(:tenancy_mode, :multi)
    Cachex.clear(:cache)
    Cachex.clear(:query)

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cachex.clear(:cache)
      Cachex.clear(:query)
    end)

    :ok
  end

  test "application cache entries are isolated by the complete tenant prefix" do
    Tenant.put_prefix("tenant_cache-a_production")
    assert {:ok, true} = Brando.Cache.put(:navigation, %{site: "a"}, :infinite)

    Tenant.put_prefix("tenant_cache-b_production")
    assert Brando.Cache.get(:navigation) == nil
    assert {:ok, true} = Brando.Cache.put(:navigation, %{site: "b"}, :infinite)

    Tenant.put_prefix("tenant_cache-a_production")
    assert Brando.Cache.get(:navigation) == %{site: "a"}

    assert {:ok, keys} = Cachex.keys(:cache)
    assert {:tenant, "tenant_cache-a_production", :navigation} in keys
    assert {:tenant, "tenant_cache-b_production", :navigation} in keys
  end

  test "query cache misses and hits independently for each environment" do
    query_key = {:list, "pages", %{status: :published}}

    Tenant.put_prefix("tenant_cache-a_production")
    assert {:miss, cache_key_a, _ttl} = Query.try_cache(query_key, true)
    assert {:ok, true} = Query.put(cache_key_a, [:site_a], :timer.minutes(1))
    assert {:hit, [:site_a]} = Query.try_cache(query_key, true)

    Tenant.put_prefix("tenant_cache-a_preview")
    assert {:miss, cache_key_preview, _ttl} = Query.try_cache(query_key, true)
    refute cache_key_a == cache_key_preview

    Tenant.put_prefix("tenant_cache-b_production")
    assert {:miss, cache_key_b, _ttl} = Query.try_cache(query_key, true)
    refute cache_key_a == cache_key_b
  end

  test "tenancy mode none preserves legacy cache keys" do
    put_test_env(:tenancy_mode, :none)
    Tenant.put_prefix(nil)

    assert {:ok, true} = Brando.Cache.put(:identity, %{name: "Legacy"}, :infinite)
    assert {:ok, %{name: "Legacy"}} = Cachex.get(:cache, :identity)
    assert {:list, "pages", _hash} = Query.hash_query({:list, "pages", %{}})
  end
end
