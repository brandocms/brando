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
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from(e in Environment, where: e.site_id == ^site.id), prefix: "public")
        Repo.delete_all(from(s in Site, where: s.id == ^site.id), prefix: "public")
      end)

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

  defp wait_for_lock_waiter(attempts \\ 200)
  defp wait_for_lock_waiter(0), do: flunk("the second write did not wait for the lock")

  defp wait_for_lock_waiter(attempts) do
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

    if waiting > 0 do
      :ok
    else
      Process.sleep(10)
      wait_for_lock_waiter(attempts - 1)
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
    put_test_env(:environment_schema_cloner, NoopSchemaCloner, global: true)

    third =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, site} = Registry.update_site(Registry.get_site(first.site_id), %{delivery_mode: :dynamic})

        Repo.update_all(from(e in Environment, where: e.id == ^first.id), [set: [live: true]], prefix: "public")

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

    switcher =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Brando.Environments.set_live(Registry.get_environment(second.id), creator: :system)
        end)
      end)

    wait_for_row_lock_waiter()
    send(saver.pid, :save)

    assert {:ok, {:ok, %Environment{redirect_hosts: ["www.three.race.test"]}}} = Task.await(saver, 15_000)
    assert {:ok, %Environment{live: true, domain: "one.race.test"}} = Task.await(switcher, 15_000)

    Sandbox.unboxed_run(Repo, fn ->
      assert Registry.get_environment(first.id).domain == "two.race.test"
      assert Registry.get_environment(third.id).redirect_hosts == ["www.three.race.test"]
    end)
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
