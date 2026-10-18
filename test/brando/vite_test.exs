defmodule Brando.ViteTest do
  # Changes PATH, which the watcher reads to find node
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    path = System.get_env("PATH")
    on_exit(fn -> System.put_env("PATH", path) end)

    # A `node` that runs the "Vite" script it is given with sh, so each test
    # says what Vite does in node_modules/vite/bin/vite.js
    bin = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin)
    File.write!(Path.join(bin, "node"), "#!/bin/sh\nexec /bin/sh \"$@\"\n")
    File.chmod!(Path.join(bin, "node"), 0o755)
    System.put_env("PATH", bin <> ":" <> path)

    # A failure recorded here would make Brando.HTML render built assets in later tests
    clear_start_failures()
    on_exit(&clear_start_failures/0)

    %{backend: Path.join(tmp_dir, "assets/backend")}
  end

  defp clear_start_failures do
    for role <- [:admin, :site], do: :persistent_term.erase({Brando.Vite, :start_failure, role})
  end

  defp fake_vite(dir, script) do
    vite = Path.join(dir, "node_modules/vite/bin/vite.js")
    File.mkdir_p!(Path.dirname(vite))
    File.write!(vite, script)
  end

  # The watcher as Phoenix runs it: a :transient child of the endpoint's supervisor
  defp start_watcher(dir) do
    watcher = {Phoenix.Endpoint.Watcher, {:vite_admin, {Brando.Vite, :watch, [dir]}}}

    start_supervised!(%{
      id: :endpoint,
      start: {Supervisor, :start_link, [[watcher], [strategy: :one_for_one]]},
      type: :supervisor
    })
  end

  defp watcher_pid(supervisor) do
    [{_, pid, :worker, _}] = Supervisor.which_children(supervisor)
    pid
  end

  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() -> true
      attempts == 0 -> flunk("condition not met in time")
      true -> Process.sleep(50) && eventually(fun, attempts - 1)
    end
  end

  defp os_alive?(pid), do: match?({_, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))

  defp read_pid(dir) do
    pid_file = Path.join(dir, "vite.pid")
    eventually(fn -> File.exists?(pid_file) and File.read!(pid_file) =~ "\n" end)
    pid_file |> File.read!() |> String.trim()
  end

  test "without node_modules, logs once what to run and returns", %{backend: backend} do
    File.mkdir_p!(backend)

    log = capture_log(fn -> assert Brando.Vite.watch(backend) == :ok end)

    assert log =~ "Vite for the admin did not start"
    assert log =~ "node_modules/vite/bin/vite.js"
    assert log =~ "mix brando.assets.setup"
    assert length(String.split(log, "[error]")) == 2
  end

  test "a directory that does not exist is named", %{tmp_dir: tmp_dir} do
    log = capture_log(fn -> assert Brando.Vite.watch(Path.join(tmp_dir, "assets/frontend")) == :ok end)

    assert log =~ "Vite for the site did not start"
    assert log =~ "assets/frontend does not exist"
  end

  test "without node on the PATH, says so", %{backend: backend, tmp_dir: tmp_dir} do
    fake_vite(backend, "exit 0\n")
    File.mkdir_p!(Path.join(tmp_dir, "empty"))
    System.put_env("PATH", Path.join(tmp_dir, "empty"))

    log = capture_log(fn -> assert Brando.Vite.watch(backend) == :ok end)

    assert log =~ "node is not on the PATH"
  end

  test "a taken port is logged once, naming the port variables, and Phoenix does not restart the watcher",
       %{backend: backend} do
    fake_vite(backend, """
    echo started >> runs
    echo "error when starting dev server:"
    echo "Error: Port 4999 is already in use" >&2
    exit 1
    """)

    output =
      capture_io(fn ->
        log =
          capture_log(fn ->
            supervisor = start_watcher(backend)
            eventually(fn -> watcher_pid(supervisor) == :undefined end)
            Process.sleep(300)
            assert watcher_pid(supervisor) == :undefined
          end)

        assert [_, error] = String.split(log, "[error]")
        assert error =~ "Vite for the admin"
        assert error =~ "port 4999 is already in use"
        assert error =~ "BRANDO_VITE_ADMIN_PORT and BRANDO_VITE_FRONTEND_PORT"
      end)

    assert output =~ "Error: Port 4999 is already in use"
    assert File.read!(Path.join(backend, "runs")) == "started\n"
  end

  test "any other failure is logged once, and points at the output", %{backend: backend} do
    fake_vite(backend, "echo 'Cannot find package vite'\nexit 3\n")

    capture_io(fn ->
      log = capture_log(fn -> assert Brando.Vite.watch(backend) == :ok end)
      assert [_, error] = String.split(log, "[error]")
      assert error =~ "exited with status 3; its output is above"
    end)
  end

  test "stopping the endpoint stops Vite before the watcher exits", %{backend: backend} do
    fake_vite(backend, "echo $$ > vite.pid\nexec sleep 300\n")

    log =
      capture_log(fn ->
        supervisor = start_watcher(backend)
        os_pid = read_pid(backend)
        assert os_alive?(os_pid)

        # Gone before the watcher exits, so a restarted endpoint finds its port free
        {microseconds, :ok} = :timer.tc(fn -> stop_supervised!(:endpoint) end)
        refute Process.alive?(supervisor)
        refute os_alive?(os_pid)
        assert microseconds < 2_000_000
      end)

    refute log =~ "[error]"
  end

  test "a character split across writes reaches the console whole", %{backend: backend} do
    # ➜ is E2 9E 9C, and an incomplete character at exit is replaced
    fake_vite(backend, """
    printf '\\342\\236'
    sleep 0.2
    printf '\\234 ready\\n'
    sleep 0.2
    printf 'end \\342'
    """)

    output = capture_io(fn -> assert Brando.Vite.watch(backend) == :ok end)

    assert output == "➜ ready\nend �"
  end

  test "a SIGTERM while the wrapper starts leaves no Vite behind", %{tmp_dir: tmp_dir} do
    for n <- 0..29 do
      delay = Enum.at([0, 1, 2, 3, 5, 8], rem(n, 6))
      dir = Path.join(tmp_dir, "run#{n}")
      File.mkdir_p!(dir)
      test = self()

      watcher =
        spawn(fn ->
          capture_log(fn -> Brando.Vite.run(dir, "/bin/sh", ["-c", "echo $$ > vite.pid; exec sleep 300"]) end)
          send(test, {:returned, self()})
        end)

      os_pid = wrapper_os_pid(watcher)
      Process.sleep(delay)
      System.cmd("kill", ["-TERM", Integer.to_string(os_pid)], stderr_to_stdout: true)
      assert_receive {:returned, ^watcher}, 5_000

      # A command that outlived the wrapper could still be writing its pid
      Process.sleep(100)
      pid_file = Path.join(dir, "vite.pid")

      if File.exists?(pid_file) do
        os_pid = pid_file |> File.read!() |> String.trim()
        if os_pid != "", do: eventually(fn -> not os_alive?(os_pid) end, 20)
      end
    end
  end

  # Another process can see the port while Port.open/2 is still starting it,
  # with an OS pid of 0
  defp wrapper_os_pid(watcher) do
    port = Enum.find(Port.list(), &(Port.info(&1, :connected) == {:connected, watcher}))

    case port && Port.info(port, :os_pid) do
      {:os_pid, os_pid} when os_pid > 0 -> os_pid
      _ -> Process.sleep(1) && wrapper_os_pid(watcher)
    end
  end

  describe "the record of a Vite that did not start" do
    test "names the taken port, for the admin's directory", %{backend: backend} do
      fake_vite(backend, "echo 'Error: Port 4999 is already in use' >&2\nexit 1\n")

      capture_io(fn -> capture_log(fn -> Brando.Vite.watch(backend) end) end)

      assert %{reason: {:port_in_use, "4999"}, dir: dir} = Brando.Vite.start_failure(:admin)
      assert String.ends_with?(dir, "assets/backend")
      assert Brando.Vite.start_failure(:site) == nil
    end

    test "keeps what to do when a check fails before Vite runs", %{tmp_dir: tmp_dir} do
      frontend = Path.join(tmp_dir, "assets/frontend")
      File.mkdir_p!(frontend)

      capture_log(fn -> Brando.Vite.watch(frontend) end)

      assert %{reason: {:not_started, detail}} = Brando.Vite.start_failure(:site)
      assert detail =~ "has no node_modules/vite/bin/vite.js. Run mix brando.assets.setup"
      assert Brando.Vite.start_failure(:admin) == nil
    end

    test "keeps the exit status of any other failure before Vite is ready", %{backend: backend} do
      fake_vite(backend, "echo 'Cannot find package vite'\nexit 3\n")

      capture_io(fn -> capture_log(fn -> Brando.Vite.watch(backend) end) end)

      assert %{reason: {:exited, 3}} = Brando.Vite.start_failure(:admin)
    end

    test "is cleared once a later start is ready, and an exit after that records nothing",
         %{backend: backend} do
      fake_vite(backend, "echo 'Error: Port 4999 is already in use' >&2\nexit 1\n")
      capture_io(fn -> capture_log(fn -> Brando.Vite.watch(backend) end) end)
      assert Brando.Vite.start_failure(:admin)

      fake_vite(backend, """
      echo '  VITE v7.1.0  ready in 312 ms'
      while [ ! -f stop ]; do sleep 0.05; done
      exit 1
      """)

      # In a process of its own: the watcher traps exits
      {watcher, ref} =
        spawn_monitor(fn -> capture_io(fn -> capture_log(fn -> Brando.Vite.watch(backend) end) end) end)

      eventually(fn -> Brando.Vite.start_failure(:admin) == nil end)
      File.write!(Path.join(backend, "stop"), "")
      assert_receive {:DOWN, ^ref, :process, ^watcher, :normal}, 5_000

      assert Brando.Vite.start_failure(:admin) == nil
    end

    test "is not kept for a directory that is neither the admin's nor the site's", %{tmp_dir: tmp_dir} do
      capture_log(fn -> Brando.Vite.watch(Path.join(tmp_dir, "assets/other")) end)

      assert Brando.Vite.start_failure(:admin) == nil
      assert Brando.Vite.start_failure(:site) == nil
    end
  end

  test "Vite stops when the watcher dies without shutting down, as when the VM exits",
       %{backend: backend} do
    fake_vite(backend, "echo $$ > vite.pid\nexec sleep 300\n")

    {watcher, ref} = spawn_monitor(fn -> Brando.Vite.watch(backend) end)
    os_pid = read_pid(backend)
    assert os_alive?(os_pid)

    Process.exit(watcher, :kill)
    assert_receive {:DOWN, ^ref, :process, ^watcher, :killed}
    eventually(fn -> not os_alive?(os_pid) end)
  end
end
