defmodule Brando.Content.LibraryOverrideRaceTest do
  # Two shared library actions on one site's customization at once, each on
  # its own connection (#3902): the sandbox shares one connection between
  # processes, so the site, its schema and the library module are committed
  # here, and removed after each test.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Brando.Test.Support
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Module
  alias Brando.Content.SharedLibrary
  alias Brando.Environments.Schema
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Users.User
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  @key "race3902"
  @prefix "tenant_race3902_production"

  setup do
    root = Path.join(System.tmp_dir!(), "brando-library-race-#{System.unique_integer([:positive])}")
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    put_test_env(:tenancy_mode, :multi, global: true)
    Tenant.put_prefix(nil)
    remove_site()

    {user, site, library} =
      unboxed(fn ->
        # Committed, so no avatar: deleting the user would leave its image row
        user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)

        {:ok, site} =
          Tenant.Setup.create_site(
            %{name: "Race", key: @key, languages: ["en"], default_language: "en", status: :active},
            user,
            seed: false,
            environments: [%{name: "Production", key: "production", live: true}]
          )

        {:ok, library} = SharedLibrary.create_shared(:module, module_attrs(), user)
        :ok = SharedLibrary.enable(site, :module, library.id)
        {user, site, library}
      end)

    on_exit(fn ->
      remove_site()
      unboxed(fn -> Repo.delete_all(from(m in Module, where: m.id == ^library.id), prefix: "public") end)
      unboxed(fn -> Repo.delete_all(from(u in User, where: u.id == ^user.id)) end)
      File.rm_rf(root)
    end)

    %{user: user, site: site, library: library}
  end

  # Accept deletes the customization and inserts its replacement: a Reset
  # waiting for the row then deletes the replacement
  test "a Reset that waited for an Accept discards the customization the Accept left", c do
    {:ok, _} = unboxed(fn -> SharedLibrary.customize(:module, c.library.id, c.site, @prefix, c.user) end)

    holder = hold(fn -> SharedLibrary.accept_update(:module, c.library.id, c.site, @prefix, c.user) end)
    reset = waiter(fn -> SharedLibrary.reset(:module, c.library.id, c.site, @prefix, c.user) end)
    send(holder.pid, :commit)
    assert {:ok, {:ok, _replacement}} = Task.await(holder, 10_000)

    assert :ok = Task.await(reset, 10_000)
    assert [] = overrides(c.library)
  end

  # Neither finds a row to lock: the second waits for the first to commit,
  # and finds its customization, rather than meet the index on the source
  test "a Customize beside another returns the customization the first made", c do
    holder = hold(fn -> SharedLibrary.customize(:module, c.library.id, c.site, @prefix, c.user) end)

    contender = waiter(fn -> SharedLibrary.customize(:module, c.library.id, c.site, @prefix, c.user) end)
    send(holder.pid, :commit)
    assert {:ok, {:ok, %{id: id}}} = Task.await(holder, 10_000)

    assert {:ok, %{id: ^id}} = Task.await(contender, 10_000)
    assert [%{id: ^id}] = overrides(c.library)
  end

  # Runs `fun` in a transaction that commits when told to
  defp hold(fun) do
    test = self()
    holder = Task.async(fn -> unboxed(fn -> hold_transaction(fun, test) end) end)
    assert_receive :holding, 10_000
    holder
  end

  defp hold_transaction(fun, test), do: Repo.transaction(fn -> run_and_hold(fun, test) end)

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
  # waits for the entry's advisory lock
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
    waiting? =
      unboxed(fn ->
        Repo.exists?(
          from(l in "pg_locks",
            where:
              l.pid == ^backend and l.locktype == "advisory" and not l.granted and
                l.database == fragment("(SELECT oid FROM pg_database WHERE datname = current_database())")
          )
        )
      end)

    unless waiting? do
      Process.sleep(10)
      wait_for_lock(backend, attempts - 1)
    end
  end

  defp overrides(library),
    do: unboxed(fn -> Repo.all(from(m in Module, where: m.source_module_id == ^library.id), prefix: @prefix) end)

  defp module_attrs do
    %{
      name: %{"en" => "Teaser"},
      namespace: %{"en" => "general"},
      help_text: %{"en" => "Help"},
      class: "teaser",
      code: "<p>library</p>"
    }
  end

  # The site's rows (the rest go with them) and schemas, as a killed run left them
  defp remove_site do
    unboxed(fn ->
      %{rows: schemas} =
        Repo.query!("SELECT nspname FROM pg_namespace WHERE starts_with(nspname, $1)", ["tenant_#{@key}_"])

      for [schema] <- schemas, do: Schema.drop(schema)
      Repo.delete_all(from(s in Site, where: s.key == @key), prefix: "public")
    end)

    Tenant.Cache.clear()
    SharedLibrary.Cache.clear()
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)
end
