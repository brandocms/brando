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

  # The write has committed: work that fails must not keep the rest from
  # running, nor fail the caller.
  test "held work that raises or exits does not stop the rest" do
    test = self()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, :done} =
                 Repo.transaction(fn ->
                   Repo.after_commit(fn -> raise "revoking failed" end)
                   Repo.after_commit(:evict_pages, fn -> exit(:gone) end)
                   Repo.after_commit(:evict_posts, fn -> send(test, :ran) end)
                   :done
                 end)
      end)

    assert_received :ran
    assert log =~ "revoking failed"
    assert log =~ ":evict_pages"
  end

  test "outside a transaction, keyed work runs at once" do
    test = self()
    Repo.after_commit(:evict_pages, fn -> send(test, :now) end)
    assert_received :now
  end
end
