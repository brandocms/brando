defmodule Brando.LiveCase do
  @moduledoc """
  Test case for tests that mount a real admin LiveView with
  `Phoenix.LiveViewTest.live/2`.

  This is the harness the form audit's Phase 4 asked for. Before it there were
  zero mounted-LiveView tests in the suite — every form test drove components
  through `update/2` and `handle_event/3` directly, which cannot observe the
  parts of a form that only exist once a LiveView process is alive: reconnect
  and recovery, `push_event` payloads, and what survives the process dying.

  Three pieces have to line up for `live/2` to work here, and all three are set
  up outside this module:

    * `BrandoIntegrationWeb.Endpoint` plugs `BrandoIntegrationWeb.Router`
      (`test/test_helper.exs`)
    * the endpoint carries a `:live_view` signing salt (`config/test.exs`)
    * the admin routes sit behind `{BrandoAdmin.UserAuth, :ensure_authenticated}`,
      so the conn needs a logged-in user — `setup` below does that.

  The sandbox is shared (`Brando.ConnCase.setup_sandbox/1` passes
  `shared: not async`), which is what lets the LiveView process — a different
  process from the test — see the test's data. **These tests must not be
  `async: true`.**

  ## Killing the LiveView

  `kill_live/1` takes a view down the way a deploy or a crash would, and waits
  for the exit rather than sleeping on it. Use it with
  `Phoenix.LiveViewTest.live/2` again to model a reconnect: LiveView's own form
  recovery replays the DOM params against a changeset freshly loaded from the
  database, so anything the editor held only in changeset `changes` or in
  component assigns is gone by design. That distinction is the whole subject of
  the form audit, and this is the harness that can actually assert it.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Brando.LiveCase
      # Extracted to the toolkit projects use; `use Brando.Test` imports the rest.
      import Brando.Test, only: [log_in_user: 2, await_selector: 2, await_selector: 3]
      import Brando.Test.Support
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import RouterHelper

      alias Brando.Factory
      alias BrandoIntegration.Repo

      @endpoint BrandoIntegrationWeb.Endpoint
    end
  end

  setup tags do
    Brando.ConnCase.setup_sandbox(tags)
    # Runs before the sandbox owner stops (on_exit callbacks run last-first)
    ExUnit.Callbacks.on_exit(&await_presence_idle/0)

    # `config` has to be present: `UserAuth.log_in_user/3` reads
    # `user.config.content_language` on the way in, and the factory leaves the
    # embed nil.
    user =
      Brando.Factory.insert(:random_user,
        role: :superuser,
        config: %Brando.Users.UserConfig{}
      )

    {:ok, conn: Brando.Test.log_in_user(Phoenix.ConnTest.build_conn(), user), current_user: user}
  end

  @doc """
  Waits, up to a second, until the presence tracker has no lookup running.

  A LiveView that closes with the test leaves presence, and presence looks
  the user up in the database in a task. Should that task still run when the
  test's sandbox owner stops, it dies on the closed connection, and
  `Phoenix.Presence` has no clause for a task that died: the tracker crashes,
  and the next test to mount an admin LiveView fails to track.
  """
  def await_presence_idle(deadline \\ System.monotonic_time(:millisecond) + 1_000) do
    shard = :"Elixir.BrandoIntegration.Presence_shard0"

    idle? =
      case Process.whereis(shard) do
        nil -> true
        pid -> match?(%{tracker_state: %{current_task: nil}}, :sys.get_state(pid))
      end

    cond do
      idle? and settled?(shard) -> :ok
      System.monotonic_time(:millisecond) > deadline -> :ok
      true -> await_presence_idle(deadline)
    end
  end

  # Idle twice, a moment apart: a leave may still be on its way
  defp settled?(shard) do
    Process.sleep(20)

    case Process.whereis(shard) do
      nil -> true
      pid -> match?(%{tracker_state: %{current_task: nil}}, :sys.get_state(pid))
    end
  end

  @doc """
  Kills a mounted LiveView the way a crash or a deploy would, and blocks until
  both the process and its client proxy are gone.

  Deliberately not `:normal` — a normal exit is not what the recovery path is
  written for, and it would let the caller assert against a process that is
  still shutting down.

  The proxy is awaited unconditionally, for **any** view. As of
  **phoenix_live_view 1.2.12**, `client_proxy.ex`'s `put_view/3` (`:846`)
  monitors every view it registers and keys them all in one `state.pids` map;
  children reach that same function through
  `recursive_detect_added_or_removed_children/4`; and the
  `handle_info({:DOWN, …}, state)` clause (`:542`) stops the proxy for any pid
  `fetch_view_by_pid/2` (`:909`) finds in that map. No root/child distinction
  exists anywhere on that path. A proxy that does not deliver its exit is a
  hang, and is flunked rather than waited out.

  Those citations are **function heads**, not interior lines, and deliberately
  so. A line number inside a function body moves the moment anything is
  inserted above it, whereas a head moves only when the function does. Every
  interior line this argument has cited has been wrong at least once — three of
  five were wrong simultaneously, including one introduced by the pass that was
  re-verifying them.

  There is no `:root | :child` role argument, because the runtime draws no such
  distinction — `put_view/3` treats every view alike, and killing a real sticky
  child stops the **root's** proxy. `form_recovery_test.exs`'s "killing a real
  child view stops the root's proxy" is what establishes that, against a live
  child rather than a stub, which is the only fixture that can settle it.

  The version is pinned so a dependency bump surfaces here as a prompt to
  re-read `client_proxy.ex`, rather than as prose nobody rechecks;
  `form_recovery_test.exs` asserts it. Be clear about what that buys:
  **the pin catches drift, not authorship.** A citation that is wrong the day
  it is written stays wrong at the pinned version, and the assertion passes the
  whole time. That is not hypothetical — it is how three of the five line
  numbers this block used to carry survived a pass whose entire job was
  re-verifying them. Treat the pin as a reason to re-read on a bump, never as
  evidence that anyone read correctly the first time.
  """
  def kill_live(view) do
    pid = view.pid
    {_ref, _topic, proxy_pid} = view.proxy
    ref = Process.monitor(pid)

    # `live/2` links the test process to the client proxy, which in turn dies
    # with the LiveView. Without trapping, killing the view kills the test.
    #
    # The flag is captured and restored rather than just set: leaving it on
    # changes how every *later* line in the same test process reacts to a
    # crash, so a test could pass against a LiveView that died on it. Capture
    # /restore composes across *repeated* calls — a second `kill_live/1` sees
    # `prior_trap?` as `true` and hands the flag back on.
    #
    # `after`, not a trailing line, because both waits below can `flunk` and a
    # flunk raises. A test that deliberately catches one would otherwise carry
    # on with the flag still set.
    prior_trap? = Process.flag(:trap_exit, true)

    try do
      Process.exit(pid, :kill)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        1_000 -> flunk("LiveView #{inspect(pid)} did not exit within 1s")
      end

      await_proxy_exit(proxy_pid)
      :ok
    after
      Process.flag(:trap_exit, prior_trap?)
    end
  end

  # Receives the exit of the one process `live/2` linked us to, and nothing
  # else. The pin on `proxy_pid` is the point: any other `{:EXIT, _, _}` stays
  # in the mailbox **deliberately**, because it belongs to the test and the
  # test should be able to see it. A blanket drain here would let a test carry
  # on past a crash it never observed.
  #
  # The kill stops the proxy (phoenix_live_view **1.2.12**, `client_proxy.ex`'s
  # `handle_info({:DOWN, …}, state)` clause at `:542`), so the exit is expected
  # and arrives in single-digit ms. Not arriving means the proxy is hung, which
  # is a failure.
  defp await_proxy_exit(proxy_pid) do
    receive do
      {:EXIT, ^proxy_pid, _reason} -> :ok
    after
      500 -> flunk("client proxy #{inspect(proxy_pid)} did not exit within 500ms")
    end
  end

  @doc """
  Clicks `element` `times` times back to back, as a quick double click that
  reaches the server before it has answered the first: the LiveView is
  suspended while the clicks are queued, so it handles them one after the
  other, ahead of anything the first one causes (a `send_update/2` to the
  form). The clicks carry what the element's `phx-click` push carries. Then
  waits for everything they caused, see `settle/1`.

  A plain `render_click/1` cannot do this: it waits for the reply, and by then
  the first click's `send_update/2` is ahead of the second click.
  """
  def queue_clicks(view, element, times \\ 2) do
    [push] =
      element
      |> Phoenix.LiveViewTest.render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("phx-click")

    [["push", %{"event" => event, "target" => cid} = push]] = Jason.decode!(push)
    value = Map.get(push, "value", %{})

    messages =
      for i <- 1..times do
        %Phoenix.Socket.Message{
          topic: "lv:" <> view.id,
          event: "event",
          ref: "queued-#{System.unique_integer([:positive])}-#{i}",
          payload: %{"type" => "click", "event" => event, "value" => value, "cid" => cid}
        }
      end

    :sys.suspend(view.pid)
    Enum.each(messages, &send(view.pid, &1))
    :sys.resume(view.pid)
    settle(view)
  end

  @doc """
  Waits until the LiveView has handled the events in its mailbox and the
  updates they sent itself, and the client proxy has their diffs; returns the
  rendered view.

  A render syncs with a ping that queues behind the events. The
  `send_update/2`s those events send queue behind that ping, so one render is
  not enough: it can come back before the form has applied them. They are all
  in the mailbox before the first ping returns, so a second render, whose ping
  queues behind them, sees their result.
  """
  def settle(view) do
    Phoenix.LiveViewTest.render(view)
    Phoenix.LiveViewTest.render(view)
  end

  @doc """
  Mounts an entry form and waits for it to finish rendering, returning
  `{view, html}`.

  The form arrives in three phases, which is why a bare `live/2` hands back a
  loader shell: `Form.update/2` kicks off `start_async(:entry_load, …)`, then
  defers the block editor by `send_update_after(…, :render_blocks, 50)`.
  `render_async/2` covers the first; only re-rendering covers the second.
  """
  defmacro live_form(conn, path, form_id \\ "page_form") do
    # A macro, not a function: `Phoenix.LiveViewTest.live/2` is itself a macro
    # that reads `@endpoint` from the calling module.
    quote do
      {:ok, view, _html} = Phoenix.LiveViewTest.live(unquote(conn), unquote(path))
      Phoenix.LiveViewTest.render_async(view, 5_000)
      {view, Brando.Test.await_selector(view, "##{unquote(form_id)}_form input")}
    end
  end

  @doc """
  Serializes a form in `html` the way a browser would, returning nested params.

  This is what makes recovery testable: LiveView's default form recovery
  replays the **DOM** through `phx-change` against a changeset freshly loaded
  from the database. So a value the editor holds only in changeset `changes` or
  in component assigns is not recoverable, and the only way to tell the two
  apart in a test is to serialize the DOM and nothing else.

  Follows the browser rules that matter here: skips disabled inputs, unchecked
  checkboxes and radios, and file inputs (a browser never sends their value).
  """
  def form_params(html, form_selector) do
    html
    |> Floki.parse_document!()
    |> Floki.find(form_selector)
    |> Floki.find("input, select, textarea")
    |> Enum.flat_map(&serialize_field/1)
    |> URI.encode_query()
    |> Plug.Conn.Query.decode()
  end

  defp serialize_field({tag, attrs, children}) do
    attrs = Map.new(attrs)
    name = Map.get(attrs, "name", "")

    if unsubmitted?(attrs, name) do
      []
    else
      field_value(tag, attrs, children, name)
    end
  end

  # A browser sends none of these: unnamed fields, anything disabled, the value
  # of a file input, or a button.
  defp unsubmitted?(attrs, name) do
    name == "" or Map.has_key?(attrs, "disabled") or
      Map.get(attrs, "type") in ["file", "submit", "button", "reset"]
  end

  defp field_value("textarea", _attrs, children, name), do: [{name, Floki.text(children)}]

  defp field_value("select", attrs, children, name),
    do: selected_option(children, name, Map.has_key?(attrs, "multiple"))

  defp field_value(_tag, %{"type" => type} = attrs, _children, name)
       when type in ["checkbox", "radio"] do
    if Map.has_key?(attrs, "checked"), do: [{name, Map.get(attrs, "value", "on")}], else: []
  end

  defp field_value(_tag, attrs, _children, name), do: [{name, Map.get(attrs, "value", "")}]

  # A single-select with no `selected` option is not an empty field: the browser
  # shows the first option and submits *that*. Returning `[]` here made recovery
  # params differ from the ones a real reconnect would send, in the harness
  # written to prove recovery works. A multi-select genuinely submits nothing
  # when nothing is selected, so the fallback is gated on `multiple`.
  defp selected_option(children, name, multiple?) do
    options = Floki.find(children, "option")

    case Enum.find(options, fn {_, attrs, _} -> List.keymember?(attrs, "selected", 0) end) do
      nil when multiple? -> []
      nil -> options |> List.first() |> option_pair(name)
      option -> option_pair(option, name)
    end
  end

  defp option_pair(nil, _name), do: []
  defp option_pair({_, attrs, text}, name), do: [{name, Map.new(attrs)["value"] || Floki.text(text)}]

  @doc """
  Serializes a form the way LiveView's *recovery* would push it — `form_params/2`
  plus the `_target` the client picks.

  The `_target` is not incidental. `pushFormRecovery` has no originating element
  to name, so it substitutes **the first non-hidden named input in the form**
  (`view.ts:2519`), pushes the form under the form's `phx-change` event, and the
  server turns that name into a key path (`channel.ex:848-853`). A handler that
  branches on `_target` therefore sees something quite different on recovery
  than it ever sees while the user types, which is easy to get wrong and
  impossible to notice without mounting the form.
  """
  def recovery_params(html, form_selector) do
    html
    |> form_params(form_selector)
    |> Map.put("_target", recovery_target(html, form_selector))
  end

  @doc """
  The `_target` key path LiveView's form recovery would send for this form.

  Mirrors `pushFormRecovery` (`deps/phoenix_live_view/assets/js/phoenix_live_view/view.ts:2490-2519`)
  as of **phoenix_live_view 1.2.12**: form-associated, named, no `phx-change` of
  its own, first non-hidden one wins.

  A mirror of somebody else's source drifts silently on a dependency bump, so
  `form_recovery_test.exs` asserts the version this was read against. If that
  assertion fails, re-read `pushFormRecovery` before bumping the number.
  """
  def recovery_target(html, form_selector) do
    html
    |> Floki.parse_document!()
    |> Floki.find(form_selector)
    |> Floki.find("input, select, textarea")
    |> Enum.map(fn {tag, attrs, children} ->
      {tag, Map.new(attrs), children}
    end)
    |> Enum.reject(fn {_, attrs, _} ->
      Map.get(attrs, "name", "") == "" or Map.has_key?(attrs, "phx-change") or
        Map.get(attrs, "type") in ["button", "submit", "reset"]
    end)
    |> then(fn candidates ->
      Enum.find(candidates, fn {_, attrs, _} -> Map.get(attrs, "type") != "hidden" end) ||
        List.first(candidates)
    end)
    |> case do
      nil -> []
      {_, attrs, _} -> attrs |> Map.fetch!("name") |> key_path()
    end
  end

  # "page[meta_title]" -> ["page", "meta_title"]; "upload" -> ["upload"].
  # Same route the server takes: decode, then walk down the nested map.
  defp key_path(name) do
    name |> Plug.Conn.Query.decode() |> gather_keys([]) |> Enum.reverse()
  end

  defp gather_keys(%{} = map, acc) do
    case Enum.at(map, 0) do
      {key, value} -> gather_keys(value, [key | acc])
      nil -> acc
    end
  end

  defp gather_keys([value | _], acc), do: gather_keys(value, acc)
  defp gather_keys(_, acc), do: acc
end
