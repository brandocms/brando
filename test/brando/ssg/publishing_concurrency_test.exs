defmodule Brando.SSG.PublishingConcurrencyTest do
  # Two people pressing Publish at once start one build: the state is read
  # and the build queued under the site's build lock. Two connections at
  # once, so outside the sandbox, on committed rows (`Brando.Test.Committed`).
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.SSG.Builds
  alias Brando.SSG.Publishing
  alias Brando.Test.Support
  alias Brando.Tenant.Registry

  setup_all do
    Brando.Test.Committed.template()
  end

  setup tags do
    :ok = Brando.Test.Committed.start(tags.template)
    root = Path.join(System.tmp_dir!(), "brando-publishing-concurrency-#{System.unique_integer([:positive])}")
    Support.put_test_env(:tenancy_mode, :multi)
    Support.put_test_env(:authorization_mode, :legacy)
    Support.put_test_env(:sites_path, Path.join(root, "sites"))
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Brando.Tenant.Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Concurrent Acme",
        key: "concurrent-acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :local}
      })

    {:ok, production} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    user = Brando.Factory.insert(:random_user, role: :superuser)
    %{site: Registry.get_site(site.id), production: production, user: user}
  end

  test "two Publish calls at once start one build", c do
    test = self()
    lock = "ssg-build:#{c.site.id}"

    # The builds are queued, not run: Oban runs a job at once when the
    # process or any of its callers is in the inline mode
    results =
      Oban.Testing.with_testing_mode(:manual, fn ->
        publish = fn ->
          Task.async(fn ->
            Oban.Testing.with_testing_mode(:manual, fn -> Publishing.publish(c.site, c.production, c.user) end)
          end)
        end

        # Held here until both wait for it: without the lock, both would
        # read the state before either queued its build
        tasks =
          Brando.Tenant.Lock.with(lock, fn ->
            tasks = [publish.(), publish.()]
            await_waiters(2)
            send(test, :released)
            tasks
          end)

        Task.await_many(tasks, 10_000)
      end)

    assert_received :released

    assert Enum.count(results, &match?({:ok, _build}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :publishing})) == 1
    assert [_one] = Builds.list_builds(c.site)
  end

  defp await_waiters(count, attempts \\ 200) do
    waiting =
      from(lock in "pg_locks", where: lock.locktype == "advisory" and not lock.granted, select: count())
      |> Brando.Repo.repo().one(prefix: "pg_catalog")

    cond do
      waiting >= count -> :ok
      attempts == 0 -> flunk("the Publish calls did not wait for the build lock")
      true ->
        Process.sleep(10)
        await_waiters(count, attempts - 1)
    end
  end
end
