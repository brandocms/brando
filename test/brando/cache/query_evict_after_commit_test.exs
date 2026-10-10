defmodule Brando.Cache.QueryEvictAfterCommitTest do
  @moduledoc """
  A write inside a transaction evicts its cached queries at once, before the
  commit. A read in between (another process, which still sees the old row)
  caches the old row again, and it stayed cached for the query's TTL. These
  tests put the old row back in the cache at that point, as such a read
  does, and check it is gone once the transaction has committed.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Authorization.Migration
  alias Brando.Cache.Query, as: CacheQuery
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Tenant

  setup do
    on_exit(fn -> Cachex.clear(:query) end)
    Cachex.clear(:query)
    :ok
  end

  describe "a generated update with group authorization" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      owner = Factory.insert(:random_user, role: :superuser)
      {:ok, _} = Migration.run()
      page = Factory.insert(:page, title: "Before")
      %{owner: owner, page: page}
    end

    test "leaves no old row cached by a read before its commit", %{owner: owner, page: page} do
      args = %{matches: %{id: page.id}, cache: true}
      assert {:ok, %{title: "Before"}} = Pages.get_page(args)
      stale = cached_entries()
      assert stale != []

      # Between the page's UPDATE and the commit, the next query of the
      # save is where a concurrent read would land.
      recache_after_update(stale, fn ->
        assert {:ok, %{title: "After"}} = Pages.update_page(page.id, %{title: "After"}, owner)
      end)

      assert {:ok, %{title: "After"}} = Pages.get_page(args)
    end
  end

  describe "Brando.Query writes inside a transaction" do
    test "update evicts again once it has committed" do
      page = Factory.insert(:page, title: "Before")
      args = %{matches: %{id: page.id}, cache: true}
      assert {:ok, %{title: "Before"}} = Pages.get_page(args)
      stale = cached_entries()

      assert {:ok, _} =
               Brando.Repo.transaction(fn ->
                 {:ok, updated} = page |> Page.changeset(%{title: "After"}, :system) |> Brando.Query.update()
                 put_entries(stale)
                 updated
               end)

      assert {:ok, %{title: "After"}} = Pages.get_page(args)
    end

    test "a rolled back write leaves the cache to what it was" do
      page = Factory.insert(:page, title: "Before")
      args = %{matches: %{id: page.id}, cache: true}
      assert {:ok, %{title: "Before"}} = Pages.get_page(args)
      stale = cached_entries()

      assert {:error, :undone} =
               Brando.Repo.transaction(fn ->
                 {:ok, _} = page |> Page.changeset(%{title: "After"}, :system) |> Brando.Query.update()
                 put_entries(stale)
                 Brando.Repo.rollback(:undone)
               end)

      assert cached_entries() == stale
    end

    test "evicts under the tenant prefix of the write, not the one restored after it" do
      put_test_env(:tenancy_mode, :multi)
      prefix = "tenant_evict-commit_production"
      on_exit(fn -> Tenant.put_prefix(nil) end)
      Tenant.put_prefix(nil)

      Tenant.with_prefix(prefix, fn ->
        {:miss, key, _ttl} = CacheQuery.try_cache({:list, "pages", %{}}, true)
        CacheQuery.put(key, [:old], :timer.minutes(1))
      end)

      stale = cached_entries()
      assert [{{:tenant, ^prefix, _}, _}] = stale

      {:ok, :done} =
        Brando.Repo.transaction(fn ->
          Tenant.with_prefix(prefix, fn ->
            CacheQuery.evict({:ok, %Page{id: 1}})
            put_entries(stale)
          end)

          :done
        end)

      assert cached_entries() == []
    end
  end

  defp cached_entries do
    {:ok, keys} = Cachex.keys(:query)
    keys |> Enum.map(&{&1, elem(Cachex.get(:query, &1), 1)}) |> Enum.sort()
  end

  defp put_entries(entries), do: Enum.each(entries, fn {key, value} -> Cachex.put(:query, key, value) end)

  # Puts `entries` back in the cache at the first query after the pages
  # UPDATE that runs in this process.
  defp recache_after_update(entries, fun) do
    handler = "recache-#{System.unique_integer([:positive])}"
    test_pid = self()
    state = :counters.new(1, [])

    :telemetry.attach(
      handler,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        cond do
          self() != test_pid ->
            :ok

          :counters.get(state, 1) == 0 and metadata.source == "pages" and String.starts_with?(metadata.query, "UPDATE") ->
            :counters.put(state, 1, 1)

          :counters.get(state, 1) == 1 ->
            :counters.put(state, 1, 2)
            put_entries(entries)

          true ->
            :ok
        end
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    assert :counters.get(state, 1) == 2, "the save ran no query after the pages UPDATE"
  end
end
