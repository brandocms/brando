defmodule Brando.Vite do
  @moduledoc """
  Runs a Vite dev server as a Phoenix endpoint watcher, for `hmr: true` in
  development.

      config :studio, StudioWeb.Endpoint,
        watchers: [
          vite_admin: {Brando.Vite, :watch, [Path.expand("../assets/backend", __DIR__)]},
          vite_site: {Brando.Vite, :watch, [Path.expand("../assets/frontend", __DIR__)]}
        ]

  `watch/1` runs `node node_modules/vite/bin/vite.js` in the directory and
  streams its output to the console. Vite stops when the watcher does: when
  Phoenix shuts down or restarts the endpoint, and when the VM exits without
  shutting down (Ctrl-C, then `a`).

  Vite reads its port from `BRANDO_VITE_ADMIN_PORT` (`assets/backend`) and
  `BRANDO_VITE_FRONTEND_PORT` (`assets/frontend`), which it inherits from
  Phoenix's environment, as `Brando.HTML` does.

  When Vite cannot start, or exits with an error, `watch/1` logs one error
  saying what to do and returns. Phoenix does not restart a watcher that
  returns, so the endpoint keeps running without that dev server.
  """

  require Logger

  @vite_bin "node_modules/vite/bin/vite.js"
  @stop_timeout 3_000
  @tail_bytes 4_096

  # Phoenix stops a command watcher by closing its standard input, and the VM
  # does the same when it exits without shutting down. Vite never reads its
  # standard input, so it would outlive both. This wrapper runs the command
  # with standard input from /dev/null, stops it when its own standard input
  # (the port) reaches end of file, forwards SIGTERM to it, and exits with its
  # status.
  @wrapper ~S"""
  exec 3<&0 0</dev/null
  "$@" 3<&- &
  child=$!
  trap 'kill -TERM "$child" 2>/dev/null' TERM INT HUP
  { while read -r _ <&3; do :; done; kill -TERM "$child" 2>/dev/null; } &
  stdin_watcher=$!
  exec 3<&-
  status=0
  wait "$child" || status=$?
  while kill -0 "$child" 2>/dev/null; do
    status=0
    wait "$child" || status=$?
  done
  kill "$stdin_watcher" 2>/dev/null
  exit "$status"
  """

  @doc """
  Runs Vite in `dir` until it exits or the calling watcher process stops.

  Always returns `:ok`. A failure to start, or an exit with an error, is
  logged once.
  """
  @spec watch(Path.t()) :: :ok
  def watch(dir) when is_binary(dir) do
    server = server(dir)

    with :ok <- check_dir(dir, server),
         :ok <- check_vite(dir, server),
         {:ok, node} <- find_node(server) do
      run(dir, node, [@vite_bin], server)
    else
      {:error, message} -> Logger.error(message)
    end

    :ok
  end

  @doc false
  # Runs `executable` with `args` in `dir` through the wrapper above. Used by
  # `watch/1`, and by tests with a stand-in for Vite.
  def run(dir, executable, args, server \\ nil) do
    server = server || server(dir)
    Process.flag(:trap_exit, true)

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        cd: dir,
        args: ["-c", @wrapper, "brando-vite", executable | args]
      ])

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, os_pid} -> os_pid
        nil -> nil
      end

    loop(port, os_pid, server, "")
  end

  defp loop(port, os_pid, server, tail) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        loop(port, os_pid, server, keep_tail(tail <> data))

      {^port, {:exit_status, status}} ->
        exited(status, server, tail)

      {:EXIT, ^port, _reason} ->
        loop(port, os_pid, server, tail)

      {:EXIT, _from, reason} ->
        stop(port, os_pid)
        # Phoenix's watcher catches an exit raised here and sleeps 2 s before
        # passing it on, which holds up the endpoint's shutdown. An exit
        # signal to itself ends the process at once.
        Process.flag(:trap_exit, false)
        Process.exit(self(), reason)
        exit(reason)
    end
  end

  defp stop(port, os_pid) do
    if os_pid, do: System.cmd("kill", ["-TERM", Integer.to_string(os_pid)], stderr_to_stdout: true)

    receive do
      {^port, {:exit_status, _}} -> :ok
    after
      @stop_timeout ->
        # Closing the port ends the wrapper's standard input, which stops Vite
        if Port.info(port), do: Port.close(port)
    end
  end

  defp keep_tail(tail) when byte_size(tail) > @tail_bytes,
    do: binary_part(tail, byte_size(tail) - @tail_bytes, @tail_bytes)

  defp keep_tail(tail), do: tail

  defp exited(0, _server, _tail), do: :ok

  # 128 + SIGINT or SIGTERM: stopped from outside, as Ctrl-C does
  defp exited(status, server, _tail) when status in [130, 143] do
    Logger.info("The Vite dev server in #{server.dir} was stopped")
  end

  defp exited(status, server, tail) do
    message =
      case Regex.run(~r/Port (\d+) is already in use/, tail) do
        [_, port] ->
          "Vite for #{server.label} (#{server.dir}) did not start: port #{port} is already in use, " <>
            "perhaps by another site's Vite. Stop that process, or give this site other ports with " <>
            "BRANDO_VITE_ADMIN_PORT and BRANDO_VITE_FRONTEND_PORT, exported where both Phoenix and Vite " <>
            "read them, for example in .envrc."

        nil ->
          "Vite for #{server.label} (#{server.dir}) exited with status #{status}; its output is above. " <>
            "If it could not load its dependencies, run mix brando.assets.setup."
      end

    Logger.error(message)
  end

  defp check_dir(dir, server) do
    if File.dir?(dir),
      do: :ok,
      else: {:error, "Vite for #{server.label} did not start: #{server.dir} does not exist."}
  end

  defp check_vite(dir, server) do
    if File.regular?(Path.join(dir, @vite_bin)) do
      :ok
    else
      {:error,
       "Vite for #{server.label} did not start: #{server.dir} has no #{@vite_bin}. " <>
         "Run mix brando.assets.setup (or pnpm install in #{server.dir}), then restart the server."}
    end
  end

  defp find_node(server) do
    case System.find_executable("node") do
      nil ->
        {:error,
         "Vite for #{server.label} (#{server.dir}) did not start: node is not on the PATH. " <>
           "Install Node.js, then restart the server."}

      node ->
        {:ok, node}
    end
  end

  defp server(dir) do
    relative = Path.relative_to_cwd(dir)

    case Path.basename(dir) do
      "backend" -> %{label: "the admin", dir: relative}
      "frontend" -> %{label: "the site", dir: relative}
      _ -> %{label: "the dev server", dir: relative}
    end
  end
end
