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

  defmodule BlockingResolver do
    @moduledoc false
    # Answers once the test says so
    def lookup(host) do
      send(:persistent_term.get({__MODULE__, :pid}), {:looking_up, host, self()})

      receive do
        :answer -> Brando.ServedHostsTestResolver.lookup(host)
      end
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
    # Nothing of one test's process or status is seen in the next: a cold
    # cache, so the new process checks nothing until the site below
    restart()
    :persistent_term.erase({ServedHosts, :status})

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

  # As the supervisor restarts it; returns once `init/1` and its continue ran,
  # and the lookups that check started have answered
  defp restart do
    :ok = Supervisor.terminate_child(Brando.Supervisor, ServedHosts)
    {:ok, _pid} = Supervisor.restart_child(Brando.Supervisor, ServedHosts)
    ServedHosts.settled()
  end

  defp lines(file), do: file |> File.read!() |> String.split("\n", trim: true)

  # Traces calls to these `:file` functions in every task the process starts
  # from now on: the writes run in tasks of their own
  defp trace_writes(functions) do
    supervisor = Process.whereis(Brando.Tenant.ServedHosts.TaskSupervisor)
    for function <- functions, do: :erlang.trace_pattern({:file, function, :_}, true, [:global])
    :erlang.trace(supervisor, true, [:call, :set_on_spawn])

    on_exit(fn ->
      if Process.alive?(supervisor), do: :erlang.trace(supervisor, false, [:call, :set_on_spawn])
      for function <- functions, do: :erlang.trace_pattern({:file, function, :_}, false, [:global])
    end)
  end

  # The traced `:file` calls made so far, in order, with their arguments
  defp file_calls do
    receive do
      {:trace, _pid, :call, {:file, function, args}} -> [{function, args} | file_calls()]
    after
      0 -> []
    end
  end

  defp file_functions, do: Enum.map(file_calls(), &elem(&1, 0))

  defp callers_of_file_functions do
    receive do
      {:trace, caller, :call, {:file, function, _args}} -> [{caller, function} | callers_of_file_functions()]
    after
      0 -> []
    end
  end

  # Holds the next write before it reads the file, until `release_write/1`
  defp hold_writes(file) do
    test = self()

    put_test_env(ServedHosts,
      file: file,
      addresses: [@here, @here_v6],
      before_write: fn ->
        send(test, {:writing, self()})

        receive do
          :write -> :ok
        end
      end
    )
  end

  defp release_write(writer), do: send(writer, :write)

  # Holds the next write once its temporary file is synced, before its
  # rename, until the writer is sent `:rename`
  defp hold_renames(file) do
    test = self()

    put_test_env(ServedHosts,
      file: file,
      addresses: [@here, @here_v6],
      before_rename: fn ->
        send(test, {:renaming, self()})

        receive do
          :rename -> :ok
        end
      end
    )
  end

  defp release_rename(writer) do
    ref = Process.monitor(writer)
    send(writer, :rename)
    assert_receive {:DOWN, ^ref, :process, ^writer, _reason}
  end

  # The process's state once `fun` holds for it, polled for up to two seconds
  defp await_state(fun, tries \\ 200) do
    state = :sys.get_state(ServedHosts)

    cond do
      fun.(state) -> state
      tries == 0 -> flunk("the state never matched: #{inspect(state)}")
      true -> Process.sleep(10) && await_state(fun, tries - 1)
    end
  end

  # Polls until the process has `count` messages waiting, for up to two seconds
  defp await_mailbox(pid, count, tries \\ 200) do
    {:message_queue_len, waiting} = Process.info(pid, :message_queue_len)

    cond do
      waiting >= count -> :ok
      tries == 0 -> flunk("#{waiting} messages waiting, not #{count}")
      true -> Process.sleep(10) && await_mailbox(pid, count, tries - 1)
    end
  end

  defp flush_lookups do
    receive do
      {:looked_up, _host} -> flush_lookups()
    after
      0 -> :ok
    end
  end

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

    test "a host unbound while its lookup runs is not written", %{path: file, site: site} do
      :persistent_term.put({BlockingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({BlockingResolver, :pid}) end)
      # Bound while its DNS does not resolve yet
      environment = bind(site, "late", "late.acme.test")
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: BlockingResolver)
      DNS.answer("late.acme.test", [@here])

      trace_writes([:write])

      check = Task.async(fn -> ServedHosts.check() end)
      assert_receive {:looking_up, "late.acme.test", lookup}
      {:ok, _} = Registry.update_environment(Registry.get_environment(environment.id), %{domain: nil}, actor: :system)
      send(lookup, :answer)

      assert %{hosts: hosts} = Task.await(check)
      refute Map.has_key?(hosts, "late.acme.test")
      refute Enum.any?(file_calls(), &match?({:write, [_io, "late.acme.test\n"]}, &1))
      assert File.read!(file) == ""
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

    test "after a start, this server's addresses are looked up though no host needs a lookup",
         %{path: file, site: site} do
      put_test_env(ServedHosts, file: file)
      DNS.answer("localhost", [@here])
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      assert lines(file) == ["www.acme.test"]

      # Every host is in the file, so the new process looks none up
      :persistent_term.erase({ServedHosts, :status})
      restart()

      assert %{addresses: [@here], hosts: %{"www.acme.test" => :served}} = ServedHosts.status()
    end
  end

  # `{:incomplete, addresses, families, reasons}`: what
  # `Brando.Tenant.ServedHosts.DNS` answers when the query of a family timed
  # out or its name server failed. A custom resolver may leave the reasons out.
  describe "a lookup that could not read a family" do
    test "admits nothing on the other family's addresses, and the host is admitted once both are read",
         %{path: file, site: site} do
      DNS.answer("www.acme.test", {:incomplete, [@here], [:inet6], %{inet6: :server_failure}})
      bind(site, "production", "www.acme.test", true)

      assert %{hosts: %{"www.acme.test" => {:lookup_failed, %{inet6: :server_failure}}}, error: nil} =
               ServedHosts.check()

      assert File.read!(file) == ""

      # No AAAA record: the IPv4 address is all there is
      DNS.answer("www.acme.test", [@here])
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.check()
      assert lines(file) == ["www.acme.test"]
    end

    test "with no addresses read, does not count as not resolving", %{path: file, site: site} do
      DNS.answer("www.acme.test", {:incomplete, [], [:inet], %{inet: :refused}})
      bind(site, "production", "www.acme.test", true)

      assert %{hosts: %{"www.acme.test" => {:lookup_failed, %{inet: :refused}}}} = ServedHosts.check()
      assert File.read!(file) == ""
    end

    test "both families timing out leave the host not looked up, not unresolved", %{path: file, site: site} do
      DNS.answer("www.acme.test", {:error, :timeout})
      bind(site, "production", "www.acme.test", true)

      assert %{hosts: %{"www.acme.test" => {:lookup_failed, %{inet: :timeout, inet6: :timeout}}}} =
               ServedHosts.check()

      assert File.read!(file) == ""
    end

    test "a reason outside the known ones, or none, is another error", %{site: site} do
      DNS.answer("one.acme.test", {:incomplete, [@here], [:inet6]})
      DNS.answer("two.acme.test", {:incomplete, [], [:inet, :inet6], %{inet: :formerr}})
      DNS.answer("three.acme.test", {:error, :econnrefused})
      DNS.answer("four.acme.test", {:error, :no_name_servers})
      for key <- ~w(one two three four), do: bind(site, key, "#{key}.acme.test")

      assert %{hosts: hosts} = ServedHosts.check()
      assert hosts["one.acme.test"] == {:lookup_failed, %{inet6: :other}}
      assert hosts["two.acme.test"] == {:lookup_failed, %{inet: :other, inet6: :other}}
      assert hosts["three.acme.test"] == {:lookup_failed, %{inet: :other, inet6: :other}}
      assert hosts["four.acme.test"] == {:lookup_failed, %{inet: :no_name_servers, inet6: :no_name_servers}}
    end

    test "a host whose latest lookup could not be read shows that, not what an earlier one found",
         %{path: file, site: site} do
      DNS.answer("away.acme.test", [@elsewhere])
      bind(site, "away", "away.acme.test")
      bind(site, "missing", "missing.acme.test")

      assert %{hosts: %{"away.acme.test" => {:waiting, [@elsewhere]}, "missing.acme.test" => :unresolved}} =
               ServedHosts.check()

      DNS.answer("away.acme.test", {:incomplete, [@here], [:inet6], %{inet6: :timeout}})
      DNS.answer("missing.acme.test", {:incomplete, [], [:inet6], %{inet6: :server_failure}})

      assert %{
               hosts: %{
                 "away.acme.test" => {:lookup_failed, %{inet6: :timeout}},
                 "missing.acme.test" => {:lookup_failed, %{inet6: :server_failure}}
               }
             } = ServedHosts.check()

      assert File.read!(file) == ""
    end

    test "is logged when a host enters it and when its reason changes, not on every retry", %{site: site} do
      previous = Logger.level()
      Logger.configure(level: :warning)
      on_exit(fn -> Logger.configure(level: previous) end)
      DNS.answer("www.acme.test", {:incomplete, [@here], [:inet6], %{inet6: :server_failure}})

      log = capture_log(fn -> bind(site, "production", "www.acme.test", true) end)
      assert [line] = Regex.scan(~r/Could not look up www\.acme\.test.*/, log)
      assert hd(line) =~ "IPv6: server_failure"

      assert capture_log(fn -> ServedHosts.check() end) =~ ~r/\A\s*\z/

      DNS.answer("www.acme.test", {:incomplete, [@here], [:inet6], %{inet6: :timeout}})
      assert capture_log(fn -> ServedHosts.check() end) =~ ~r/Could not look up www\.acme\.test.*IPv6: timeout/
    end

    # A host in the file is not looked up again, so the one way an unread
    # answer meets it: the host goes in the file while its lookup runs
    test "a host another node puts in the file while its lookup runs stays served", %{path: file, site: site} do
      DNS.hold("www.acme.test", self())
      DNS.answer("www.acme.test", {:incomplete, [@elsewhere], [:inet6], %{inet6: :timeout}})

      {:ok, _environment} =
        Registry.create_environment(site, %{name: "production", key: "production", domain: "www.acme.test"},
          actor: :system
        )

      assert_receive {:looking_up, "www.acme.test", lookup}
      File.write!(file, "www.acme.test\n")
      send(lookup, :answer)

      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.settled()
      assert lines(file) == ["www.acme.test"]

      # The next check, as the five-minute recheck runs it
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.check()
      assert lines(file) == ["www.acme.test"]
    end

    test "a host not looked up is looked up again on the retry timer", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], retry_interval: 20)
      DNS.answer("www.acme.test", {:incomplete, [@here], [:inet6]})
      bind(site, "production", "www.acme.test", true)
      assert %{hosts: %{"www.acme.test" => {:lookup_failed, %{inet6: :other}}}} = ServedHosts.status()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())

      DNS.answer("www.acme.test", [@here])

      assert_receive {:served_hosts, %{hosts: %{"www.acme.test" => :served}}}
      assert File.read!(file) == "www.acme.test\n"
    end

    test "a timed-out lookup is retried once soon, then on the retry timer", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], timeout_retry_interval: 20)
      # As a caching resolver answers a name's first query too slowly
      DNS.answer("new.acme.test", {:incomplete, [], [:inet], %{inet: :timeout}})
      bind(site, "new", "new.acme.test")
      assert %{hosts: %{"new.acme.test" => {:lookup_failed, %{inet: :timeout}}}} = ServedHosts.status()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())

      DNS.answer("new.acme.test", {:error, :nxdomain})

      assert_receive {:served_hosts, %{hosts: %{"new.acme.test" => :unresolved}}}
    end

    test "the quick retry after a timeout runs once, and not for another failure", %{path: file, site: site} do
      :persistent_term.put({NotifyingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({NotifyingResolver, :pid}) end)
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: NotifyingResolver, timeout_retry_interval: 300)
      DNS.answer("slow.acme.test", {:error, :timeout})
      DNS.answer("broken.acme.test", {:incomplete, [], [:inet6], %{inet6: :server_failure}})
      bind(site, "broken", "broken.acme.test")
      bind(site, "slow", "slow.acme.test")
      flush_lookups()

      # The quick retry looks up the timed-out host alone, which times out
      # again and so waits for the minute
      assert_receive {:looked_up, "slow.acme.test"}, 1_000
      ServedHosts.settled()
      refute_receive {:looked_up, _host}, 600
      assert %{hosts: %{"slow.acme.test" => {:lookup_failed, %{inet: :timeout}}}} = ServedHosts.status()
    end

    test "a host that times out while another's quick retry waits gets its own", %{path: file, site: site} do
      :persistent_term.put({NotifyingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({NotifyingResolver, :pid}) end)
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: NotifyingResolver, timeout_retry_interval: 300)
      DNS.answer("first.acme.test", {:error, :timeout})
      DNS.answer("second.acme.test", {:error, :timeout})
      bind(site, "first", "first.acme.test")
      bind(site, "second", "second.acme.test")
      flush_lookups()

      # The first host's retry, armed before the second timed out, retries it
      # alone; the second waits its own interval
      assert_receive {:looked_up, "first.acme.test"}, 1_000
      refute_receive {:looked_up, "second.acme.test"}, 150
      assert_receive {:looked_up, "second.acme.test"}, 1_000
      ServedHosts.settled()
      refute_receive {:looked_up, _host}, 600
    end

    test "the quick retry leaves alone an answer that came in before it, while a write runs",
         %{path: file, site: site} do
      :persistent_term.put({NotifyingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({NotifyingResolver, :pid}) end)
      test = self()
      config = [file: file, addresses: [@here], resolver: NotifyingResolver, timeout_retry_interval: 300]
      put_test_env(ServedHosts, config)
      DNS.answer("slow.acme.test", {:error, :timeout})
      bind(site, "slow", "slow.acme.test")
      flush_lookups()

      # A refresh looks the host up again before its quick retry, and the
      # answer waits for a write that is held past the retry's time
      DNS.answer("slow.acme.test", [@here])

      put_test_env(
        ServedHosts,
        config ++
          [
            flush_interval: 20,
            before_write: fn ->
              send(test, {:writing, self()})

              receive do
                :write -> :ok
              end
            end
          ]
      )

      refresh = Task.async(fn -> ServedHosts.registry_changed() end)
      assert_receive {:writing, check}
      release_write(check)
      assert_receive {:looked_up, "slow.acme.test"}
      assert_receive {:writing, flush}
      refute_receive {:looked_up, "slow.acme.test"}, 600

      put_test_env(ServedHosts, config)
      release_write(flush)
      Task.await(refresh)
      assert %{hosts: %{"slow.acme.test" => :served}} = ServedHosts.settled()
      assert lines(file) == ["slow.acme.test"]
    end

    test "of this server's addresses leaves them unknown: the last ones found count", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file)
      DNS.answer("localhost", [@here])
      DNS.answer("away.acme.test", [@elsewhere])
      # Waits for its DNS, so every check looks this server's addresses up
      bind(site, "away", "away.acme.test")
      assert %{addresses: [@here]} = ServedHosts.check()

      # Only the IPv6 family read: the IPv4 address found before still counts
      DNS.answer("localhost", {:incomplete, [@here_v6], [:inet]})
      assert %{addresses: [@here]} = ServedHosts.check()
    end

    test "of this server's addresses, with none found before, admits no host", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file)
      DNS.answer("localhost", {:incomplete, [@here], [:inet6]})
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)

      assert %{addresses: [], hosts: %{"www.acme.test" => {:waiting, [@here]}}} = ServedHosts.check()
      assert File.read!(file) == ""

      DNS.answer("localhost", [@here])
      assert %{addresses: [@here], hosts: %{"www.acme.test" => :served}} = ServedHosts.check()
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
        "203.0.113.10",
        # IPv4 literals the resolver reads, in hexadecimal and short forms
        "203.0.113.0x0a",
        "0xcb.0x00.0x71.0x0a"
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

  describe "redirect hosts" do
    defp put_redirect_hosts(environment, hosts) do
      {:ok, environment} =
        Registry.update_environment(Registry.get_environment(environment.id), %{redirect_hosts: hosts}, actor: :system)

      environment
    end

    test "one pointing here is admitted and written, one pointing elsewhere waits", %{path: file, site: site} do
      DNS.answer("acme.test", [@here])
      DNS.answer("www.acme.test", [@here, @here_v6])
      DNS.answer("old-acme.test", [@elsewhere])
      production = bind(site, "production", "acme.test", true)
      put_redirect_hosts(production, ["www.acme.test", "old-acme.test", "gone-acme.test"])

      status = ServedHosts.check()

      assert lines(file) == ["acme.test", "www.acme.test"]

      assert status.hosts == %{
               "acme.test" => :served,
               "www.acme.test" => :served,
               "old-acme.test" => {:waiting, [@elsewhere]},
               "gone-acme.test" => :unresolved
             }
    end

    test "one removed from the environment is removed from the file", %{path: file, site: site} do
      DNS.answer("acme.test", [@here])
      DNS.answer("www.acme.test", [@here])
      DNS.answer("old-acme.test", [@here])
      production = bind(site, "production", "acme.test", true)
      production = put_redirect_hosts(production, ["www.acme.test", "old-acme.test"])
      ServedHosts.check()
      assert lines(file) == ["acme.test", "old-acme.test", "www.acme.test"]

      put_redirect_hosts(production, ["www.acme.test"])
      %{hosts: hosts} = ServedHosts.check()

      assert lines(file) == ["acme.test", "www.acme.test"]
      refute Map.has_key?(hosts, "old-acme.test")
    end

    test "set_live on a dynamic site moves them with the domain and leaves the file alone",
         %{path: file, site: site} do
      for host <- ~w(acme.test www.acme.test next.acme.test www.next.acme.test), do: DNS.answer(host, [@here])
      production = bind(site, "production", "acme.test", true)
      put_redirect_hosts(production, ["www.acme.test"])
      staging = bind(site, "staging", "next.acme.test")
      put_redirect_hosts(staging, ["www.next.acme.test"])
      ServedHosts.check()
      assert lines(file) == ~w(acme.test next.acme.test www.acme.test www.next.acme.test)
      before = File.stat!(file, time: :posix)
      # Every host is in the file: none is looked up again
      for host <- ~w(acme.test www.acme.test next.acme.test www.next.acme.test), do: DNS.answer(host, [@elsewhere])

      assert {:ok, %{live: true, domain: "acme.test", redirect_hosts: ["www.acme.test"]}} =
               Environments.set_live(Registry.get_environment(staging.id))

      %{hosts: hosts} = ServedHosts.check()
      assert lines(file) == ~w(acme.test next.acme.test www.acme.test www.next.acme.test)
      assert File.stat!(file, time: :posix).inode == before.inode
      assert Enum.all?(hosts, fn {_host, state} -> state == :served end)
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

    test "a host another node wrote while the lookups ran is kept, and remembered", %{path: file, site: site} do
      :persistent_term.put({BlockingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({BlockingResolver, :pid}) end)
      # Bound while their DNS does not resolve yet
      bind(site, "h", "h.acme.test")
      bind(site, "k", "k.acme.test")
      assert File.read!(file) == ""
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: BlockingResolver)
      DNS.answer("h.acme.test", {:error, :timeout})
      DNS.answer("k.acme.test", [@here])

      check = Task.async(fn -> ServedHosts.check() end)
      assert_receive {:looking_up, "h.acme.test", h_lookup}
      assert_receive {:looking_up, "k.acme.test", k_lookup}
      # Another node sharing the path admitted it meanwhile
      File.write!(file, "h.acme.test\n")
      send(h_lookup, :answer)
      send(k_lookup, :answer)

      assert %{hosts: %{"h.acme.test" => :served, "k.acme.test" => :served}} = Task.await(check)
      assert lines(file) == ["h.acme.test", "k.acme.test"]

      # Lost again, while its DNS still fails: it goes back in without a lookup
      put_test_env(ServedHosts, file: file, addresses: [@here])
      File.write!(file, "k.acme.test\n")
      assert %{hosts: %{"h.acme.test" => :served}} = ServedHosts.check()
      assert lines(file) == ["h.acme.test", "k.acme.test"]
    end

    test "a host bound and admitted by another node while a write waits to read the file stays in it",
         %{path: file, site: site} do
      DNS.answer("a.acme.test", [@here])
      bind(site, "a", "a.acme.test")
      hold_writes(file)
      ServedHosts.registry_changed()
      assert_receive {:writing, writer}

      # Bound while the write waits, failing its lookup here, and admitted by
      # another node sharing the path
      DNS.answer("b.acme.test", {:error, :timeout})
      {:ok, _} = Registry.create_environment(site, %{name: "b", key: "b", domain: "b.acme.test"}, actor: :system)
      File.write!(file, "a.acme.test\nb.acme.test\n")
      put_test_env(ServedHosts, file: file, addresses: [@here, @here_v6])
      release_write(writer)

      assert %{hosts: %{"b.acme.test" => :served}} = ServedHosts.settled()
      assert lines(file) == ["a.acme.test", "b.acme.test"]
    end

    test "a file that cannot be read again before the write is left alone and reported",
         %{path: file, site: site} do
      :persistent_term.put({BlockingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({BlockingResolver, :pid}) end)
      bind(site, "k", "k.acme.test")
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: BlockingResolver)
      DNS.answer("k.acme.test", [@here])

      check = Task.async(fn -> ServedHosts.check() end)
      assert_receive {:looking_up, "k.acme.test", lookup}
      File.write!(file, "h.acme.test\n")
      File.chmod!(file, 0o000)
      on_exit(fn -> File.chmod(file, 0o644) end)

      log =
        capture_log(fn ->
          send(lookup, :answer)
          assert %{error: error} = Task.await(check)
          assert error =~ file
        end)

      assert log =~ "Could not update the served hosts file"
      File.chmod!(file, 0o644)
      assert File.read!(file) == "h.acme.test\n"
    end

    test "a write of a process that restarted does not replace the file its successor wrote",
         %{path: file, tmp_dir: tmp_dir, site: site} do
      DNS.answer("a.acme.test", [@here])
      bind(site, "a", "a.acme.test")
      # Another node sharing the path wrote over it, so the next write renames
      File.write!(file, "")
      hold_renames(file)
      ServedHosts.registry_changed()
      assert_receive {:renaming, writer}

      put_test_env(ServedHosts, file: file, addresses: [@here, @here_v6])
      DNS.answer("b.acme.test", [@here])
      {:ok, _} = Registry.create_environment(site, %{name: "b", key: "b", domain: "b.acme.test"}, actor: :system)
      restart()
      assert lines(file) == ["a.acme.test", "b.acme.test"]

      release_rename(writer)

      assert lines(file) == ["a.acme.test", "b.acme.test"]
      assert File.ls!(tmp_dir) == ["served_hosts"]
    end

    test "a write whose work was dropped while the file changed away and back does not replace the file",
         %{path: file, tmp_dir: tmp_dir, site: site} do
      DNS.answer("a.acme.test", [@here])
      bind(site, "a", "a.acme.test")
      # Another node sharing the path wrote over it, so the next write renames
      File.write!(file, "")
      hold_renames(file)
      ServedHosts.registry_changed()
      assert_receive {:renaming, writer}

      pid = Process.whereis(ServedHosts)
      put_test_env(ServedHosts, file: Path.join(tmp_dir, "other_hosts"), addresses: [@here, @here_v6])
      ServedHosts.registry_changed()
      :sys.get_state(pid)
      put_test_env(ServedHosts, file: file, addresses: [@here, @here_v6])
      ServedHosts.registry_changed()
      :sys.get_state(pid)
      # Written by another node since the old write read the file
      File.write!(file, "a.acme.test\nbeta.example.com\n")

      :sys.suspend(pid)
      release_rename(writer)
      assert File.read!(file) == "a.acme.test\nbeta.example.com\n"
      :sys.resume(pid)
      ServedHosts.settled()
    end

    test "a write under way when the file is unset leaves the file alone", %{path: file, tmp_dir: tmp_dir, site: site} do
      DNS.answer("a.acme.test", [@here])
      bind(site, "a", "a.acme.test")
      # Another node sharing the path wrote over it, so the next write renames
      File.write!(file, "")
      hold_renames(file)
      ServedHosts.registry_changed()
      assert_receive {:renaming, writer}

      put_test_env(ServedHosts, [])
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())
      release_rename(writer)
      ServedHosts.settled()

      assert File.read!(file) == ""
      assert File.ls!(tmp_dir) == ["served_hosts"]
      refute_received {:served_hosts, _status}
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

    test "the temporary file is synced to disk before it is renamed over the old one", %{site: site} do
      trace_writes([:sync, :rename])

      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)

      assert file_functions() == [:sync, :rename]
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

    test "a resolver that raises leaves the host not looked up", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: RaisingResolver)
      bind(site, "production", "www.acme.test", true)

      assert %{hosts: %{"www.acme.test" => {:lookup_failed, %{inet: :other, inet6: :other}}}, error: nil} =
               ServedHosts.check()

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
      test "a lookup that fails with #{inspect(resolver)} leaves the host not looked up", %{path: file, site: site} do
        pid = Process.whereis(ServedHosts)
        # No addresses: the endpoint's host goes through the same resolver
        put_test_env(ServedHosts, file: file, resolver: @resolver, lookup_timeout: 50)
        bind(site, "production", "www.acme.test", true)

        assert %{hosts: %{"www.acme.test" => {:lookup_failed, %{inet: _, inet6: _}}}, addresses: [], error: nil} =
                 ServedHosts.check()

        assert Process.whereis(ServedHosts) == pid
        assert File.read!(file) == ""
      end
    end

    defmodule StuckResolver do
      # The task that times the lookup never answers, as when a lookup in a
      # NIF cannot be killed: it is suspended
      def lookup(_host) do
        [timer | _callers] = Process.get(:"$callers")
        send(:persistent_term.get({__MODULE__, :pid}), {:stuck, timer})
        :erlang.suspend_process(timer)
        Process.sleep(:infinity)
      end
    end

    test "a lookup whose task never answers fails at its deadline and frees its slot", %{path: file, site: site} do
      :persistent_term.put({StuckResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({StuckResolver, :pid}) end)
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: StuckResolver, lookup_timeout: 50)
      hosts = for index <- 1..9, do: "h#{index}.acme.test"
      environments = for index <- 1..9, do: bind(site, "e#{index}", nil)
      for {host, environment} <- Enum.zip(hosts, environments), do: set_domain(environment, host)
      Cache.warm()

      check = Task.async(fn -> ServedHosts.check() end)
      assert {:ok, %{hosts: states}} = Task.yield(check, 5_000)
      timers = for {:stuck, timer} <- Enum.map(hosts, fn _host -> assert_receive({:stuck, _timer}) end), do: timer
      on_exit(fn -> Enum.each(timers, &Process.exit(&1, :kill)) end)

      assert Map.take(states, hosts) == Map.new(hosts, &{&1, {:lookup_failed, %{inet: :timeout, inet6: :timeout}}})
      assert %{lookups: lookups} = :sys.get_state(ServedHosts)
      assert lookups == %{}
    end

    test "a flush that raises leaves no flush timer behind", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], flush_interval: :timer.minutes(10))
      hosts = ~w(a.acme.test b.acme.test)

      for host <- hosts do
        DNS.answer(host, [@here])
        DNS.hold(host, self())
      end

      bind_at_once(site, hosts)
      assert_receive {:looking_up, "a.acme.test", a_lookup}
      assert_receive {:looking_up, "b.acme.test", b_lookup}
      # Answered while the other runs: a flush is due in ten minutes
      send(a_lookup, :answer)
      assert await_state(&is_reference(&1.flush_timer))

      # The batch's flush raises: the cache is broken
      sites = :persistent_term.get({:brando, :sites})
      :persistent_term.put({:brando, :sites}, :broken)

      log =
        capture_log(fn ->
          send(b_lookup, :answer)
          assert %{flush_timer: nil, flush: nil} = await_state(&(&1.error != nil))
        end)

      assert log =~ "Could not update the served hosts file"
      :persistent_term.put({:brando, :sites}, sites)
    end

    test "a dead task supervisor leaves the host not looked up, the file alone and the process running",
         %{path: file, site: site} do
      pid = Process.whereis(ServedHosts)
      bind(site, "production", "www.acme.test", true)
      DNS.answer("www.acme.test", [@here])
      :ok = Supervisor.terminate_child(Brando.Supervisor, Brando.Tenant.ServedHosts.TaskSupervisor)
      on_exit(fn -> Supervisor.restart_child(Brando.Supervisor, Brando.Tenant.ServedHosts.TaskSupervisor) end)

      log =
        capture_log(fn ->
          assert %{hosts: %{"www.acme.test" => {:lookup_failed, %{inet: :other, inet6: :other}}}, error: error} =
                   ServedHosts.check()

          assert error =~ "no task supervisor"
        end)

      assert log =~ "Could not update the served hosts file"
      assert Process.whereis(ServedHosts) == pid
      assert File.read!(file) == ""
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

  describe "after a registry write" do
    test "a newly bound host is checking at once, and a slow lookup of another host does not hold its result back",
         %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here, @here_v6], flush_interval: 20)
      DNS.answer("acme.test", [@here])
      production = bind(site, "production", "acme.test", true)
      # Waits for its DNS, so every check looks it up again
      bind(site, "away", "away.acme.test")
      assert %{hosts: %{"away.acme.test" => :unresolved}} = ServedHosts.status()
      DNS.hold("away.acme.test", self())
      DNS.hold("no-record.acme.test", self())
      # A check under way, its lookup of the waiting host slow to answer
      check = Task.async(fn -> ServedHosts.check() end)
      assert_receive {:looking_up, "away.acme.test", away_lookup}
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())

      {:ok, _} =
        Registry.update_environment(Registry.get_environment(production.id), %{redirect_hosts: ["no-record.acme.test"]},
          actor: :system
        )

      assert %{hosts: %{"no-record.acme.test" => :checking, "away.acme.test" => :unresolved}} = ServedHosts.status()
      # Answered while the other lookup still runs
      assert_receive {:looking_up, "no-record.acme.test", lookup}
      send(lookup, :answer)
      assert_receive {:served_hosts, %{hosts: %{"no-record.acme.test" => :unresolved}}}

      send(away_lookup, :answer)
      assert %{hosts: %{"away.acme.test" => :unresolved, "no-record.acme.test" => :unresolved}} = Task.await(check)
    end

    test "a lookup that does not answer fails at the lookup timeout", %{path: file, site: site} do
      DNS.answer("acme.test", [@here])
      production = bind(site, "production", "acme.test", true)
      put_test_env(ServedHosts, file: file, addresses: [@here], lookup_timeout: 100)
      DNS.hold("slow.acme.test", self())
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())

      {:ok, _} =
        Registry.update_environment(Registry.get_environment(production.id), %{redirect_hosts: ["slow.acme.test"]},
          actor: :system
        )

      assert %{hosts: %{"slow.acme.test" => :checking}} = ServedHosts.status()
      # Never answered
      assert_receive {:looking_up, "slow.acme.test", _lookup}

      assert_receive {:served_hosts,
                      %{hosts: %{"slow.acme.test" => {:lookup_failed, %{inet: :timeout, inet6: :timeout}}}}},
                     2_000
    end

    test "the process does no file work itself: a task reads and writes the file", %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      environment = bind(site, "production", nil, true)
      # Stored without a registry write: only the warm below asks for a check
      set_domain(environment, "www.acme.test")
      pid = Process.whereis(ServedHosts)
      :erlang.trace(pid, true, [:call])
      on_exit(fn -> :erlang.trace(pid, false, [:call]) end)
      trace_writes([:_])

      Cache.warm()
      ServedHosts.settled()
      :erlang.trace(pid, false, [:call])

      calls = callers_of_file_functions()
      refute Enum.any?(calls, &match?({^pid, _function}, &1))
      assert Enum.any?(calls, &match?({_task, :read_file}, &1))
      assert Enum.any?(calls, &match?({_task, :rename}, &1))
      assert File.read!(file) == "www.acme.test\n"
    end

    test "a registry write returns at once while a write of the file is held, and its new host has a state",
         %{path: file, site: site} do
      DNS.answer("acme.test", [@here])
      production = bind(site, "production", "acme.test", true)
      hold_writes(file)

      # The first write holds, as on a stalled mount
      {:ok, _} =
        Registry.update_environment(Registry.get_environment(production.id), %{redirect_hosts: ["www.acme.test"]},
          actor: :system
        )

      assert_receive {:writing, writer}

      {elapsed, {:ok, _}} =
        :timer.tc(fn ->
          Registry.update_environment(
            Registry.get_environment(production.id),
            %{redirect_hosts: ["www.acme.test", "old-acme.test"]},
            actor: :system
          )
        end)

      assert elapsed < 1_000_000
      assert %{hosts: %{"old-acme.test" => :checking}} = ServedHosts.status()

      DNS.answer("old-acme.test", [@here])
      put_test_env(ServedHosts, file: file, addresses: [@here, @here_v6])
      release_write(writer)
      assert %{hosts: %{"old-acme.test" => :served}} = ServedHosts.settled()
      assert lines(file) == ["acme.test", "old-acme.test"]
    end

    test "a write of the old file that ends after the file changed admits nothing to the new one",
         %{path: file, tmp_dir: tmp_dir, site: site} do
      DNS.answer("a.acme.test", [@here])
      bind(site, "a", "a.acme.test")
      # A lookup under way, whose answer comes once the file has changed
      DNS.hold("h.acme.test", self())
      {:ok, _} = Registry.create_environment(site, %{name: "h", key: "h", domain: "h.acme.test"}, actor: :system)
      assert_receive {:looking_up, "h.acme.test", lookup}
      # Another node sharing the path wrote over it, so the next write renames
      File.write!(file, "")
      hold_renames(file)
      ServedHosts.registry_changed()
      assert_receive {:renaming, writer}

      # The answer arrives first; the write to the old file then passes its
      # checks and ends; then the file changes, to a server whose addresses differ
      pid = Process.whereis(ServedHosts)
      :sys.suspend(pid)
      send(lookup, :answer)
      await_mailbox(pid, 1)
      release_rename(writer)
      new_file = Path.join(tmp_dir, "other_hosts")
      put_test_env(ServedHosts, file: new_file, addresses: [@elsewhere])
      :sys.resume(pid)

      # The new file's check looks every host up
      assert_receive {:looking_up, "h.acme.test", lookup}
      send(lookup, :answer)

      assert %{file: ^new_file, hosts: %{"a.acme.test" => {:waiting, [@here]}}} = ServedHosts.settled()
      assert File.read!(new_file) == ""
      assert lines(file) == ["a.acme.test"]
    end

    test "a file that cannot be read still gives a newly bound host its state and its result",
         %{path: file, site: site} do
      DNS.answer("acme.test", [@here])
      production = bind(site, "production", "acme.test", true)
      File.write!(file, "acme.test\nother.example.com\n")
      File.chmod!(file, 0o000)
      on_exit(fn -> File.chmod(file, 0o644) end)
      DNS.hold("away.acme.test", self())
      DNS.answer("away.acme.test", [@elsewhere])

      capture_log(fn ->
        {:ok, _} =
          Registry.update_environment(Registry.get_environment(production.id), %{redirect_hosts: ["away.acme.test"]},
            actor: :system
          )

        assert %{hosts: %{"away.acme.test" => :checking}} = ServedHosts.status()
        assert_receive {:looking_up, "away.acme.test", lookup}
        send(lookup, :answer)

        assert %{hosts: %{"acme.test" => :served, "away.acme.test" => {:waiting, [@elsewhere]}}, error: error} =
                 ServedHosts.settled()

        assert error =~ file
      end)

      File.chmod!(file, 0o644)
      assert File.read!(file) == "acme.test\nother.example.com\n"
    end

    test "a newly bound host that is no full host name is invalid at once", %{site: site} do
      DNS.answer("acme.test", [@here])
      production = bind(site, "production", "acme.test", true)

      {:ok, _} =
        Registry.update_environment(Registry.get_environment(production.id), %{redirect_hosts: ["intranet"]},
          actor: :system
        )

      assert %{hosts: %{"intranet" => :invalid}} = ServedHosts.status()
    end
  end

  describe "lookups" do
    test "this server's addresses are looked up once per check, and a failed lookup keeps the last ones",
         %{path: file, site: site} do
      :persistent_term.put({NotifyingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({NotifyingResolver, :pid}) end)
      put_test_env(ServedHosts, file: file, resolver: NotifyingResolver)
      DNS.answer("localhost", [@here])
      for key <- ~w(a b c), do: bind(site, key, "#{key}.acme.test")
      flush_lookups()

      assert %{addresses: [@here], hosts: %{"a.acme.test" => :unresolved}} = ServedHosts.check()
      assert_received {:looked_up, "localhost"}
      refute_received {:looked_up, "localhost"}

      DNS.answer("localhost", {:error, :timeout})

      assert %{addresses: [@here], hosts: %{"a.acme.test" => :unresolved}} = ServedHosts.check()
      assert_received {:looked_up, "localhost"}
    end

    test "this server's addresses are forgotten once they have failed to refresh for :addresses_max_age",
         %{path: file, site: site} do
      put_test_env(ServedHosts, file: file)
      DNS.answer("localhost", [@here])
      DNS.answer("away.acme.test", [@elsewhere])
      # Waits for its DNS, so every check looks this server's addresses up
      bind(site, "away", "away.acme.test")
      assert %{addresses: [@here]} = ServedHosts.check()

      DNS.answer("localhost", {:error, :timeout})
      put_test_env(ServedHosts, file: file, addresses_max_age: 1)
      Process.sleep(5)

      assert %{addresses: [], hosts: %{"away.acme.test" => {:waiting, [@elsewhere]}}} = ServedHosts.check()
    end

    test "this server's addresses past :addresses_max_age admit no host while their refresh runs",
         %{path: file, site: site} do
      put_test_env(ServedHosts, file: file)
      DNS.answer("localhost", [@here])
      DNS.answer("away.acme.test", [@elsewhere])
      # Waits for its DNS, so every check looks this server's addresses up
      bind(site, "away", "away.acme.test")
      assert %{addresses: [@here]} = ServedHosts.status()

      put_test_env(ServedHosts, file: file, addresses_max_age: 1)
      Process.sleep(5)
      DNS.hold("localhost", self())
      DNS.answer("new.acme.test", [@here])
      {:ok, _} = Registry.create_environment(site, %{name: "new", key: "new", domain: "new.acme.test"}, actor: :system)
      assert_receive {:looking_up, "localhost", lookup}

      # The new host's answer has been written while the refresh runs
      await_state(fn state ->
        MapSet.member?(state.admitted, "new.acme.test") or
          (Map.has_key?(state.results, "new.acme.test") and is_nil(state.flush_timer) and is_nil(state.writing))
      end)

      assert File.read!(file) == ""
      assert %{hosts: %{"new.acme.test" => :checking}} = ServedHosts.status()

      DNS.answer("localhost", {:error, :timeout})
      send(lookup, :answer)

      assert %{addresses: [], hosts: %{"new.acme.test" => {:waiting, [@here]}}} = ServedHosts.settled()
      assert File.read!(file) == ""
    end

    test "a lookup that times out does not erase this server's addresses", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, lookup_timeout: 100)
      DNS.answer("localhost", [@here])
      DNS.answer("away.acme.test", [@elsewhere])
      bind(site, "away", "away.acme.test")
      assert %{addresses: [@here]} = ServedHosts.status()
      DNS.hold("slow.acme.test", self())
      bind(site, "slow", "slow.acme.test")

      assert %{
               addresses: [@here],
               hosts: %{
                 "away.acme.test" => {:waiting, [@elsewhere]},
                 "slow.acme.test" => {:lookup_failed, %{inet: :timeout}}
               }
             } =
               ServedHosts.settled()
    end

    # Every host bound by one warm, so one check queues them all at once
    defp bind_at_once(site, hosts) do
      environments = for index <- 1..length(hosts), do: bind(site, "e#{index}", nil)
      for {host, environment} <- Enum.zip(hosts, environments), do: set_domain(environment, host)
      Cache.warm()
    end

    test "at most eight run at a time, and a queued one starts when one answers", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here])
      hosts = for index <- 1..10, do: "h#{index}.acme.test"

      for host <- hosts do
        DNS.answer(host, [@here])
        DNS.hold(host, self())
      end

      bind_at_once(site, hosts)

      [first | running] = for _ <- 1..8, do: assert_receive({:looking_up, _host, _lookup})
      refute_receive {:looking_up, _host, _lookup}, 100

      {:looking_up, _host, lookup} = first
      send(lookup, :answer)
      ninth = assert_receive {:looking_up, _host, _lookup}
      refute_receive {:looking_up, _host, _lookup}, 100

      [{:looking_up, _host, lookup} | running] = running
      send(lookup, :answer)
      tenth = assert_receive {:looking_up, _host, _lookup}

      for {:looking_up, _host, lookup} <- [ninth, tenth | running], do: send(lookup, :answer)

      %{hosts: states} = ServedHosts.settled()
      assert Map.take(states, hosts) == Map.new(hosts, &{&1, :served})
    end

    test "a queued lookup's timeout counts from its own start", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], lookup_timeout: 1_000)
      hosts = for index <- 1..10, do: "h#{index}.acme.test"

      for host <- hosts do
        DNS.answer(host, [@here])
        DNS.hold(host, self())
      end

      bind_at_once(site, hosts)

      # The first eight never answer and time out; the last two start then,
      # with a timeout of their own, and answer at once
      first = for _ <- 1..8, do: assert_receive({:looking_up, _host, _lookup})

      for _ <- 1..2 do
        assert_receive {:looking_up, _host, lookup}, 5_000
        send(lookup, :answer)
      end

      %{hosts: states} = ServedHosts.settled()
      timed_out = for {:looking_up, host, _lookup} <- first, do: host
      assert Enum.count(states, fn {_host, state} -> state == :served end) == 2
      for host <- timed_out, do: assert(states[host] == {:lookup_failed, %{inet: :timeout, inet6: :timeout}})
    end

    test "answers of one check are written and broadcast once", %{path: file, site: site} do
      # However long the answers take to come in
      put_test_env(ServedHosts, file: file, addresses: [@here], flush_interval: :timer.minutes(10))
      hosts = for index <- 1..5, do: "h#{index}.acme.test"

      for host <- hosts do
        DNS.answer(host, [@here])
        DNS.hold(host, self())
      end

      pid = Process.whereis(ServedHosts)
      trace_writes([:rename])

      # One warm binds all five: one check looks them up
      bind_at_once(site, hosts)
      messages = for _ <- hosts, do: assert_receive({:looking_up, _host, _lookup})
      # The check has published by now
      :sys.get_state(pid)
      file_calls()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())
      for {:looking_up, _host, lookup} <- messages, do: send(lookup, :answer)

      assert %{hosts: states} = ServedHosts.settled()
      assert Map.take(states, hosts) == Map.new(hosts, &{&1, :served})
      assert lines(file) == hosts
      assert file_functions() == [:rename]
      assert_received {:served_hosts, _status}
      refute_received {:served_hosts, _status}
    end

    test "an answer waiting for its batch's write is not looked up again when another check starts",
         %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here])
      DNS.answer("acme.test", [@here])
      production = bind(site, "production", "acme.test", true)
      hosts = ~w(a.acme.test b.acme.test)
      environments = for key <- ~w(a b), do: bind(site, key, nil)

      for {host, environment} <- Enum.zip(hosts, environments) do
        set_domain(environment, host)
        DNS.answer(host, [@here])
        DNS.hold(host, self())
      end

      # One warm binds both: one batch
      Cache.warm()
      assert_receive {:looking_up, "a.acme.test", a_lookup}
      assert_receive {:looking_up, "b.acme.test", b_lookup}
      send(a_lookup, :answer)

      # An unrelated registry write checks again before the batch is written
      {:ok, _} =
        Registry.update_environment(Registry.get_environment(production.id), %{redirect_hosts: ["www.acme.test"]},
          actor: :system
        )

      refute_receive {:looking_up, "a.acme.test", _lookup}, 200
      send(b_lookup, :answer)

      assert %{hosts: %{"a.acme.test" => :served, "b.acme.test" => :served}} = ServedHosts.settled()
      assert lines(file) == ["a.acme.test", "acme.test", "b.acme.test"]
    end

    test "an answer that arrives while a check's write runs is not looked up again after it",
         %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here])
      DNS.answer("acme.test", [@here])
      production = bind(site, "production", "acme.test", true)
      hosts = ~w(a.acme.test b.acme.test)
      environments = for key <- ~w(a b), do: bind(site, key, nil)

      for {host, environment} <- Enum.zip(hosts, environments) do
        set_domain(environment, host)
        DNS.answer(host, [@here])
        DNS.hold(host, self())
      end

      Cache.warm()
      assert_receive {:looking_up, "a.acme.test", a_lookup}
      assert_receive {:looking_up, "b.acme.test", b_lookup}
      hold_writes(file)

      # Another check's write starts before the answer and ends after it
      {:ok, _} =
        Registry.update_environment(Registry.get_environment(production.id), %{redirect_hosts: ["www.acme.test"]},
          actor: :system
        )

      assert_receive {:writing, writer}
      send(a_lookup, :answer)
      :sys.get_state(ServedHosts)
      put_test_env(ServedHosts, file: file, addresses: [@here])
      release_write(writer)

      refute_receive {:looking_up, "a.acme.test", _lookup}, 200
      send(b_lookup, :answer)

      assert %{hosts: %{"a.acme.test" => :served, "b.acme.test" => :served}} = ServedHosts.settled()
      assert lines(file) == ["a.acme.test", "acme.test", "b.acme.test"]
    end

    test "a lookup timeout that is not a number of milliseconds falls back to the default", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], lookup_timeout: "soon")
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)

      assert %{hosts: %{"www.acme.test" => :served}, error: nil} = ServedHosts.check()
      assert lines(file) == ["www.acme.test"]
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

    test "a timer that fires while the cache is cold leaves the file alone", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], recheck_interval: 20)
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      assert lines(file) == ["www.acme.test"]

      pid = Process.whereis(ServedHosts)
      Cache.clear()
      :erlang.trace(pid, true, [:receive])
      on_exit(fn -> :erlang.trace(pid, false, [:receive]) end)

      assert_receive {:trace, ^pid, :receive, {:tick, _}}
      :sys.get_state(pid)

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

    test "with nothing waiting, a slow check reads the file again and puts back a host it lost, without a lookup",
         %{path: file, site: site} do
      :persistent_term.put({NotifyingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({NotifyingResolver, :pid}) end)
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: NotifyingResolver, recheck_interval: 20)
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.status()
      assert_received {:looked_up, "www.acme.test"}

      # Another node sharing the path wrote its stale list, and the DNS fails now
      DNS.answer("www.acme.test", {:error, :timeout})
      File.write!(file, "")
      pid = Process.whereis(ServedHosts)
      :erlang.trace(pid, true, [:receive])
      on_exit(fn -> :erlang.trace(pid, false, [:receive]) end)

      assert_receive {:trace, ^pid, :receive, {:tick, _}}
      ServedHosts.settled()

      assert File.read!(file) == "www.acme.test\n"
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.status()
      refute_received {:looked_up, _host}
    end

    test "a host lost from the file right after a write is put back by the verification, without a lookup",
         %{path: file, site: site} do
      :persistent_term.put({NotifyingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({NotifyingResolver, :pid}) end)
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: NotifyingResolver, verify_interval: 50)
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      assert_received {:looked_up, "www.acme.test"}
      flush_lookups()

      # Another installation sharing the path renames its older list over it
      pid = Process.whereis(ServedHosts)
      :sys.suspend(pid)
      assert %{verify: verify} = :sys.get_state(pid)
      assert verify
      File.write!(file, "")
      :sys.resume(pid)

      await_state(fn _state -> File.read!(file) == "www.acme.test\n" end)
      ServedHosts.settled()
      assert %{hosts: %{"www.acme.test" => :served}} = ServedHosts.status()
      refute_received {:looked_up, _host}
    end

    test "a verification that finds every admitted host in the file writes nothing", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], verify_interval: 50)
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)

      pid = Process.whereis(ServedHosts)
      :sys.suspend(pid)
      assert %{verify: verify} = :sys.get_state(pid)
      assert verify
      trace_writes([:read_file, :open, :rename])
      :sys.resume(pid)

      assert_receive {:trace, _writer, :call, {:file, :read_file, _args}}
      await_state(&(is_nil(&1.verify) and is_nil(&1.writing)))
      ServedHosts.settled()

      assert file_functions() == []
      assert File.read!(file) == "www.acme.test\n"
    end

    test "writes in quick succession leave one verification pending", %{path: file, site: site} do
      put_test_env(ServedHosts, file: file, addresses: [@here], verify_interval: :timer.minutes(10))
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)

      timers =
        for _ <- 1..3 do
          ServedHosts.check()
          %{verify_timer: timer} = :sys.get_state(ServedHosts)
          timer
        end

      [current | earlier] = Enum.reverse(timers)
      assert Enum.uniq(timers) == timers
      assert is_integer(Process.read_timer(current))
      assert Enum.all?(earlier, &(Process.read_timer(&1) == false))
    end

    test "a restarted process starts from the file alone: a host it lost is admitted again",
         %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      bind(site, "production", "www.acme.test", true)
      assert lines(file) == ["www.acme.test"]

      File.write!(file, "")
      DNS.answer("www.acme.test", [@elsewhere])
      restart()

      assert %{hosts: %{"www.acme.test" => {:waiting, [@elsewhere]}}} = ServedHosts.status()
      assert File.read!(file) == ""
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

      assert_receive {:trace, ^pid, :receive, {:tick, _}}
      assert_receive {:trace, ^pid, :receive, {:tick, _}}
      ServedHosts.settled()

      refute_received {:looked_up, _host}
      assert File.read!(file) == "www.acme.test\n"
    end

    test "a tick of a timer a later check replaced runs no check", %{path: file, site: site} do
      :persistent_term.put({NotifyingResolver, :pid}, self())
      on_exit(fn -> :persistent_term.erase({NotifyingResolver, :pid}) end)
      # The default retry interval: no real timer fires during the test
      put_test_env(ServedHosts, file: file, addresses: [@here], resolver: NotifyingResolver)
      # Waits for its DNS, so every check looks it up
      bind(site, "production", "www.acme.test", true)
      assert_received {:looked_up, "www.acme.test"}
      flush_lookups()

      pid = Process.whereis(ServedHosts)
      %{tick: stale} = :sys.get_state(pid)
      # A later check replaces the timer, and its lookup answers
      ServedHosts.registry_changed()
      ServedHosts.settled()
      assert_received {:looked_up, "www.acme.test"}
      assert %{tick: current} = :sys.get_state(pid)
      assert current != stale

      # The replaced timer's tick, fired before it was cancelled
      send(pid, {:tick, stale})
      :sys.get_state(pid)
      ServedHosts.settled()

      refute_received {:looked_up, _host}
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

    test "turning the feature off stops the lookups under way: nothing is written or broadcast",
         %{path: file, site: site} do
      DNS.answer("www.acme.test", [@here])
      DNS.hold("www.acme.test", self())

      {:ok, _} =
        Registry.create_environment(site, %{name: "production", key: "production", domain: "www.acme.test"},
          actor: :system
        )

      assert_receive {:looking_up, "www.acme.test", lookup}
      put_test_env(ServedHosts, [])
      Phoenix.PubSub.subscribe(Brando.pubsub(), ServedHosts.topic())
      send(lookup, :answer)
      ServedHosts.settled()

      refute_received {:served_hosts, _status}
      assert File.read!(file) == ""
    end

    test "a new file path drops the lookups under way, and the old file is left alone",
         %{path: file, tmp_dir: tmp_dir, site: site} do
      DNS.answer("www.acme.test", [@here])
      DNS.hold("www.acme.test", self())

      {:ok, _} =
        Registry.create_environment(site, %{name: "production", key: "production", domain: "www.acme.test"},
          actor: :system
        )

      assert_receive {:looking_up, "www.acme.test", lookup}
      new_file = Path.join(tmp_dir, "other_hosts")
      put_test_env(ServedHosts, file: new_file, addresses: [@here, @here_v6])
      send(lookup, :answer)

      # A check of the new file looks the host up again
      assert_receive {:looking_up, "www.acme.test", lookup}
      send(lookup, :answer)
      assert %{file: ^new_file, hosts: %{"www.acme.test" => :served}} = ServedHosts.settled()
      assert File.read!(file) == ""
      assert File.read!(new_file) == "www.acme.test\n"
    end

    test "a check of a new file admits a host the old file held again", %{path: file, tmp_dir: tmp_dir, site: site} do
      DNS.answer("a.acme.test", [@here])
      bind(site, "a", "a.acme.test")
      assert lines(file) == ["a.acme.test"]

      # A new server, whose addresses differ
      new_file = Path.join(tmp_dir, "other_hosts")
      put_test_env(ServedHosts, file: new_file, addresses: [@elsewhere])

      assert %{file: ^new_file, hosts: %{"a.acme.test" => {:waiting, [@here]}}} = ServedHosts.check()
      assert File.read!(new_file) == ""
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
