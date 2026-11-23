defmodule Brando.Cache.QuerySkipInTransactionTest do
  @moduledoc """
  `Brando.Cache.Query.skip_in_transaction/0`: in a transaction that will be
  rolled back, no query result is cached, and none cached before is read,
  since its rows may differ from what the transaction sees.
  """
  use Brando.ConnCase, async: false

  alias Brando.Cache.Query, as: CacheQuery
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Repo

  setup do
    on_exit(fn -> Cachex.clear(:query) end)
    Cachex.clear(:query)
    :ok
  end

  test "puts nothing in the cache for the rest of the transaction" do
    Repo.transaction(fn ->
      assert CacheQuery.skip_in_transaction() == :ok

      CacheQuery.put({:list, "pages", "skipped"}, [:row])
      CacheQuery.put({:single, "pages", "skipped"}, %{id: 1}, :timer.minutes(1), 1)
      CacheQuery.put({:tenant, "prefix", {:single, "pages", "skipped"}}, %{id: 1}, :timer.minutes(1), 1)
    end)

    assert Cachex.size!(:query) == 0

    # Without the skip, the same puts are cached
    Repo.transaction(fn -> CacheQuery.put({:list, "pages", "kept"}, [:row]) end)
    assert Cachex.size!(:query) == 1
  end

  test "reads no result cached before the transaction" do
    CacheQuery.put({:list, "pages", "warm"}, [:row])

    Repo.transaction(fn ->
      assert CacheQuery.get({:list, "pages", "warm"}) == [:row]
      CacheQuery.skip_in_transaction()
      assert CacheQuery.get({:list, "pages", "warm"}) == nil
    end)

    assert CacheQuery.get({:list, "pages", "warm"}) == [:row]
  end

  test "a cached query reads the transaction's rows and caches none of them" do
    page = Factory.insert(:page, title: "Before")
    args = %{matches: %{id: page.id}, cache: true}
    assert {:ok, %{title: "Before"}} = Pages.get_page(args)
    cached = Cachex.size!(:query)

    Repo.transaction(fn ->
      CacheQuery.skip_in_transaction()
      Repo.update_all(Ecto.Query.from(p in Page, where: p.id == ^page.id), set: [title: "Inside"])
      assert {:ok, %{title: "Inside"}} = Pages.get_page(args)
      assert {:ok, _} = Pages.list_pages(%{cache: true})
      Repo.rollback(:done)
    end)

    assert Cachex.size!(:query) == cached
    assert {:ok, %{title: "Before"}} = Pages.get_page(args)
  end

  test "is refused outside a transaction" do
    assert CacheQuery.skip_in_transaction() == :error
  end
end
