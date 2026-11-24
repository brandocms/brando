defmodule Brando.Content.TrashedModuleRaceTest do
  # A module's delete against a save or restore that brings it into use, each
  # on its own connection (#3902): the sandbox shares one connection between
  # processes, so the rows are committed here and removed after each test.
  # Whichever reaches the module's row first wins; the other waits for it to
  # commit, and is refused.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.Block
  alias Brando.Content.Module
  alias Brando.Pages
  alias Brando.Pages.Page
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    {user, module, page} =
      unboxed(fn ->
        user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)

        {:ok, module} =
          Brando.Content.create_module(
            Brando.Factory.params_for(:module, name: %{"en" => "Teaser"}, code: "<p>teaser</p>", vars: [], refs: []),
            user
          )

        changeset =
          %Page{}
          |> Page.changeset(Brando.Factory.params_for(:page), user)
          |> Map.put(:action, :insert)

        {:ok, page} = Pages.create_page(changeset, user)
        {user, module, page}
      end)

    on_exit(fn -> unboxed(fn -> clean_up(user, module) end) end)

    %{user: user, module: module, page: page}
  end

  describe "a save adding a block of the module" do
    test "that waits for the delete is refused", c do
      holder = hold(fn -> Brando.Content.delete_module(c.module.id, :system) end)
      save = waiter(fn -> add_block(c.page, c.module, c.user) end)
      send(holder.pid, :commit)
      assert {:ok, {:ok, %{deleted_at: %DateTime{}}}} = Task.await(holder, 10_000)

      assert {:error, {:module_in_trash, _}} = Task.await(save, 10_000)
      assert block_count(c.module) == 0
    end

    test "that the delete waits for refuses the delete", c do
      holder = hold(fn -> add_block(c.page, c.module, c.user) end)
      delete = waiter(fn -> Brando.Content.delete_module(c.module.id, :system) end)
      send(holder.pid, :commit)
      assert {:ok, {:ok, _page}} = Task.await(holder, 10_000)

      assert {:error, :module_in_use} = Task.await(delete, 10_000)
      assert %{deleted_at: nil} = unboxed(fn -> Repo.get!(Module, c.module.id) end)
    end
  end

  describe "restoring an entry holding a block of the module" do
    setup c do
      trashed =
        unboxed(fn ->
          {:ok, _} = add_block(c.page, c.module, c.user)
          {:ok, trashed} = Pages.delete_page(c.page.id, c.user)
          trashed
        end)

      %{trashed: trashed}
    end

    test "that waits for the delete is refused", c do
      holder = hold(fn -> Brando.Content.delete_module(c.module.id, c.user) end)
      restore = waiter(fn -> Boundary.restore(:system, c.trashed) end)
      send(holder.pid, :commit)
      assert {:ok, {:ok, _module}} = Task.await(holder, 10_000)

      assert {:error, {:module_in_trash, _}} = Task.await(restore, 10_000)
      assert %{deleted_at: %DateTime{}} = unboxed(fn -> Repo.get!(Page, c.page.id) end)
    end

    test "that the delete waits for refuses the delete", c do
      holder = hold(fn -> Boundary.restore(c.user, c.trashed) end)
      delete = waiter(fn -> Brando.Content.delete_module(c.module.id, :system) end)
      send(holder.pid, :commit)
      assert {:ok, {:ok, %{deleted_at: nil}}} = Task.await(holder, 10_000)

      assert {:error, :module_in_use} = Task.await(delete, 10_000)
    end
  end

  # The form's save adding one root block of `module`
  defp add_block(page, module, user) do
    block = %{
      type: :module,
      module_id: module.id,
      source: "Elixir.Brando.Pages.Page.Blocks",
      uid: Brando.Utils.generate_uid()
    }

    page
    |> Repo.preload(:entry_blocks, force: true)
    |> Page.changeset(%{}, user)
    |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
    |> Pages.update_page(user)
  end

  defp block_count(module),
    do: unboxed(fn -> Repo.aggregate(from(b in Block, where: b.module_id == ^module.id), :count) end)

  # Runs `fun` in a transaction that commits when told to
  defp hold(fun) do
    test = self()
    holder = Task.async(fn -> unboxed(fn -> Repo.transaction(fn -> run_and_hold(fun, test) end) end) end)
    assert_receive :holding, 10_000
    holder
  end

  defp run_and_hold(fun, test) do
    result = fun.()
    send(test, :holding)

    receive do
      :commit -> result
    after
      10_000 -> raise "never told to commit"
    end
  end

  # Runs `fun` on a connection of its own, and returns once that connection
  # waits for a lock
  defp waiter(fun) do
    test = self()

    task =
      Task.async(fn ->
        unboxed(fn ->
          %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
          send(test, {:backend, backend})
          fun.()
        end)
      end)

    assert_receive {:backend, backend}, 10_000
    wait_for_lock(backend)
    task
  end

  defp wait_for_lock(backend, attempts \\ 500)
  defp wait_for_lock(_backend, 0), do: flunk("nothing waited for the lock")

  defp wait_for_lock(backend, attempts) do
    unless unboxed(fn -> Repo.exists?(from(l in "pg_locks", where: l.pid == ^backend and not l.granted)) end) do
      Process.sleep(10)
      wait_for_lock(backend, attempts - 1)
    end
  end

  # What the setup and the tests wrote, which no sandbox rolls back
  defp clean_up(user, module) do
    pages = Repo.all(from(p in Page, where: p.creator_id == ^user.id, select: p.id))
    schema = to_string(Page)

    Repo.query!("DELETE FROM content_identifiers WHERE schema = $1 AND entry_id = ANY($2)", [schema, pages])
    Repo.query!("DELETE FROM search_documents WHERE schema = $1 AND entry_id = ANY($2)", [schema, pages])

    Repo.delete_all(
      from(e in Brando.Activity.Event, where: e.user_id == ^user.id or (e.schema == ^schema and e.entry_id in ^pages))
    )

    Repo.delete_all(from(r in Brando.Revisions.Revision, where: r.creator_id == ^user.id))
    Repo.delete_all(from(j in Page.Blocks, where: j.entry_id in ^pages))
    Repo.delete_all(from(p in Page, where: p.id in ^pages))
    Repo.delete_all(from(b in Block, where: b.module_id == ^module.id))
    Repo.delete_all(from(m in Module, where: m.id == ^module.id))
    Repo.delete_all(from(e in Brando.Users.SecurityEvent, where: e.user_id == ^user.id))
    Repo.delete_all(from(u in Brando.Users.User, where: u.id == ^user.id))
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)
end
