defmodule Brando.Content.DefinitionsReleaseStatusEnvironmentsTest do
  # The release status of a site with several environments: which
  # environments a change plans again, how often, and how the result reaches
  # the other nodes (`Brando.CacheSync`). One node in a test run: a result
  # "from another node" is a message that carries another node's origin.
  use Brando.ConnCase, async: false

  alias Brando.CacheSync
  alias Brando.Content.{Definitions, Module}
  alias Brando.Content.Definitions.{Release, ReleaseStatus}
  alias Brando.Environments
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @other_node "another-node"
  @production "tenant_acme_production"
  @staging "tenant_acme_staging"

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-release-environments-#{System.unique_integer([:positive])}")
    release = Path.join(root, "release")
    File.mkdir_p!(release)
    source = File.read!("test/fixtures/definitions/hero.exs.txt")
    File.write!(Path.join(release, "hero.exs"), source)

    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    # The server runs in its own process, which reads these too
    put_test_env(:tenancy_mode, :multi, global: true)
    put_test_env(:authorization_mode, :legacy, global: true)
    put_test_env(Definitions, release_path: release)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()
    ReleaseStatus.clear()

    on_exit(fn ->
      ReleaseStatus.clear()
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
      File.rm_rf(root)
    end)

    user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)

    {:ok, site} =
      Brando.Tenant.Setup.create_site(
        %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
        user,
        environments: [
          %{name: "Production", key: "production", live: true},
          %{name: "Staging", key: "staging", live: false}
        ],
        seed: false
      )

    # Production has the release's hero; staging has never had it
    Tenant.with_prefix(@production, fn -> {:ok, _} = Release.apply(:all, user: user.id) end)

    Phoenix.PubSub.subscribe(Brando.pubsub(), CacheSync.topic())

    %{user: user, site: site, release: release, source: source}
  end

  defp start_server!(opts \\ []) do
    pid = start_supervised!({ReleaseStatus, Keyword.merge([delay: 10, debounce: 50], opts)})
    Ecto.Adapters.SQL.Sandbox.allow(Brando.Repo.repo(), self(), pid)
    eventually(fn -> ReleaseStatus.summary(@production) && ReleaseStatus.summary(@staging) end)
    # The boot plans are this node's alone
    refute_planned()
    pid
  end

  defp save!(prefix, user, class) do
    Tenant.with_prefix(prefix, fn ->
      module = Brando.Repo.get_by!(Module, uid: "hero-test")
      {:ok, _} = Brando.Content.update_module(module.id, %{class: class}, user)
    end)
  end

  # Waits until the server has run what it holds
  defp settle(pid) do
    Process.sleep(150)
    :sys.get_state(pid)
  end

  # What this node planned for `prefix` and sent to the others
  defp planned(prefix) do
    origin = CacheSync.origin()

    receive do
      {:brando_cache_sync, ^origin, {ReleaseStatus, {:planned, ^prefix, value}}} ->
        value
    after
      2_000 -> flunk("#{prefix} was not planned")
    end
  end

  # Nothing this node planned was sent to the others
  defp refute_planned(prefix \\ :any) do
    origin = CacheSync.origin()

    receive do
      {:brando_cache_sync, ^origin, {ReleaseStatus, {:planned, planned, _}}} when prefix in [:any, planned] ->
        flunk("#{planned} was planned")
    after
      0 -> :ok
    end
  end

  defp eventually(fun, tries \\ 100) do
    if fun.() || tries == 0 do
      assert fun.()
    else
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  describe "a change" do
    test "plans only the environment it changed, and tells the other nodes", %{user: user} do
      pid = start_server!()
      assert %{pending: 0} = ReleaseStatus.summary(@production)
      assert %{pending: 1} = ReleaseStatus.summary(@staging)

      save!(@production, user, "admin-class")

      assert %{pending: 0, states: %{"hero-test" => :changed_in_admin}} = planned(@production)
      settle(pid)
      refute_planned(@staging)
      assert ReleaseStatus.state("hero-test", @production) == :changed_in_admin
    end

    test "a burst of saves plans once", %{user: user} do
      pid = start_server!()

      for n <- 1..5, do: save!(@production, user, "class-#{n}")

      assert %{states: %{"hero-test" => :changed_in_admin}} = planned(@production)
      settle(pid)
      refute_planned()
    end

    test "made before the boot plan is still sent once it is planned", %{user: user} do
      pid = start_supervised!({ReleaseStatus, delay: 100, debounce: 400})
      Ecto.Adapters.SQL.Sandbox.allow(Brando.Repo.repo(), self(), pid)

      # The boot plan sees the save first; the change's own check then finds
      # nothing new here, but the other nodes still need the result
      save!(@production, user, "before-boot")

      assert %{states: %{"hero-test" => :changed_in_admin}} = planned(@production)
    end

    test "saves in a transaction that rolls back plan nothing", %{user: user} do
      pid = start_server!()

      Brando.Repo.transaction(fn ->
        save!(@production, user, "rolled-back")
        Brando.Repo.rollback(:undo)
      end)

      settle(pid)
      refute_planned()
    end
  end

  describe "an environment replaced in bulk" do
    test "a copy plans the target again with the source's definitions", %{site: site} do
      start_server!()
      assert %{pending: 1} = ReleaseStatus.summary(@staging)

      [production, staging] = Enum.sort_by(Registry.list_environments(site), &(!&1.live))
      {:ok, _} = Environments.copy_environment(production, staging)

      assert %{pending: 0} = planned(@staging)
      assert %{pending: 0} = ReleaseStatus.summary(@staging)
    end

    test "a restored archive is planned as the environment it adds", %{site: site} do
      start_server!()

      # Staging, without the hero, is archived by the copy and restored
      [production, staging] = Enum.sort_by(Registry.list_environments(site), &(!&1.live))
      {:ok, _} = Environments.copy_environment(production, staging)
      assert %{pending: 0} = planned(@staging)

      {:ok, restored} = Environments.rollback(site)
      prefix = Tenant.prefix(site, restored)

      assert %{pending: 1, states: %{"hero-test" => :new}} = planned(prefix)
      assert %{pending: 1} = ReleaseStatus.summary(prefix)
    end

    test "a new environment is planned", %{site: site} do
      start_server!()

      {:ok, preview} = Environments.create_environment(site, %{name: "Preview", key: "preview", live: false})
      prefix = Tenant.prefix(site, preview)

      assert %{pending: 1} = planned(prefix)
      assert %{pending: 1} = ReleaseStatus.summary(prefix)
    end

    test "a ZIP import (an apply) plans the environment it imported into", %{user: user} do
      start_server!()

      Tenant.with_prefix(@staging, fn -> {:ok, _} = Release.apply(:all, user: user.id) end)

      assert %{pending: 0} = planned(@staging)
      assert %{pending: 0} = ReleaseStatus.summary(@staging)
    end
  end

  describe "another node's result" do
    test "is kept here, without planning", %{user: user} do
      pid = start_server!()
      %{release: release} = :ets.lookup_element(ReleaseStatus, @production, 2)

      remote = %{
        release: release,
        database: "elsewhere",
        taken_at: System.os_time(:microsecond),
        version: "9.9.9",
        pending: 3,
        states: %{"hero-test" => :changed_in_both},
        error: nil
      }

      send_remote({ReleaseStatus, {:planned, @production, remote}})

      assert %{pending: 3, version: "9.9.9"} = ReleaseStatus.summary(@production)
      assert ReleaseStatus.state("hero-test", @production) == :changed_in_both
      settle(pid)
      refute_planned()

      # One taken before this node's own plan is older: kept out
      save!(@production, user, "x")
      planned(@production)
      send_remote({ReleaseStatus, {:planned, @production, %{remote | taken_at: remote.taken_at - 1, pending: 7}}})
      refute match?(%{pending: 7}, ReleaseStatus.summary(@production))
    end

    test "for an environment this node hasn't planned is checked against its own release", c do
      pid = start_server!()
      File.write!(Path.join(c.release, "hero.exs"), String.replace(c.source, ~s(class "hero"), ~s(class "file")))
      # A new environment's first result
      :ets.delete(ReleaseStatus, @production)

      remote = %{
        release: "another-release",
        database: "elsewhere",
        taken_at: System.os_time(:microsecond),
        version: "0.0.1",
        pending: 9,
        states: %{},
        error: nil
      }

      send_remote({ReleaseStatus, {:planned, @production, remote}})

      eventually(fn -> ReleaseStatus.state("hero-test", @production) == :changed_in_release end)
      assert %{pending: 1} = ReleaseStatus.summary(@production)
      settle(pid)
      refute_planned()
    end

    test "for another release is planned again here, and not sent back", %{release: release} = c do
      pid = start_server!()
      File.write!(Path.join(release, "hero.exs"), String.replace(c.source, ~s(class "hero"), ~s(class "file")))

      remote = %{
        release: "another-release",
        database: "elsewhere",
        taken_at: System.os_time(:microsecond),
        version: "0.0.1",
        pending: 9,
        states: %{},
        error: nil
      }

      send_remote({ReleaseStatus, {:planned, @production, remote}})

      eventually(fn -> ReleaseStatus.state("hero-test", @production) == :changed_in_release end)
      assert %{pending: 1} = ReleaseStatus.summary(@production)
      settle(pid)
      refute_planned()
    end
  end

  defp send_remote(refresh) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), CacheSync.topic(), {:brando_cache_sync, @other_node, refresh})
    CacheSync.sync()
  end
end
