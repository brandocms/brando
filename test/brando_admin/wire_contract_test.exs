defmodule BrandoAdmin.WireContractTest do
  # The JS ↔ LiveView boundary is invisible to the compiler: a client
  # `pushEvent` with no `handle_event` crashes at runtime, and a server
  # `push_event` with no `handleEvent` listener silently does nothing.
  # This test inventories both sides from source and fails on drift —
  # the defect class behind several audit findings (unhandled
  # `upload_error`/`drop_svg`, the dead `files_selected`/`start_upload_queue`
  # protocol).
  #
  # Known blind spots (raw-text scan, by design):
  # - Client→server only covers JS-originated pushes; `JS.push`/`phx-click`
  #   events defined in HEEx templates are NOT inventoried (their handlers
  #   are colocated with the template, so drift there is far less likely).
  # - Event names appearing in comments or string literals count as live —
  #   a false positive fails loudly and is trivially resolved; there is no
  #   silent false-negative in that direction.
  use ExUnit.Case, async: true

  @js_glob "assets/src/**/*.js"
  @ex_globs ["lib/brando_admin/**/*.ex", "lib/brando/**/*.ex"]

  # Client-pushed events the server intentionally handles via a mechanism this
  # scanner can't see, or that are handled per-project. Keep this list SHORT
  # and justified — every entry is a hole in the contract check.
  @client_push_allowlist []

  # Server-pushed events consumed by something other than a hook handleEvent
  # (window listeners, JS.exec targets) or pushed only for optional hooks.
  @server_push_allowlist []

  test "every literal client pushEvent has a server handler" do
    client_events = collect_client_pushes()
    server_handlers = collect_server_handlers()

    missing =
      client_events
      |> Map.reject(fn {event, _} -> event in server_handlers or event in @client_push_allowlist end)

    assert missing == %{}, """
    Client events pushed with no matching server handle_event clause:

    #{format_missing(missing)}

    Either add a handler, delete the dead client push, or (only when the
    handler genuinely can't be detected) add the event to the allowlist in
    #{__ENV__.file} with a comment explaining where it is handled.
    """
  end

  test "every literal server push_event has a client handleEvent listener" do
    server_pushes = collect_server_pushes()
    client_listeners = collect_client_listeners()

    missing =
      server_pushes
      |> Map.reject(fn {event, _} -> event in client_listeners or event in @server_push_allowlist end)

    assert missing == %{}, """
    Server push_event calls with no matching client handleEvent listener:

    #{format_missing(missing)}

    Either add a listener, delete the dead server push, or (only when the
    listener genuinely can't be detected) add the event to the allowlist in
    #{__ENV__.file} with a comment explaining where it is consumed.
    """
  end

  defp collect_client_pushes do
    # pushEvent('name'…, pushEventTo(target, 'name'…, and wrappers ending in
    # Event/EventTo (e.g. pushVideoEvent). Skips dynamic names.
    scan_files([@js_glob], ~r/push\w*Event(?:To\((?:[^,()]|\([^)]*\))+,|\()\s*['"`]([^'"`$]+)['"`]/)
  end

  defp collect_server_handlers do
    # handle_event("name"… plus attach_hook-style dispatchers
    # (handle_block_event/3 and handle_hooks_video_event/3) that route raw events.
    scan_files(@ex_globs, ~r/defp?\s+handle_(?:event|block_event|hooks_\w+)\(\s*\n?\s*"([^"]+)"/)
    |> Map.keys()
    |> MapSet.new()
  end

  defp collect_server_pushes do
    # push_event(socket, "name"…) — skip interpolated names.
    scan_files(@ex_globs, ~r/push_event\(\s*[\w@.]*,?\s*"([^"#]+)"/)
  end

  defp collect_client_listeners do
    hook_listeners = scan_files([@js_glob], ~r/handleEvent\(\s*['"`]([^'"`$]+)['"`]/)

    # push_event also dispatches a `phx:<name>` window event — the other
    # sanctioned consumption channel (js-exec, component remounts, …).
    window_listeners = scan_files([@js_glob], ~r/addEventListener\(\s*['"`]phx:([^'"`$]+)['"`]/)

    (Map.keys(hook_listeners) ++ Map.keys(window_listeners))
    |> MapSet.new()
    |> then(fn set ->
      # b:validate:<dynamic-id> pushes are consumed by per-element listeners
      # registered as handleEvent(`b:validate:${id}`) — normalize the prefix.
      MapSet.put(set, "b:validate")
    end)
  end

  defp scan_files(globs, regex) do
    globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&String.contains?(&1, "/node_modules/"))
    |> Enum.reduce(%{}, fn file, acc ->
      content = File.read!(file)

      regex
      |> Regex.scan(content, capture: :all_but_first)
      |> List.flatten()
      |> Enum.reject(&(&1 =~ ~r/[#$]\{/))
      |> Enum.reduce(acc, fn event, inner ->
        Map.update(inner, event, [file], &[file | &1])
      end)
    end)
  end

  defp format_missing(missing) do
    Enum.map_join(missing, "\n", fn {event, files} ->
      "  #{inspect(event)} — pushed from #{Enum.uniq(files) |> Enum.join(", ")}"
    end)
  end
end
