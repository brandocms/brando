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
