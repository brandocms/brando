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

  `kill_live/2` takes a view down the way a deploy or a crash would, and waits
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

    # `config` has to be present: `UserAuth.log_in_user/3` reads
    # `user.config.content_language` on the way in, and the factory leaves the
    # embed nil.
    user =
      Brando.Factory.insert(:random_user,
        role: :superuser,
        config: %Brando.Users.UserConfig{}
      )

    {:ok, conn: log_in_user(Phoenix.ConnTest.build_conn(), user), current_user: user}
  end

  @doc """
  Puts a session token for `user` on the conn.

  Deliberately not `BrandoAdmin.UserAuth.log_in_user/3`: that one ends in a
  `redirect/2`, so it hands back an already-sent 302 conn that `live/2` cannot
  dispatch. What the admin pipeline actually reads is the session, and this
  writes exactly what `put_token_in_session/2` writes.
  """
  def log_in_user(conn, user) do
    token = Brando.Users.generate_user_session_token(user)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
    |> Plug.Conn.put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  @doc """
  Kills a mounted LiveView the way a crash or a deploy would, and blocks until
  the process is actually gone.

  Deliberately not `:normal` — a normal exit is not what the recovery path is
  written for, and it would let the caller assert against a process that is
  still shutting down.

  `role` is the caller declaring what this view is to `live/2`'s client proxy.
  There is no default, because the two roles want genuinely different
  behaviour and a default would silently give a child view the root path:

    * `:root` — killing the view stops its proxy (`client_proxy.ex:542-545`),
      so an exit signal is on its way and is awaited. A proxy that never
      delivers one is a hang, and is flunked rather than waited out.
    * `:child` — shares the root's proxy, which stays alive. Nothing is in
      flight, so nothing is awaited: no race, and no pointless half-second.
  """
  def kill_live(view, role) when role in [:root, :child] do
    pid = view.pid
    {_ref, _topic, proxy_pid} = view.proxy
    ref = Process.monitor(pid)

    # `live/2` links the test process to the client proxy, which in turn dies
    # with the LiveView. Without trapping, killing the view kills the test.
    #
    # The flag is captured and restored rather than just set: leaving it on
    # changes how every *later* line in the same test process reacts to a
    # crash, so a test could pass against a LiveView that died on it. Capture
    # /restore composes across *repeated* calls — a second `kill_live/2` sees
    # `prior_trap?` as `true` and hands the flag back on.
    prior_trap? = Process.flag(:trap_exit, true)

    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      1_000 -> flunk("LiveView #{inspect(pid)} did not exit within 1s")
    end

    if role == :root, do: await_proxy_exit(proxy_pid)
    Process.flag(:trap_exit, prior_trap?)
    :ok
  end

  # Receives the exit of the one process `live/2` linked us to, and nothing
  # else. Any other `{:EXIT, _, _}` in the mailbox is left there
  # **deliberately** — it belongs to the test, which should be able to observe
  # it. Disposing of unrelated exits is precisely what the old `flush_exits/0`
  # did wrong: it drained every exit for 50ms, so a test carried on past a
  # crash it never saw.
  #
  # Only reached for a `:root` view, whose proxy the kill stops
  # (`client_proxy.ex:542-545`), so the exit is expected and arrives in
  # single-digit ms. Not arriving means the proxy is hung, and that is a
  # failure — this used to return `:ok` whenever the proxy was still alive,
  # which made a hung root indistinguishable from a healthy child.
  defp await_proxy_exit(proxy_pid) do
    receive do
      {:EXIT, ^proxy_pid, _reason} -> :ok
    after
      500 -> flunk("client proxy #{inspect(proxy_pid)} did not exit within 500ms")
    end
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
      {view, Brando.LiveCase.await_selector(view, "##{unquote(form_id)}_form input")}
    end
  end

  @doc """
  Re-renders `view` until `selector` matches, and returns the matching HTML.

  Polls observable DOM state rather than sleeping a guessed interval — the
  e2e suite's fixed `waitForTimeout` calls are the repo's worst flake source
  and there is no reason to import that pattern here.
  """
  def await_selector(view, selector, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_selector(view, selector, deadline)
  end

  defp do_await_selector(view, selector, deadline) do
    html = Phoenix.LiveViewTest.render(view)

    cond do
      html |> Floki.parse_document!() |> Floki.find(selector) |> Enum.any?() ->
        html

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("`#{selector}` never appeared in the rendered LiveView")

      true ->
        Process.sleep(20)
        do_await_selector(view, selector, deadline)
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
  (`view.ts:2450`), pushes the form under the form's `phx-change` event, and the
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

  Mirrors `pushFormRecovery` (`deps/phoenix_live_view/assets/js/phoenix_live_view/view.ts:2434-2450`)
  as of **phoenix_live_view 1.2.8**: form-associated, named, no `phx-change` of
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
