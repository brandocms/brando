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

  When Vite for `assets/backend` (the admin) or `assets/frontend` (the site)
  fails before it is ready, `watch/1` also records why, for `start_failure/1`.
  `Brando.HTML.include_assets/1` reads that record: rather than point the page
  at a port that another site's Vite may hold, it renders the built assets and
  a notice. A later start that gets as far as Vite's "ready" line clears it.
  Without a `Brando.Vite` watcher, as when the developer runs `pnpm dev`,
  nothing is ever recorded.
  """

  require Logger

  @vite_bin "node_modules/vite/bin/vite.js"
  @stop_timeout 3_000
  @tail_bytes 4_096

  @type role :: :admin | :site

  @typedoc """
  Why Vite did not start: the port Vite found in use, another exit status
  before Vite was ready, or a check that failed before Vite ran (the message
  says what to do).
  """
  @type failure :: %{
          dir: String.t(),
          reason: {:port_in_use, String.t()} | {:exited, integer()} | {:not_started, String.t()}
        }

  # Phoenix stops a command watcher by closing its standard input, and the VM
  # does the same when it exits without shutting down. Vite never reads its
  # standard input, so it would outlive both. This wrapper starts a watcher on
  # its standard input (the port), then replaces itself with the command, run
  # with standard input from /dev/null. The command keeps the wrapper's process
  # ID, so a SIGTERM to the port's OS process reaches it directly, and the
  # watcher sends it one when the port's standard input reaches end of file.
  #
  # The wrapper forwards no signals: a shell that traps SIGTERM and forks the
  # command loses a SIGTERM sent to the child between its fork and its exec.
  # The watcher's output goes to /dev/null so that it does not hold the port
  # open after the command exits.
  @wrapper ~S"""
  exec 3<&0 0</dev/null
  { while read -r _ <&3; do :; done; kill -TERM $$; } >/dev/null 2>&1 &
  exec "$@" 3<&-
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
      {:error, message} ->
        [_, detail] = String.split(message, "did not start: ", parts: 2)
        record_failure(server, {:not_started, detail})
        Logger.error(message)
    end

    :ok
  end

  @doc """
  Returns why the last `watch/1` for the admin's or the site's assets
  directory could not start Vite in this VM, or `nil` when it started, is
  starting, or never ran.
  """
  @spec start_failure(role()) :: failure() | nil
  def start_failure(role) when role in [:admin, :site], do: :persistent_term.get(failure_key(role), nil)

  defp record_failure(%{role: nil}, _reason), do: :ok

  defp record_failure(%{role: role, dir: dir}, reason),
    do: :persistent_term.put(failure_key(role), %{dir: dir, reason: reason})

  # Erasing a persistent term makes every process scan its heap, so only when
  # there is one
  defp clear_failure(%{role: nil}), do: :ok

  defp clear_failure(%{role: role}) do
    if start_failure(role), do: :persistent_term.erase(failure_key(role))
    :ok
  end

  defp failure_key(role), do: {__MODULE__, :start_failure, role}

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

    loop(port, os_pid, Map.put(server, :ready?, false), "", "")
  end

  defp loop(port, os_pid, server, tail, pending) do
    receive do
      {^port, {:data, data}} ->
        pending = write_output(pending <> data)
        tail = keep_tail(tail <> data)
        loop(port, os_pid, check_ready(server, tail), tail, pending)

      {^port, {:exit_status, status}} ->
        flush_output(pending)
        exited(status, server, tail)

      {:EXIT, ^port, _reason} ->
        loop(port, os_pid, server, tail, pending)

      {:EXIT, _from, reason} ->
        flush_output(pending)
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

  # The console takes only whole UTF-8 characters, and a chunk from the port
  # can end inside one. Writes the whole characters, replaces invalid bytes,
  # and returns an incomplete character at the end for the next chunk.
  defp write_output(data) do
    case :unicode.characters_to_binary(data) do
      text when is_binary(text) ->
        IO.write(text)
        ""

      {:incomplete, text, rest} ->
        IO.write(text)
        rest

      {:error, text, <<_invalid, rest::binary>>} ->
        IO.write(text <> "\uFFFD")
        write_output(rest)
    end
  end

  defp flush_output(""), do: :ok
  defp flush_output(pending), do: IO.write(String.replace_invalid(pending))

  defp keep_tail(tail) when byte_size(tail) > @tail_bytes,
    do: binary_part(tail, byte_size(tail) - @tail_bytes, @tail_bytes)

  defp keep_tail(tail), do: tail

  # Vite prints "VITE v7.1.0  ready in 312 ms" once it listens on its port,
  # perhaps with colour codes between the words. Its error for a taken port,
  # "Port 3333 is already in use", has "ready in" too.
  defp check_ready(%{ready?: false} = server, tail) do
    if Regex.match?(~r/VITE.*ready in /, tail) do
      clear_failure(server)
      %{server | ready?: true}
    else
      server
    end
  end

  defp check_ready(server, _tail), do: server

  defp exited(0, _server, _tail), do: :ok

  # 128 + SIGINT or SIGTERM: stopped from outside, as Ctrl-C does
  defp exited(status, server, _tail) when status in [130, 143] do
    Logger.info("The Vite dev server in #{server.dir} was stopped")
  end

  defp exited(status, server, tail) do
    port_in_use = Regex.run(~r/Port (\d+) is already in use/, tail)

    unless server.ready? do
      reason = if port_in_use, do: {:port_in_use, Enum.at(port_in_use, 1)}, else: {:exited, status}
      record_failure(server, reason)
    end

    message =
      case port_in_use do
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
      "backend" -> %{label: "the admin", dir: relative, role: :admin}
      "frontend" -> %{label: "the site", dir: relative, role: :site}
      _ -> %{label: "the dev server", dir: relative, role: nil}
    end
  end
end
