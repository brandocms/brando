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

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Schema.drop(Tenant.prefix(site.key, "preview"))
        Repo.delete_all(from(l in "environment_operation_logs", where: l.site_id == ^site.id), prefix: "public")
        Repo.delete_all(from(e in Environment, where: e.site_id == ^site.id), prefix: "public")
        Repo.delete_all(from(s in Site, where: s.id == ^site.id), prefix: "public")
      end)

      Cache.clear()
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
        Repo.one(
          from(l in "pg_locks",
            where:
              l.locktype == "relation" and not l.granted and
                l.relation == fragment("to_regclass(?)::oid", ^~s|"#{prefix}".pages|),
            select: count()
          )
        )
      end)

    if waiting > 0 do
      :ok
    else
      Process.sleep(10)
      wait_for_drop(prefix, attempts - 1)
    end
  end
end
