defmodule Brando.Tenant.ServedHostsTest do
  # The node's one ServedHosts process, its global config and status, and the
  # tenant cache it reads: one test at a time
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog

  alias Brando.Environments
  alias Brando.ServedHostsTestResolver, as: DNS
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Tenant.ServedHosts

  @here "203.0.113.10"
  @here_v6 "2001:db8::10"
  @elsewhere "198.51.100.7"

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  defmodule SchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix), do: Brando.Environments.Schema.create(target_prefix)
  end

  defmodule StructureCloner do
    @behaviour Brando.Environments.StructureCloner

    @impl true
    def clone_structure(_source_prefix, _target_prefix), do: :ok
  end

  defmodule NotifyingResolver do
    @moduledoc false
    def lookup(host) do
      send(:persistent_term.get({__MODULE__, :pid}), {:looked_up, host})
      Brando.ServedHostsTestResolver.lookup(host)
    end
  end

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    file = Path.join(tmp_dir, "served_hosts")
    put_test_env(ServedHosts, file: file, addresses: [@here, @here_v6])
    Cache.clear()

    on_exit(fn ->
      DNS.reset()
      Cache.clear()
    end)

    {:ok, site} = create_site("acme")
    # Waits for the check the site's creation asked for, so it cannot land mid-test
    ServedHosts.check()
    %{path: file, site: site}
  end

  defp create_site(key) do
    Registry.create_site(%{
      name: String.capitalize(key),
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    })
  end

  defp bind(site, key, domain, live \\ false) do
    {:ok, environment} =
      Registry.create_environment(site, %{name: key, key: key, live: live, domain: domain}, actor: :system)

    # The check the write asked for, done before the test changes DNS
    ServedHosts.check()
    environment
  end

  # A domain stored before `Environment` checked it, which no changeset sees again
  defp bind_raw(site, key, domain) do
    environment = bind(site, key, nil)
    set_domain(environment, domain)
    Cache.warm()
    ServedHosts.check()
    environment
  end

  defp set_domain(environment, domain) do
    Brando.Repo.update_all(
      from(e in Brando.Environments.Environment, where: e.id == ^environment.id),
      [set: [domain: domain]],
      prefix: "public"
    )
  end

  # As the supervisor restarts it; returns once `init/1` and its continue ran
  defp restart do
    :ok = Supervisor.terminate_child(Brando.Supervisor, ServedHosts)
    {:ok, _pid} = Supervisor.restart_child(Brando.Supervisor, ServedHosts)
    :sys.get_state(ServedHosts)
  end

  defp lines(file), do: file |> File.read!() |> String.split("\n", trim: true)

  describe "admission" do
    test "a host pointing here is admitted, the others wait", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here, @here_v6])
      DNS.answer("away.acme.test", [@elsewhere])
      DNS.answer("split.acme.test", [@here, @elsewhere])
      bind(site, "production", "www.acme.test", true)
      bind(site, "away", "away.acme.test")
      bind(site, "split", "split.acme.test")
      bind(site, "missing", "missing.acme.test")

      status = ServedHosts.check()

      assert File.read!(file) == "www.acme.test\n"

      assert status.hosts == %{
               "www.acme.test" => :served,
               "away.acme.test" => {:waiting, [@elsewhere]},
               "split.acme.test" => {:waiting, [@elsewhere, @here]},
               "missing.acme.test" => :unresolved
             }

      assert status.addresses == [@here, @here_v6]
      assert status.error == nil
    end

    test "addresses are sorted and unique, so records answered in turn change nothing", %{site: site} do
      put_test_env(ServedHosts, file: ServedHosts.status().file, addresses: [@here_v6, @here, @here])
      DNS.answer("away.acme.test", [@here, @elsewhere])
      bind(site, "away", "away.acme.test")

      assert %{addresses: [@here, @here_v6], hosts: %{"away.acme.test" => {:waiting, [@elsewhere, @here]}}} =
               ServedHosts.check()

      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())
      DNS.answer("away.acme.test", [@elsewhere, @here, @elsewhere])
      ServedHosts.check()

      refute_received {:served_hosts, _status}
    end

    test "an admitted host stays when its lookup later fails or points elsewhere", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      ServedHosts.check()
      assert lines(file) == ["www.acme.test"]

      DNS.answer("www.acme.test", [@elsewhere])
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.check()

      DNS.answer("www.acme.test", {:error, :timeout})
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.check()
      assert lines(file) == ["www.acme.test"]
    end

    test "a host is admitted when its DNS arrives", %{path: file, site: site} do
      bind(site, "production", "www.acme.test", true)
      assert %{hosts: %{"www.acme.test" => :unresolved}} = ServedHosts.check()
      assert File.read!(file) == ""

      DNS.answer("www.acme.test", [@here])
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.check()
      assert lines(file) == ["www.acme.test"]
    end

    test "admit: :always admits every bound host without a lookup", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, admit: :always)
      bind(site, "production", "www.acme.test", true)
      bind(site, "away", "away.acme.test")

      assert %{hosts: %{"www.acme.test" => :served, "away.acme.test" => :served}} = ServedHosts.check()
      assert lines(file) == ["away.acme.test", "www.acme.test"]
    end

    test "explicit addresses decide, not the endpoint's", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@elsewhere])
      DNS.answer("localhost", [@here])
      DNS.answer("www.acme.test", [@here])
      DNS.answer("away.acme.test", [@elsewhere])
      bind(site, "production", "www.acme.test", true)
      bind(site, "away", "away.acme.test")

      assert %{addresses: [@elsewhere]} = ServedHosts.check()
      assert lines(file) == ["away.acme.test"]
    end

    test "without addresses, this server's are what the endpoint's host resolves to", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file)
      DNS.answer("localhost", [@here])
      bind(site, "production", "www.acme.test", true)
      DNS.answer("www.acme.test", [@here])

      assert %{addresses: [@here]} = ServedHosts.check()
      assert lines(file) == ["www.acme.test"]
    end
  end

  describe "the set" do
    test "unbinding, deleting the environment and deleting the site each remove a host", %{path: file, site: site} do
      {:ok, beta} = create_site("beta")

      for host <- ~w(www.acme.test spring.acme.test old.acme.test www.beta.test),
          do: DNS.answer(host, [@here])

      production = bind(site, "production", "www.acme.test", true)
      spring = bind(site, "spring", "spring.acme.test")
      old = bind(site, "old", "old.acme.test")
      bind(beta, "production", "www.beta.test", true)

      ServedHosts.check()
      assert lines(file) == ~w(old.acme.test spring.acme.test www.acme.test www.beta.test)

      {:ok, _} = Registry.update_environment(spring, %{domain: nil}, actor: :system)
      ServedHosts.check()
      assert lines(file) == ~w(old.acme.test www.acme.test www.beta.test)

      {:ok, _} = Registry.delete_environment(old)
      ServedHosts.check()
      assert lines(file) == ~w(www.acme.test www.beta.test)

      {:ok, _} = Registry.delete_site(beta)
      %{hosts: hosts} = ServedHosts.check()
      assert lines(file) == ~w(www.acme.test)
      assert Map.keys(hosts) == ["www.acme.test"]

      assert production
    end

    test "a suspended or archived site keeps its host", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      ServedHosts.check()

      {:ok, site} = Registry.update_site(Registry.get_site(site.id), %{status: :suspended})
      ServedHosts.check()
      assert lines(file) == ["www.acme.test"]

      {:ok, _site} = Registry.update_site(site, %{status: :archived})
      ServedHosts.check()
      assert lines(file) == ["www.acme.test"]
    end

    test "set_live on a dynamic site moves its host between environments and leaves the file alone",
         %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      DNS.answer("next.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      staging = bind(site, "staging", "next.acme.test")
      ServedHosts.check()
      before = File.stat!(file, time: :posix)
      DNS.answer("www.acme.test", [@elsewhere])
      DNS.answer("next.acme.test", [@elsewhere])

      assert {:ok, %{live: true, domain: "www.acme.test"}} = Environments.set_live(staging)

      ServedHosts.check()
      assert lines(file) == ["next.acme.test", "www.acme.test"]
      assert File.stat!(file, time: :posix).inode == before.inode
    end

    test "a stored value that is no valid host name is never written, even with admit: :always",
         %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, admit: :always)
      bind(site, "production", "www.acme.test", true)

      invalid = [
        "example.com:4000",
        "under_score.acme.test",
        "back`tick.acme.test",
        "www.acme.test\nunbound.example.com",
        "intranet",
        "203.0.113.10"
      ]

      for {raw, index} <- Enum.with_index(invalid), do: bind_raw(site, "legacy-#{index}", raw)

      assert %{hosts: hosts} = ServedHosts.check()
      assert File.read!(file) == "www.acme.test\n"
      assert hosts["www.acme.test"] == :served
      for raw <- invalid, do: assert(hosts[raw] == :invalid, "#{inspect(raw)} is #{inspect(hosts[raw])}")
    end

    test "an IP address is not admitted by the DNS check", %{path: file, site: site} do
      DNS.answer(@here, [@here])
      bind_raw(site, "production", @here)

      assert %{hosts: %{@here => :invalid}} = ServedHosts.check()
      assert File.read!(file) == ""
    end

    test "the installation's own hosts are never in the file", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, admit: :always)
      environment = bind(site, "production", nil, true)

      # Stored before the changeset refused it
      Brando.Repo.update_all(
        from(e in Brando.Environments.Environment, where: e.id == ^environment.id),
        [set: [domain: "localhost"]],
        prefix: "public"
      )

      Cache.warm()
      assert %{hosts: hosts} = ServedHosts.check()
      assert hosts == %{}
      assert File.read!(file) == ""
    end
  end

  describe "the file" do
    test "is not rewritten when nothing changed", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      ServedHosts.check()
      %{inode: inode} = File.stat!(file)

      ServedHosts.check()
      Cache.warm()
      ServedHosts.check()

      assert %{inode: ^inode} = File.stat!(file)
    end

    test "drops junk and hosts no environment binds", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      File.write!(file, "not a host!\nwww.acme.test\nunbound.example.com\n\n")

      ServedHosts.check()

      assert File.read!(file) == "www.acme.test\n"
    end

    test "a write removes temporary files an earlier write left behind, and none of its own",
         %{path: file, tmp_dir: tmp_dir, site: site} do
      leftovers = [".served_hosts.12.tmp", ".served_hosts.Zm9vYmFy.tmp"]
      # Another node sharing the path may be between its write and its rename
      fresh = ".served_hosts.bm93.tmp"
      others = [".other_hosts.12.tmp", "served_hosts.bak", fresh]
      for name <- leftovers ++ others, do: File.write!(Path.join(tmp_dir, name), "stale\n")
      two_minutes_ago = System.os_time(:second) - 120
      for name <- leftovers, do: File.touch!(Path.join(tmp_dir, name), two_minutes_ago)

      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)

      assert File.read!(file) == "www.acme.test\n"
      assert tmp_dir |> File.ls!() |> Enum.sort() == Enum.sort(["served_hosts" | others])
    end

    test "a host already in the file is kept without a lookup", %{path: file, site: site} do
      bind(site, "production", "www.acme.test", true)
      File.write!(file, "www.acme.test\n")

      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.check()
      assert File.read!(file) == "www.acme.test\n"
    end

    test "an unwritable path is reported, logged once and retried", %{tmp_dir: tmp_dir, site: site} do
      file = Path.join([tmp_dir, "missing", "served_hosts"])
      put_test_env(ServedHosts, file: file, admit: :always)

      log =
        capture_log(fn ->
          bind(site, "production", "www.acme.test", true)
          assert %{error: error, hosts: %{"www.acme.test" => :not_written}} = ServedHosts.check()
          assert error =~ file
          assert %{error: ^error} = ServedHosts.check()
        end)

      assert [_once] = Regex.scan(~r/Could not update the served hosts file/, log)
      assert Process.alive?(Process.whereis(ServedHosts))

      File.mkdir_p!(Path.dirname(file))

      capture_log(fn ->
        assert %{error: nil, hosts: %{"www.acme.test" => :served}} = ServedHosts.check()
      end)

      assert File.read!(file) == "www.acme.test\n"
    end
  end

  describe "a broken setup" do
    defmodule RaisingResolver do
      def lookup(_host), do: raise("resolver broke")
    end

    test "a resolver that raises leaves the host waiting", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: RaisingResolver)
      bind(site, "production", "www.acme.test", true)

      assert %{hosts: %{"www.acme.test" => :unresolved}, error: nil} = ServedHosts.check()
      assert File.read!(file) == ""
    end

    defmodule ExitingResolver do
      def lookup(_host), do: exit(:resolver_exited)
    end

    defmodule ThrowingResolver do
      def lookup(_host), do: throw(:resolver_threw)
    end

    defmodule CrashingResolver do
      # The lookup task dies of a link, which no catch inside it sees
      def lookup(_host) do
        spawn_link(fn -> exit(:linked_crash) end)
        Process.sleep(:infinity)
      end
    end

    defmodule HangingResolver do
      def lookup(_host), do: Process.sleep(:infinity)
    end

    for resolver <- [ExitingResolver, ThrowingResolver, CrashingResolver, HangingResolver] do
      @resolver resolver
      test "a lookup that fails with #{inspect(resolver)} leaves the host unresolved", %{path: file, site: site} do
        pid = Process.whereis(ServedHosts)
        bind(site, "production", "www.acme.test", true)
        # No addresses: the endpoint's host goes through the same resolver
        put_test_env(ServedHosts, file: file, resolver: @resolver, lookup_timeout: 50)

        assert %{hosts: %{"www.acme.test" => :unresolved}, addresses: [], error: nil} = ServedHosts.check()
        assert Process.whereis(ServedHosts) == pid
        assert File.read!(file) == ""
      end
    end

    test "a check that raises is reported and does not restart the process", %{path: file, site: site} do
      pid = Process.whereis(ServedHosts)
      bind(site, "production", "www.acme.test", true)
      put_test_env(ServedHosts, file: file, addresses: :not_a_list)

      log = capture_log(fn -> assert %{error: "" <> _} = ServedHosts.check() end)

      assert log =~ "Could not update the served hosts file"
      assert Process.whereis(ServedHosts) == pid

      put_test_env(ServedHosts, file: file, admit: :always)
      capture_log(fn -> assert %{error: nil, hosts: %{"www.acme.test" => :served}} = ServedHosts.check() end)
    end
  end

  describe "when it runs" do
    test "a warm of the tenant cache checks again, and the status is broadcast", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      environment = bind(site, "production", nil, true)
      # Stored without a registry write, so only the warm below can make a check
      set_domain(environment, "www.acme.test")
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())

      Cache.warm()

      assert_receive {:served_hosts, %{hosts: %{"www.acme.test" => :served}}}
      assert File.read!(file) == "www.acme.test\n"
    end

    test "a restarted process checks when the cache is warm", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      File.write!(file, "")

      restart()

      assert File.read!(file) == "www.acme.test\n"
    end

    test "a restarted process with a cold cache leaves the file alone", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      Cache.clear()

      restart()

      assert File.read!(file) == "www.acme.test\n"
    end

    test "a waiting host is checked again on the retry timer", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], retry_interval: 20)
      bind(site, "production", "www.acme.test", true)
      assert %{hosts: %{"www.acme.test" => :unresolved}} = ServedHosts.status()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())

      DNS.answer("www.acme.test", [@here])

      assert_receive {:served_hosts, %{hosts: %{"www.acme.test" => :served}}}
      assert File.read!(file) == "www.acme.test\n"
    end

    test "with nothing waiting, a slow check reads the file again and readmits a host it lost",
         %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], recheck_interval: 20)
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.status()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())

      # Another node sharing the path wrote its stale list
      DNS.answer("www.acme.test", [@elsewhere])
      File.write!(file, "")

      assert_receive {:served_hosts, %{hosts: %{"www.acme.test" => {:waiting, [@elsewhere]}}}}
    end

    test "the slow check looks nothing up while the file holds every bound host", %{path: file, site: site} do
      :persistent_term.put({NotifyingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({NotifyingResolver, :pid}) end)
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: NotifyingResolver, recheck_interval: 20)
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      assert_received {:looked_up, "www.acme.test"}

      pid = Process.whereis(ServedHosts)
      :erlang.trace(pid, true, [:receive])
      on_exit(fn -> :erlang.trace(pid, false, [:receive]) end)

      assert_receive {:trace, ^pid, :receive, :tick}
      assert_receive {:trace, ^pid, :receive, :tick}
      :sys.get_state(pid)

      refute_received {:looked_up, _host}
      assert File.read!(file) == "www.acme.test\n"
    end

    test "the status is broadcast on this node only: each node has its own file", %{site: site} do
      # Calls the process makes into Phoenix.PubSub; a cluster cannot be started here
      pid = Process.whereis(ServedHosts)
      :erlang.trace_pattern({Phoenix.PubSub, :_, :_}, true, [:global])
      :erlang.trace(pid, true, [:call])

      on_exit(fn ->
        :erlang.trace(pid, false, [:call])
        :erlang.trace_pattern({Phoenix.PubSub, :_, :_}, false, [:global])
      end)

      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)

      assert_receive {:trace, ^pid, :call, {Phoenix.PubSub, :local_broadcast, [_, _, {:served_hosts, _}]}}
      refute_received {:trace, ^pid, :call, {Phoenix.PubSub, :broadcast, _}}
    end

    test "with no file configured, nothing is written or broadcast", %{tmp_dir: tmp_dir, site: site} do
      put_test_env(ServedHosts, [])
      File.rm_rf!(Path.join(tmp_dir, "served_hosts"))
      refute ServedHosts.enabled?()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())
      DNS.answer("www.acme.test", [@here])

      bind(site, "production", "www.acme.test", true)
      ServedHosts.check()

      refute_received {:served_hosts, _status}
      assert File.ls!(tmp_dir) == []
    end
  end
end
