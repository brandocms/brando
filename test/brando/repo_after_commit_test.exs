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

  # A nested transaction that rolls back fails the outer one too (`mode:
  # :savepoint` included, which only covers each statement), so nothing held
  # in either runs, though the outer carries on.
  test "a nested transaction that rolls back drops what the outer one held" do
    test = self()

    {:error, :rollback} =
      Repo.transaction(fn ->
        Repo.after_commit(:evict_pages, fn -> send(test, :outer) end)

        {:error, :undone} =
          Repo.transaction(
            fn ->
              Repo.after_commit(:evict_posts, fn -> send(test, :inner) end)
              Repo.rollback(:undone)
            end,
            mode: :savepoint
          )

        :done
      end)

    refute_received :outer
    refute_received :inner
  end

  test "a multi that fails drops what its steps held" do
    test = self()

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:hold, fn _repo, _ -> {:ok, Repo.after_commit(fn -> send(test, :held) end)} end)
      |> Ecto.Multi.run(:fail, fn _repo, _ -> {:error, :undone} end)

    assert {:error, :fail, :undone, _} = Repo.transaction(multi)
    refute_received :held

    assert {:ok, _} =
             Repo.transaction(
               Ecto.Multi.run(Ecto.Multi.new(), :hold, fn _repo, _ ->
                 {:ok, Repo.after_commit(fn -> send(test, :held) end)}
               end)
             )

    assert_received :held
  end

  test "late work runs after the rest, whenever it was held" do
    test = self()

    {:ok, _} =
      Repo.transaction(fn ->
        Repo.after_commit(:rebuild_globals, fn -> send(test, :rebuild_globals) end)
        Repo.after_commit(:render_globals, fn -> send(test, :render_globals) end, late: true)
        Repo.after_commit(:rebuild_menus, fn -> send(test, :rebuild_menus) end)
        Repo.after_commit(:render_menus, fn -> send(test, :render_menus) end, late: true)
        Repo.after_commit(fn -> send(test, :broadcast) end)
      end)

    assert [:rebuild_globals, :rebuild_menus, :broadcast, :render_globals, :render_menus] = drain()

    Repo.after_commit(:render_menus, fn -> send(test, :now) end, late: true)
    assert_received :now
  end

  defp drain do
    receive do
      message -> [message | drain()]
    after
      0 -> []
    end
  end

  test "outside a transaction, keyed work runs at once" do
    test = self()
    Repo.after_commit(:evict_pages, fn -> send(test, :now) end)
    assert_received :now
  end
end
