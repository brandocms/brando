# Profiles the server time an editor operation costs, inside the LiveView process.
#
#   elixir --sname profile --cookie benchcookie profile_op.exs
#
# Phase 3 of the block editor plan is latency, not payload: insert is 79 KB but
# takes over a second at 115 blocks, and opening the outline drawer is 45 KB but
# a full second of server work. Neither is visible from the websocket, so both
# have to be measured from inside the BEAM — same reason as
# `measure_lv_memory.exs`.
#
# Coordination with the browser runs through flag files, because the operation
# has to be driven from a real client (it is a `phx-click` on a rendered block)
# while the profiler is already attached:
#
#   1. the spec opens the entry and writes  READY
#   2. this script attaches :eprof and writes  GO
#   3. the spec performs the operation and writes  DONE
#   4. this script detaches and reports
#
# Run `bench/profile-op.spec.js` (BENCH_OP=insert|outline|copy) alongside it.
# The server must be a named node:
#
#   MIX_ENV=e2e PORT=4444 elixir --sname brandobench --cookie benchcookie -S mix phx.server

flag_dir = Path.expand("../e2e/playwright/bench", __DIR__)
ready = Path.join(flag_dir, "op-ready.flag")
go = Path.join(flag_dir, "op-go.flag")
done = Path.join(flag_dir, "op-done.flag")

for f <- [ready, go, done], do: File.rm(f)

{:ok, host} = :inet.gethostname()
target = :"brandobench@#{host}"

unless Node.connect(target) do
  IO.puts("could not connect to #{target} — start the server with --sname brandobench")
  System.halt(1)
end

Process.sleep(300)

wait_for = fn path, timeout_ms, label ->
  deadline = System.monotonic_time(:millisecond) + timeout_ms

  Enum.reduce_while(Stream.cycle([:tick]), nil, fn _, _ ->
    cond do
      File.exists?(path) -> {:halt, :ok}
      System.monotonic_time(:millisecond) > deadline -> {:halt, {:timeout, label}}
      true -> Process.sleep(100) && {:cont, nil}
    end
  end)
end

find_lv = fn ->
  pids = :erpc.call(target, Process, :list, [])

  Enum.find(pids, fn pid ->
    case :erpc.call(target, :erlang, :process_info, [pid, :dictionary]) do
      {:dictionary, dict} ->
        match?({BrandoAdmin.Pages.PageFormLive, :mount, 3}, Keyword.get(dict, :"$initial_call"))

      _ ->
        false
    end
  end)
end

IO.puts("waiting for the editor to open...")

case wait_for.(ready, 180_000, "READY") do
  :ok -> :ok
  {:timeout, label} -> IO.puts("timed out waiting for #{label}") && System.halt(1)
end

lv_pid = find_lv.()

if is_nil(lv_pid) do
  IO.puts("no PageFormLive process found — is the editor open?")
  System.halt(1)
end

# `:eprof` lives in OTP's `tools` app, which a Mix project does not put on the
# code path — the module is simply `:undef` on the server node. Add its ebin
# from the node's own OTP root so the version always matches.
root = to_string(:erpc.call(target, :code, :root_dir, []))

case Path.wildcard(Path.join([root, "lib", "tools-*", "ebin"])) do
  [] ->
    IO.puts("no tools-*/ebin under #{root} — cannot load :eprof")
    System.halt(1)

  [ebin | _] ->
    :erpc.call(target, :code, :add_patha, [to_charlist(ebin)])
end

IO.puts("attaching :eprof to #{inspect(lv_pid)}")
:erpc.call(target, :eprof, :start, [])
:erpc.call(target, :eprof, :start_profiling, [[lv_pid]])

File.write!(go, "go")

case wait_for.(done, 180_000, "DONE") do
  :ok -> :ok
  {:timeout, label} -> IO.puts("timed out waiting for #{label}")
end

:erpc.call(target, :eprof, :stop_profiling, [])

op = System.get_env("BENCH_OP", "op")
entry = System.get_env("BENCH_ENTRY", "115")
report = Path.join(flag_dir, "profile-#{op}-#{entry}.txt")

# `:eprof.analyze/2` prints through the *remote* node's group leader, so its
# table would land in the server's stdout rather than here. `:eprof.log/1`
# redirects it to a file instead — same machine, so it can just be read back.
:erpc.call(target, :eprof, :log, [to_charlist(report)])
:erpc.call(target, :eprof, :analyze, [:total, [{:sort, :time}, {:filter, [{:calls, 20}]}]])
:erpc.call(target, :eprof, :stop, [])

IO.puts("\n=== eprof: #{op} @ #{entry} — #{report} ===")

case File.read(report) do
  {:ok, contents} -> IO.puts(contents)
  {:error, reason} -> IO.puts("could not read report: #{inspect(reason)}")
end

for f <- [ready, go, done], do: File.rm(f)
