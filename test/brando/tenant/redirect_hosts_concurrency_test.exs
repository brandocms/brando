defmodule Brando.Tenant.RedirectHostsConcurrencyTest do
  # A host is bound once in the installation also when two writes run at
  # once, on their own connections: the second waits for the first to commit,
  # then sees its host and is refused.
  use ExUnit.Case, async: false

  import Brando.Test.Support
  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    put_test_env(:tenancy_mode, :none)

    {site, first, second} =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, site} =
          Registry.create_site(%{name: "Acme", key: "acme-race", languages: ["en"], default_language: "en"})

        {:ok, first} =
          Registry.create_environment(site, %{name: "One", key: "one", domain: "one.race.test"}, actor: :system)

        {:ok, second} =
          Registry.create_environment(site, %{name: "Two", key: "two", domain: "two.race.test"}, actor: :system)

        {site, first, second}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn -> delete_site(site) end)
      Cache.clear()
    end)

    %{first: first, second: second}
  end

  # The first write commits only once the second is waiting for the lock
  defp race({first, first_attrs}, {second, second_attrs}) do
    parent = self()

    holder = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> write_and_hold(parent, first, first_attrs) end) end)

    assert_receive :written, 5_000

    contender =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn -> Registry.update_environment(second, second_attrs, actor: :system) end)
      end)

    wait_for_lock_waiter()
    send(holder.pid, :commit)

    assert {:ok, :ok} = Task.await(holder, 10_000)
    Task.await(contender, 10_000)
  end

  defp write_and_hold(parent, environment, attrs) do
    Repo.transaction(fn ->
      {:ok, _} = Registry.update_environment(environment, attrs, actor: :system)
      send(parent, :written)

      receive do
        :commit -> :ok
      after
        10_000 -> raise "the second write never waited"
      end
    end)
  end

  defp wait_for_lock_waiter(waiters \\ 1, attempts \\ 200)
  defp wait_for_lock_waiter(_waiters, 0), do: flunk("the writes did not wait for the lock")

  defp wait_for_lock_waiter(waiters, attempts) do
    waiting =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.one(
          from(l in "pg_locks",
            where:
              l.locktype == "advisory" and not l.granted and
                fragment("? = (SELECT oid FROM pg_database WHERE datname = current_database())", l.database),
            select: count()
          )
        )
      end)

    if waiting >= waiters do
      :ok
    else
      Process.sleep(10)
      wait_for_lock_waiter(waiters, attempts - 1)
    end
  end

  defmodule NoopSchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, _target_prefix), do: :ok
  end

  # A live switch on a dynamic site with three environments takes the host
  # lock (through the trigger) and then writes every row of the site; a hosts
  # save on the third row holds that row, then needs the host lock. Neither
  # may wait for the other while holding what the other needs.
  test "a live switch and a hosts save on a third environment both complete", %{first: first, second: second} do
    site = dynamic_with_live(first)

    third =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, third} =
          Registry.create_environment(site, %{name: "Three", key: "three", domain: "three.race.test"}, actor: :system)

        third
      end)

    parent = self()

    saver =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            locked = Repo.one(from(e in Environment, where: e.id == ^third.id, lock: "FOR UPDATE"), prefix: "public")
            send(parent, :row_locked)

            receive do
              :save -> Registry.update_environment(locked, %{redirect_hosts: ["www.three.race.test"]}, actor: :system)
            after
              10_000 -> raise "never told to save"
            end
          end)
        end)
      end)

    assert_receive :row_locked, 5_000

    switcher = set_live_task(second)

    wait_for_row_lock_waiter()
    send(saver.pid, :save)

    assert {:ok, {:ok, %Environment{redirect_hosts: ["www.three.race.test"]}}} = Task.await(saver, 15_000)
    assert {:ok, %Environment{live: true, domain: "one.race.test"}} = Task.await(switcher, 15_000)

    Sandbox.unboxed_run(Repo, fn ->
      assert Registry.get_environment(first.id).domain == "two.race.test"
      assert Registry.get_environment(third.id).redirect_hosts == ["www.three.race.test"]
    end)
  end

  # The switch takes the host lock before it releases the outgoing domain: a
  # write binding that domain on another site meanwhile waits for nothing the
  # switch holds, and is refused, as the domain is still bound
  test "a live switch and a write binding the outgoing domain both complete", %{first: first, second: second} do
    dynamic_with_live(first)

    other =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, other} =
          Registry.create_site(%{name: "Acme Other", key: "acme-race-other", languages: ["en"], default_language: "en"})

        other
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> delete_site(other) end) end)

    parent = self()

    binder =
      hold_hosts_lock(parent, fn ->
        case Registry.create_environment(other, %{name: "Other", key: "other", domain: "one.race.test"}, actor: :system) do
          {:error, changeset} -> Repo.rollback(changeset)
          {:ok, environment} -> environment
        end
      end)

    assert_receive :hosts_locked, 5_000
    switcher = set_live_task(second)

    wait_for_lock_waiter()
    send(binder.pid, :go)

    assert {:error, changeset} = Task.await(binder, 15_000)
    assert changeset.errors[:domain]
    assert {:ok, %Environment{live: true, domain: "one.race.test"}} = Task.await(switcher, 15_000)
  end

  # An environment committed after the switch locked the site's rows is not
  # locked by it: the switch leaves its row alone, as a hosts save on it holds
  # the row while it waits for the host lock the switch holds
  test "a live switch and a hosts save on an environment created after it began both complete", %{
    first: first,
    second: second
  } do
    site = dynamic_with_live(first)
    parent = self()

    holder = hold_hosts_lock(parent, fn -> :ok end)
    assert_receive :hosts_locked, 5_000

    switcher = set_live_task(second)
    wait_for_lock_waiter()

    # No hosts: its insert does not wait for the host lock
    third =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, third} = Registry.create_environment(site, %{name: "Three", key: "three"}, actor: :system)
        third
      end)

    saver =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            locked = Repo.one(from(e in Environment, where: e.id == ^third.id, lock: "FOR UPDATE"), prefix: "public")
            Registry.update_environment(locked, %{domain: "three.race.test"}, actor: :system)
          end)
        end)
      end)

    wait_for_lock_waiter(2)
    send(holder.pid, :go)

    assert {:ok, :ok} = Task.await(holder, 15_000)
    assert {:ok, %Environment{live: true, domain: "one.race.test"}} = Task.await(switcher, 15_000)
    assert {:ok, {:ok, %Environment{domain: "three.race.test"}}} = Task.await(saver, 15_000)
  end

  defp dynamic_with_live(%Environment{} = live) do
    put_test_env(:environment_schema_cloner, NoopSchemaCloner, global: true)

    Sandbox.unboxed_run(Repo, fn ->
      {:ok, site} = Registry.update_site(Registry.get_site(live.site_id), %{delivery_mode: :dynamic})
      Repo.update_all(from(e in Environment, where: e.id == ^live.id), [set: [live: true]], prefix: "public")
      site
    end)
  end

  # Holds the host lock the trigger takes until told to go on, then runs `fun`
  defp hold_hosts_lock(parent, fun) do
    on_own_connection(fn -> Repo.transaction(fn -> locked_hosts(parent, fun) end) end)
  end

  defp on_own_connection(fun), do: Task.async(fn -> Sandbox.unboxed_run(Repo, fun) end)

  defp locked_hosts(parent, fun) do
    Registry.lock_hosts()
    send(parent, :hosts_locked)

    receive do
      :go -> fun.()
    after
      10_000 -> raise "never told to go on"
    end
  end

  defp set_live_task(%Environment{id: id}) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn -> Brando.Environments.set_live(Registry.get_environment(id), creator: :system) end)
    end)
  end

  defp delete_site(%Site{id: id}) do
    Repo.delete_all(from(e in Environment, where: e.site_id == ^id), prefix: "public")
    Repo.delete_all(from(s in Site, where: s.id == ^id), prefix: "public")
  end

  defp wait_for_row_lock_waiter(attempts \\ 200)
  defp wait_for_row_lock_waiter(0), do: flunk("the live switch did not wait for the locked row")

  defp wait_for_row_lock_waiter(attempts) do
    waiting =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.one(
          from(l in "pg_locks",
            join: a in "pg_stat_activity",
            on: a.pid == l.pid,
            where:
              l.locktype in ["transactionid", "tuple"] and not l.granted and
                a.datname == fragment("current_database()"),
            select: count()
          )
        )
      end)

    if waiting > 0 do
      :ok
    else
      Process.sleep(10)
      wait_for_row_lock_waiter(attempts - 1)
    end
  end

  test "the same redirect host from two concurrent writes is bound once", %{first: first, second: second} do
    attrs = %{redirect_hosts: ["www.race.test"]}

    assert {:error, changeset} = race({first, attrs}, {second, attrs})
    assert changeset.errors[:redirect_hosts]

    Sandbox.unboxed_run(Repo, fn ->
      assert Registry.get_environment(first.id).redirect_hosts == ["www.race.test"]
      assert Registry.get_environment(second.id).redirect_hosts == []
    end)
  end

  test "a redirect host and the same host as a domain from two concurrent writes", %{first: first, second: second} do
    assert {:error, changeset} =
             race({first, %{redirect_hosts: ["shared.race.test"]}}, {second, %{domain: "shared.race.test"}})

    assert changeset.errors[:domain]

    Sandbox.unboxed_run(Repo, fn ->
      assert Registry.get_environment(second.id).domain == "two.race.test"
    end)
  end

  test "a domain and the same host as a redirect host from two concurrent writes", %{first: first, second: second} do
    assert {:error, changeset} =
             race({first, %{domain: "shared.race.test"}}, {second, %{redirect_hosts: ["shared.race.test"]}})

    assert changeset.errors[:redirect_hosts]
  end
end
