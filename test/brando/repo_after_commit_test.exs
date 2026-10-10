defmodule Brando.RepoAfterCommitTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Repo

  test "work held under one key runs once after the commit" do
    test = self()

    {:ok, :done} =
      Repo.transaction(fn ->
        Repo.after_commit(:evict_pages, fn -> send(test, :first) end)
        Repo.after_commit(:evict_pages, fn -> send(test, :second) end)
        Repo.after_commit(:evict_posts, fn -> send(test, :other) end)
        refute_received _
        :done
      end)

    assert_received :first
    refute_received :second
    assert_received :other
  end

  test "a rolled back transaction drops what it held, and the next one holds it again" do
    test = self()

    {:error, :undone} =
      Repo.transaction(fn ->
        Repo.after_commit(:evict_pages, fn -> send(test, :rolled_back) end)
        Repo.rollback(:undone)
      end)

    refute_received :rolled_back

    {:ok, _} = Repo.transaction(fn -> Repo.after_commit(:evict_pages, fn -> send(test, :committed) end) end)
    assert_received :committed
  end

  test "outside a transaction, keyed work runs at once" do
    test = self()
    Repo.after_commit(:evict_pages, fn -> send(test, :now) end)
    assert_received :now
  end
end
