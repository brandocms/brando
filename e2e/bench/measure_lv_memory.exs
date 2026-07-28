# Reports BEAM memory for an open block-editor session on the running e2e node.
#
#   elixir --sname measure --cookie benchcookie measure_lv_memory.exs
#
# LiveComponents are NOT separate processes — every Block/RenderVar component's
# assigns live on the parent LiveView process heap, so this is the number that
# bounds how many concurrent editors a server can hold.
#
# Reports memory before and after a forced GC. The post-GC figure is the honest
# one: right after a big render the heap is full of garbage that would be
# collected anyway.

{:ok, host} = :inet.gethostname()
target = :"brandobench@#{host}"

unless Node.connect(target) do
  IO.puts("could not connect to #{target}")
  System.halt(1)
end

Process.sleep(300)

mem = fn pid ->
  case :erpc.call(target, :erlang, :process_info, [pid, :memory]) do
    {:memory, m} -> Float.round(m / 1024, 1)
    _ -> nil
  end
end

pids = :erpc.call(target, Process, :list, [])

tagged =
  for pid <- pids,
      info = :erpc.call(target, :erlang, :process_info, [pid, [:memory, :dictionary]]),
      info != :undefined do
    initial = info |> Keyword.get(:dictionary, []) |> Keyword.get(:"$initial_call")

    kind =
      case initial do
        {mod, :mount, 3} -> {:liveview, mod}
        {Bandit.DelegatingHandler, :init, 1} -> {:socket, Bandit.DelegatingHandler}
        _ -> nil
      end

    {pid, kind, Float.round(Keyword.fetch!(info, :memory) / 1024, 1)}
  end
  |> Enum.reject(fn {_, kind, _} -> is_nil(kind) end)
  |> Enum.sort_by(fn {_, _, kb} -> kb end, :desc)

form_lv =
  Enum.find(tagged, fn {_, kind, _} ->
    match?({:liveview, mod} when mod in [BrandoAdmin.Pages.PageFormLive], kind)
  end)

sockets = Enum.filter(tagged, fn {_, kind, _} -> match?({:socket, _}, kind) end)

if is_nil(form_lv) do
  IO.puts("no PageFormLive process found — is the editor open?")
  System.halt(1)
end

{lv_pid, _, lv_before} = form_lv
{sock_pid, _, sock_before} = List.first(sockets) || {nil, nil, 0.0}

# Force collection so we report retained state, not render garbage.
#
# A SINGLE garbage_collect/1 is not enough and will overstate retention badly —
# measured on a 115-block editor: 11.3 MB, then 6.5 MB, then 4.3 MB on
# successive calls, settling only on the third. Reporting the first reading as
# "post-GC" once made this benchmark claim a 2.6x memory regression that did not
# exist. So collect until two consecutive readings agree within 2%.
collect_until_settled = fn pid ->
  Enum.reduce_while(1..8, nil, fn _, previous ->
    :erpc.call(target, :erlang, :garbage_collect, [pid])
    Process.sleep(300)
    current = mem.(pid)

    settled? = previous && (previous == 0.0 or abs(current - previous) / previous < 0.02)
    if settled?, do: {:halt, current}, else: {:cont, current}
  end)
end

lv_after = collect_until_settled.(lv_pid)
sock_after = if sock_pid, do: collect_until_settled.(sock_pid), else: 0.0

IO.puts("\n=== block editor session memory (#{target}) ===")
IO.puts("  PageFormLive     #{lv_before} KB  ->  #{lv_after} KB after GC")
IO.puts("  socket handler   #{sock_before} KB  ->  #{sock_after} KB after GC")
IO.puts("  session total (post-GC): #{Float.round(lv_after + sock_after, 1)} KB")

IO.puts("MEASURE_RESULT lv_pre=#{lv_before} lv_post=#{lv_after} sock_pre=#{sock_before} sock_post=#{sock_after}")
