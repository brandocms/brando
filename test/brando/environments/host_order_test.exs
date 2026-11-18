defmodule Brando.Environments.HostOrderTest.PageController do
  use Phoenix.Controller, formats: [:html]

  # Reads a table of the environment the host resolved to, as a page does
  def index(conn, _params) do
    Brando.Repo.repo().query!(~s|SELECT count(*) FROM "#{conn.assigns.tenant_prefix}".pages|)
    send_resp(conn, 200, "ok")
  end
end

defmodule Brando.Environments.HostOrderTest.Router do
  use Phoenix.Router

  pipeline :browser do
    plug Brando.Plug.Tenant
  end

  scope "/" do
    pipe_through :browser
    get "/", Brando.Environments.HostOrderTest.PageController, :index
  end
end

defmodule Brando.Environments.HostOrderTest do
  # Requests on an environment's hosts while it is created and deleted, on
  # their own connections: until the create is done, and from the moment the
  # delete starts, the hosts are unknown (404), never a half-made or dropped
  # schema (5xx).
  use ExUnit.Case, async: false

  import Brando.Test.Support
  import Ecto.Query, only: [from: 2]

  alias Brando.Environments
  alias Brando.Environments.Environment
  alias Brando.Environments.HostOrderTest.Router
  alias Brando.Environments.Schema
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Users.User
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @domain "preview.hold.test"
  @redirect "www.preview.hold.test"

  defmodule StructureCloner do
    @behaviour Brando.Environments.StructureCloner

    @impl true
    def clone_structure(_source_prefix, target_prefix) do
      Brando.Repo.repo().query!(~s|CREATE TABLE "#{target_prefix}".pages (id integer)|)
      :ok
    end
  end

  # Holds the migrations until the test sends `:migrate`
  defmodule HoldingMigrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment) do
      send(Application.fetch_env!(:brando, __MODULE__), {:migrating, self()})

      receive do
        :migrate -> {:ok, []}
      after
        10_000 -> {:error, :never_released}
      end
    end
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:tenant_migrator, HoldingMigrator)
    put_test_env(HoldingMigrator, self())

    # Committed: what a killed run left goes first, and on exit whatever this
    # run leaves
    remove_site("acme-hold")
    on_exit(fn -> remove_site("acme-hold") end)

    site =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, site} =
          Registry.create_site(%{
            name: "Acme",
            key: "acme-hold",
            languages: ["en"],
            default_language: "en",
            status: :active,
            delivery_mode: :dynamic
          })

        site
      end)

    %{site: site}
  end

  test "a create's hosts answer only once its schema is migrated", %{site: site} do
    creator = create_task(site)

    assert_receive {:migrating, migrator}, 5_000
    assert schema_exists?(Tenant.prefix(site.key, "preview"))
    assert request(@domain).status == 404
    assert request(@redirect).status == 404

    send(migrator, :migrate)
    assert {:ok, %Environment{domain: @domain, redirect_hosts: [@redirect]}} = Task.await(creator, 10_000)

    assert request(@domain).status == 200
    assert request(@redirect).status == 301
  end

  test "a delete's hosts stop answering before its schema is dropped", %{site: site} do
    creator = create_task(site)
    assert_receive {:migrating, migrator}, 5_000
    send(migrator, :migrate)
    assert {:ok, environment} = Task.await(creator, 10_000)
    assert request(@domain).status == 200

    # Reading the table holds the drop at its lock until the reader commits
    prefix = Tenant.prefix(site, environment)
    reader = hold_table(prefix)
    deleter = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> Environments.delete_environment(environment) end) end)
    wait_for_drop(prefix)

    assert request(@domain).status == 404
    assert request(@redirect).status == 404

    send(reader.pid, :commit)
    Task.await(reader, 10_000)
    assert {:ok, %Environment{}} = Task.await(deleter, 10_000)

    refute schema_exists?(prefix)
    assert request(@domain).status == 404
  end

  test "a delete of an environment whose hosts a cache still holds refreshes it before the drop", %{site: site} do
    creator = create_task(site)
    assert_receive {:migrating, migrator}, 5_000
    send(migrator, :migrate)
    assert {:ok, environment} = Task.await(creator, 10_000)

    # Released by a write whose cache refresh failed
    Sandbox.unboxed_run(Repo, fn ->
      Repo.update_all(from(e in Environment, where: e.id == ^environment.id), [set: [domain: nil, redirect_hosts: []]],
        prefix: "public"
      )
    end)

    assert {_site, %Environment{}} = Cache.get_env_by_domain(@domain)

    prefix = Tenant.prefix(site, environment)
    reader = hold_table(prefix)
    deleter = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> Environments.delete_environment(environment) end) end)
    wait_for_drop(prefix)

    refute Cache.get_env_by_domain(@domain)
    refute Cache.get_redirect(@redirect)

    send(reader.pid, :commit)
    Task.await(reader, 10_000)
    assert {:ok, %Environment{}} = Task.await(deleter, 10_000)
  end

  describe "a delete whose drop fails" do
    setup %{site: site} do
      creator = create_task(site)
      assert_receive {:migrating, migrator}, 5_000
      send(migrator, :migrate)
      assert {:ok, environment} = Task.await(creator, 10_000)

      prefix = Tenant.prefix(site, environment)
      reader = hold_table(prefix)
      deleter = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> Environments.delete_environment(environment) end) end)

      %{environment: environment, prefix: prefix, reader: reader, deleter: deleter, drop: wait_for_drop(prefix)}
    end

    test "binds the hosts again", context do
      cancel(context.drop)
      assert {:error, %Postgrex.Error{postgres: %{code: :query_canceled}}} = Task.await(context.deleter, 10_000)
      send(context.reader.pid, :commit)
      Task.await(context.reader, 10_000)

      assert %Environment{domain: @domain, redirect_hosts: [@redirect]} =
               Sandbox.unboxed_run(Repo, fn -> Registry.get_environment(context.environment.id) end)

      assert schema_exists?(context.prefix)
      assert request(@domain).status == 200
      assert request(@redirect).status == 301
    end

    test "says which hosts it could not bind again", %{site: site} = context do
      # Another environment takes the domain while the drop waits
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, _rival} =
          Registry.create_environment(site, %{name: "Rival", key: "rival", domain: @domain}, actor: :system)
      end)

      cancel(context.drop)

      assert {:error, {:schema_not_dropped, %Postgrex.Error{}, {:hosts_released, @domain, [@redirect]}}} =
               Task.await(context.deleter, 10_000)

      send(context.reader.pid, :commit)
      Task.await(context.reader, 10_000)

      assert %Environment{domain: nil, redirect_hosts: []} =
               Sandbox.unboxed_run(Repo, fn -> Registry.get_environment(context.environment.id) end)

      assert schema_exists?(context.prefix)
    end
  end

  describe "a new site's hosts" do
    setup do
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:cache_sync_settle_ms, 0)

      root = Path.join(System.tmp_dir!(), "brando-host-order-#{System.unique_integer([:positive])}")
      put_test_env(:media_path, Path.join(root, "media"))
      put_test_env(:sites_path, Path.join(root, "sites"))

      remove_site("acme-bind")

      on_exit(fn ->
        remove_site("acme-bind")
        File.rm_rf(root)
      end)

      # Committed, so no avatar: deleting the user would leave its image row
      # behind for every later test in this database
      creator = Sandbox.unboxed_run(Repo, fn -> Brando.Factory.insert(:random_user, role: :superuser, avatar: nil) end)
      on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(from(u in User, where: u.id == ^creator.id)) end) end)

      %{creator: creator}
    end

    # A hosts save holds its row, then the host lock: the bind takes them in
    # the same order, so it never holds the host lock while it waits for a row
    test "are bound with every row locked before the host lock", %{creator: creator} do
      provisioner = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> provision_bind_site(creator) end) end)

      assert_receive {:migrating, migrator}, 5_000
      send(migrator, :migrate)

      # Staging's row is written: a save holds it until the bind waits
      assert_receive {:migrating, migrator}, 5_000

      staging =
        Sandbox.unboxed_run(Repo, fn ->
          Registry.get_environment_by_key(Registry.get_site_by_key("acme-bind"), "staging")
        end)

      holder = hold_row(staging)
      send(migrator, :migrate)

      wait_for_row_waiter()
      assert host_lock_free?()

      send(holder.pid, :commit)
      Task.await(holder, 10_000)
      assert {:ok, site} = Task.await(provisioner, 10_000)
      assert Enum.find(site.environments, &(&1.key == "staging")).domain == "staging.bind.hold.test"
    end
  end

  defp provision_bind_site(creator) do
    Brando.Tenant.Setup.create_site(
      %{
        name: "Acme",
        key: "acme-bind",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      },
      creator,
      seed: false,
      environments: [
        %{name: "Production", key: "production", live: true, domain: "bind.hold.test"},
        %{name: "Staging", key: "staging", live: false, domain: "staging.bind.hold.test"}
      ]
    )
  end

  defp hold_row(environment) do
    test = self()

    holder =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn -> hold_row_until_commit(environment, test) end)
      end)

    assert_receive :holding, 5_000
    holder
  end

  defp hold_row_until_commit(environment, test) do
    Repo.transaction(fn ->
      Repo.query!("SELECT id FROM public.environments WHERE id = $1 FOR NO KEY UPDATE", [environment.id])
      send(test, :holding)

      receive do
        :commit -> :ok
      after
        10_000 -> raise "never told to commit"
      end
    end)
  end

  # Until a connection waits for a row another holds
  defp wait_for_row_waiter(attempts \\ 500)
  defp wait_for_row_waiter(0), do: flunk("nothing waited for the row")

  defp wait_for_row_waiter(attempts) do
    waiting =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.one(
          from(l in "pg_locks", where: l.locktype in ["transactionid", "tuple"] and not l.granted, select: count())
        )
      end)

    if waiting > 0 do
      :ok
    else
      Process.sleep(10)
      wait_for_row_waiter(attempts - 1)
    end
  end

  defp host_lock_free? do
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, free?} =
        Repo.transaction(fn ->
          %{rows: [[free?]]} =
            Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended('brando.environments.hosts', 0))")

          free?
        end)

      free?
    end)
  end

  # A site's rows (the rest go with them) and schemas, by key, as a killed
  # run left them
  defp remove_site(key) do
    Sandbox.unboxed_run(Repo, fn ->
      %{rows: schemas} =
        Repo.query!("SELECT nspname FROM pg_namespace WHERE starts_with(nspname, $1)", ["tenant_#{key}_"])

      for [schema] <- schemas, do: Schema.drop(schema)
      Repo.delete_all(from(s in Site, where: s.key == ^key), prefix: "public")
    end)

    Cache.clear()
  end

  defp create_task(site) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Environments.create_environment(
          site,
          %{name: "Preview", key: "preview", domain: @domain, redirect_hosts: [@redirect]},
          actor: :system
        )
      end)
    end)
  end

  defp schema_exists?(prefix), do: Sandbox.unboxed_run(Repo, fn -> Schema.exists?(prefix) end)

  defp request(host) do
    Sandbox.unboxed_run(Repo, fn ->
      :get
      |> Plug.Test.conn("https://#{host}/")
      |> Router.call(Router.init([]))
    end)
  end

  defp hold_table(prefix) do
    test = self()

    reader = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> read_and_hold(test, prefix) end) end)

    assert_receive :reading, 5_000
    reader
  end

  defp read_and_hold(test, prefix), do: Repo.transaction(fn -> hold_read(test, prefix) end)

  defp hold_read(test, prefix) do
    Repo.query!(~s|SELECT count(*) FROM "#{prefix}".pages|)
    send(test, :reading)

    receive do
      :commit -> :ok
    after
      10_000 -> raise "never told to commit"
    end
  end

  # Until the drop waits for the reader's lock on the table
  defp wait_for_drop(prefix, attempts \\ 500)
  defp wait_for_drop(_prefix, 0), do: flunk("the drop never waited for the table")

  defp wait_for_drop(prefix, attempts) do
    waiting =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.all(
          from(l in "pg_locks",
            where:
              l.locktype == "relation" and not l.granted and
                l.relation == fragment("to_regclass(?)::oid", ^~s|"#{prefix}".pages|),
            select: l.pid
          )
        )
      end)

    case waiting do
      [pid | _] ->
        pid

      [] ->
        Process.sleep(10)
        wait_for_drop(prefix, attempts - 1)
    end
  end

  # Fails the drop waiting at `pid`
  defp cancel(pid), do: Sandbox.unboxed_run(Repo, fn -> Repo.query!("SELECT pg_cancel_backend($1)", [pid]) end)
end
