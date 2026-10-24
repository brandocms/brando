defmodule BrandoAdmin.LiveView.Form.Tabs do
  @moduledoc """
  One tab per user edits an entry.

  An editor with the entry open in two of their own tabs would edit it in
  both: the stale tab misses what the other saved, and its save or recovery
  copy can put old values back. Other editors' tabs are not concerned: they
  sync as editors do (`Brando.EditSession`, the form's field sync).

  ## Claims

  Each form LiveView with an entry tracks itself on the entry's `tabs`
  presence topic (`Brando.Tenant.Topic.entry("tabs", schema, id)`), keyed by
  its user, with a claim stamp. Of a user's tabs, the one with the highest
  claim edits; a claim of 0 claims nothing. A tab claims when it opens and
  none of the user's other tabs holds a claim, and when the editor presses
  Edit here (or Take editing back); a claim is one more than the highest
  the tab sees, with the tab id breaking a tie, so every tab agrees on the
  editor without asking the others. A claim the tab made on opening is
  `auto`; one the editor made is not.

  ## A browser tab

  The browser tab sends an id of its own (`brando_tab`, from sessionStorage,
  which a duplicated tab doesn't share: see `initializeLiveSocket.js`) as a
  connect param. A tab that reconnects or reloads is a new process with the
  same id. Its old process may still be there: the server notices a lost
  connection only when its heartbeat runs out, and a node of a cluster may
  not have dropped it yet. Of the processes with one tab id, the newest is
  the tab (`joined`): it takes over the old one's claim, and the old one,
  with no browser left, edits nothing.

  The tab also sends the entries it edited (`brando_editing`), which the
  server keeps it told of (`b:brando-tab-mode`). When every tab rejoins at
  once (a deploy, a restart), the tracker has forgotten the claims, and the
  first tab to rejoin claims; the tab that edited claims again over such an
  `auto` claim, but not over one the editor made while it was away.

  ## Modes

    * `:editing` — the tab holds the highest claim.
    * `:waiting` — the tab opened while another one edits, or edits no more
      since that one closed. The form shows a notice with Edit here.
    * `:released` — the tab edited, and another tab claimed. The form shows a
      banner with Take editing back.
    * `:taking` — the tab claimed and waits for the tab that edited to hand
      over: a last recovery capture, whose copy this tab adopts
      (`{__MODULE__, :handover, ...}`). It edits when that arrives, when the
      other tab is gone, or after `handover_timeout/0`; without a handover
      the other tab's copy is offered as any recovery copy is.

  Nothing claims by itself: when the editing tab closes, the others say so
  and wait for the editor.

  The form component reads the state from the process (`current/0`) when it
  mounts and gets every change after that (`event: "tab_access"`).
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1, push_event: 3, send_update: 2]

  alias Brando.Tenant.Topic
  alias Phoenix.PubSub

  require Logger

  @key {__MODULE__, :access}

  @doc "The presence topic of an entry's tabs."
  def topic(schema, entry_id), do: Topic.entry("tabs", schema, entry_id)

  @doc """
  The tab state the form component starts with: what `arm/3` and later
  changes left in this process, or editing when no claim was armed (a new
  entry, the frontend editor).
  """
  def current, do: Process.get(@key) || %{mode: :editing, other: nil, closed?: false}

  @doc "Whether the form in this process edits the entry."
  def editing?, do: current().mode == :editing

  @doc """
  Read what the browser tab sent on connecting. Only in mount: LiveView
  drops connect params after it, and a create form arms its claim later.
  """
  def connect(socket) do
    params = (connected?(socket) && get_connect_params(socket)) || %{}

    tab =
      case params["brando_tab"] do
        tab when is_binary(tab) and byte_size(tab) in 1..64 -> tab
        _ -> Ecto.UUID.generate()
      end

    editing =
      case params["brando_editing"] do
        keys when is_list(keys) -> Enum.filter(keys, &is_binary/1)
        _ -> []
      end

    assign(socket, :tab_connect, %{tab: tab, editing: editing})
  end

  @doc """
  Track this tab on the entry's topic and take its mode. Called once the
  LiveView knows its entry (on mount, or when a create form's first save
  patches to the update route), in a connected process.
  """
  def arm(socket, schema, entry_id) do
    if connected?(socket) and not is_nil(entry_id) and socket.assigns[:current_user] do
      do_arm(socket, schema, entry_id)
    else
      socket
    end
  end

  defp do_arm(socket, schema, entry_id) do
    topic = topic(schema, entry_id)
    key = to_string(socket.assigns.current_user.id)
    %{tab: tab, editing: editing} = socket.assigns[:tab_connect] || %{tab: Ecto.UUID.generate(), editing: []}
    metas = metas(topic, key)

    # This tab's old process, after a reconnect or a reload
    ghost = metas |> Enum.filter(&(&1.tab == tab)) |> Enum.max_by(& &1.joined, fn -> nil end)
    others = Enum.reject(metas, &(&1.tab == tab))
    edited? = topic in editing

    {claim, auto} =
      cond do
        ghost && ghost.claim > 0 -> {ghost.claim, ghost.auto}
        # every tab rejoined at once: this one edited, and none claimed since
        edited? and not Enum.any?(others, &(&1.claim > 0 and not &1.auto)) -> {next_claim(others), true}
        Enum.any?(others, &(&1.claim > 0)) -> {0, true}
        true -> {next_claim(others), true}
      end

    meta = %{
      tab: tab,
      pid: self(),
      claim: claim,
      auto: auto,
      opened_at: (ghost && ghost.opened_at) || System.system_time(:second),
      joined: System.system_time(:microsecond)
    }

    PubSub.subscribe(Brando.pubsub(), topic)
    {:ok, _} = Brando.presence().track(self(), topic, key, meta)
    Process.put({__MODULE__, :topic}, topic)

    state = %{
      topic: topic,
      key: key,
      meta: meta,
      schema: schema,
      mode: if(edited? or (ghost && ghost.claim > 0), do: :released, else: :waiting),
      edited?: edited? or !!(ghost && ghost.claim > 0),
      others?: others != [],
      closed?: false,
      other: nil,
      from: nil,
      timer: nil
    }

    state = settle(state, metas(topic, key))
    if :unclaim in state.actions, do: Brando.presence().update(self(), topic, key, state.meta)
    state = Map.delete(state, :actions)

    socket
    |> assign(:tab_access, state)
    |> publish(state)
  end

  # The user's tabs on the topic. A process of this node that has died is
  # no tab, though the tracker lists it until it has handled the exit.
  @doc false
  def metas(topic, key) do
    case Brando.presence().list(topic) do
      %{^key => %{metas: metas}} -> Enum.filter(metas, &(valid_meta?(&1) and not dead?(&1.pid)))
      _ -> []
    end
  end

  defp valid_meta?(%{tab: tab, pid: pid, claim: claim, auto: auto, opened_at: _, joined: joined}),
    do: is_binary(tab) and is_pid(pid) and is_integer(claim) and is_boolean(auto) and is_integer(joined)

  defp valid_meta?(_), do: false

  defp dead?(pid), do: node(pid) == node() and not Process.alive?(pid)

  @doc false
  def next_claim(metas), do: Enum.reduce(metas, 0, &max(&1.claim, &2)) + 1

  @doc """
  The meta of the tab that edits, among `metas`: the highest claim, the tab
  id breaking a tie. `nil` when none claims.
  """
  def editor(metas) do
    metas
    |> Enum.filter(&(&1.claim > 0))
    |> Enum.max_by(&{&1.claim, &1.tab}, fn -> nil end)
  end

  @doc """
  The state after the user's tabs changed to `metas`: the mode this tab is
  in, the other tab the form names, and whether the other tabs are gone.
  Pure, apart from what it returns in `:actions` for the caller to do.
  """
  def settle(state, metas) do
    me = state.meta
    # A newer process of this browser tab is the tab now: this one has no
    # browser left (`## A browser tab`), and edits nothing.
    superseded? = Enum.any?(metas, &(&1.tab == me.tab and &1.pid != me.pid and &1.joined > me.joined))
    # This tab as it knows itself: its own presence can lag behind an update,
    # and its old processes are not other tabs.
    metas = [me | Enum.reject(metas, &(&1.tab == me.tab))]
    others = Enum.reject(metas, &(&1.pid == me.pid))
    editor = editor(metas)
    mine? = editor != nil and editor.pid == me.pid and not superseded?

    {mode, actions} =
      cond do
        superseded? ->
          {:released, []}

        mine? and state.mode == :taking ->
          # The tab it waits for may have closed: it can't hand over then.
          if state.from && Enum.any?(others, &(&1.pid == state.from)),
            do: {:taking, []},
            else: {:editing, [:took_over]}

        mine? ->
          {:editing, if(state.mode == :editing, do: [], else: [:took_over])}

        state.mode == :editing ->
          {:released, [{:release, editor.pid}]}

        state.mode == :taking ->
          {if(state.edited?, do: :released, else: :waiting), []}

        true ->
          {state.mode, []}
      end

    other = if editor && not mine?, do: editor, else: Enum.max_by(others, & &1.opened_at, fn -> nil end)

    # A tab that doesn't edit claims nothing: its old claim would have it
    # edit again by itself once the tab that edits closes.
    {meta, actions} =
      if mode in [:waiting, :released] and me.claim > 0,
        do: {%{me | claim: 0}, actions ++ [:unclaim]},
        else: {me, actions}

    %{
      state
      | mode: mode,
        meta: meta,
        edited?: state.edited? or mode == :editing,
        other: other && %{opened_at: other.opened_at},
        # Said once the tabs that were here have all gone, until another opens.
        closed?: others == [] and (state.others? or state.closed?),
        others?: others != []
    }
    |> Map.put(:actions, actions)
  end

  @doc """
  The editor pressed Edit here or Take editing back: this tab claims. It
  edits at once when no other tab edits; otherwise it waits for that one
  to hand over.
  """
  def claim(%{assigns: %{tab_access: %{mode: mode} = state}} = socket) when mode in [:waiting, :released] do
    metas = metas(state.topic, state.key)
    editor = metas |> Enum.reject(&(&1.tab == state.meta.tab)) |> editor()
    meta = %{state.meta | claim: next_claim(metas), auto: false}
    Brando.presence().update(self(), state.topic, state.key, meta)

    state =
      if editor do
        ref = make_ref()
        Process.send_after(self(), {__MODULE__, :handover_timeout, ref}, handover_timeout())
        %{state | meta: meta, mode: :taking, from: editor.pid, timer: ref}
      else
        %{state | meta: meta, mode: :editing, edited?: true, from: nil, timer: nil}
      end

    socket
    |> assign(:tab_access, Map.delete(state, :actions))
    |> publish(state, if(editor, do: nil, else: %{handover: nil}))
  end

  def claim(socket), do: socket

  @doc false
  def handle_info({__MODULE__, :changed}, %{assigns: %{tab_access: %{} = state}} = socket) do
    state = settle(state, metas(state.topic, state.key))

    socket =
      Enum.reduce(state.actions, socket, fn
        {:release, to}, socket ->
          release(socket, to)

        :unclaim, socket ->
          Brando.presence().update(self(), state.topic, state.key, state.meta)
          socket

        :took_over, socket ->
          socket
      end)

    took_over = if :took_over in state.actions, do: %{handover: nil}
    state = if state.mode == :taking, do: state, else: %{state | from: nil, timer: nil}

    {:halt, socket |> assign(:tab_access, Map.delete(state, :actions)) |> publish(state, took_over)}
  end

  # The tab that edited captured its recovery copy and hands it over. While
  # this tab waits for one it takes it, from whichever tab: a claim between
  # can have sent it on (below).
  def handle_info({__MODULE__, :handover, _from, handover}, %{assigns: %{tab_access: %{mode: :taking} = state}} = socket) do
    state = %{state | mode: :editing, edited?: true, from: nil, timer: nil}
    {:halt, socket |> assign(:tab_access, state) |> publish(state, %{handover: handover})}
  end

  def handle_info({__MODULE__, :handover, from, handover}, %{assigns: %{tab_access: %{} = state}} = socket) do
    if state.mode == :editing do
      # Too late: this tab edits already. The copy is offered as any is.
      {:halt, publish(socket, state, %{late_handover: handover})}
    else
      # Claimed meanwhile by another tab: it goes on to the one that edits.
      case editor(metas(state.topic, state.key)) do
        %{pid: pid} when pid != self() -> send(pid, {__MODULE__, :handover, from, handover})
        _ -> :ok
      end

      {:halt, socket}
    end
  end

  def handle_info({__MODULE__, :handover_timeout, ref}, %{assigns: %{tab_access: %{timer: ref} = state}} = socket) do
    Logger.info("[Tabs] no handover from the tab that edited; taking over without its copy")
    state = %{state | mode: :editing, edited?: true, from: nil, timer: nil}
    {:halt, socket |> assign(:tab_access, state) |> publish(state, %{handover: nil})}
  end

  def handle_info({__MODULE__, :handover_timeout, _ref}, socket), do: {:halt, socket}

  # A tab of this editor wrote a copy of edits it could not apply
  # (`offer_copy/0`): the editing tab offers it.
  def handle_info({__MODULE__, :copy_offered}, %{assigns: %{tab_access: %{mode: :editing}}} = socket) do
    if form_id = form_id(socket),
      do: send_update(BrandoAdmin.Components.Form, id: form_id, event: "refresh_draft_candidates")

    {:halt, socket}
  end

  def handle_info({__MODULE__, _}, socket), do: {:halt, socket}
  def handle_info({__MODULE__, _, _, _}, socket), do: {:halt, socket}
  def handle_info(_message, socket), do: {:cont, socket}

  @doc "The panel's and the banner's buttons."
  def handle_event("brando_tab_claim", _params, socket), do: {:halt, claim(socket)}
  def handle_event(_event, _params, socket), do: {:cont, socket}

  # Another tab claimed: the form stops editing, ships what it changed and
  # hands its recovery copy to `to` (`Form`, `event: "tab_release"`).
  defp release(socket, to) do
    send_update(BrandoAdmin.Components.Form, id: form_id(socket), event: "tab_release", to: to)
    socket
  end

  @doc """
  This tab wrote a recovery copy of edits it could not apply, since another
  tab edits (it reconnected with offline edits): the user's tabs read their
  copies again, and the editing one offers it. Copies are the user's own, so
  other editors' tabs on the topic need not hear of it, but do no harm.
  """
  def offer_copy do
    if topic = Process.get({__MODULE__, :topic}),
      do: PubSub.broadcast_from(Brando.pubsub(), self(), topic, {__MODULE__, :copy_offered})

    :ok
  end

  @doc "Hand the recovery copy `handover` (`%{draft_id: id, fields: [...]}` or `nil`) to the tab `to`."
  def hand_over(to, handover) when is_pid(to), do: send(to, {__MODULE__, :handover, self(), handover})

  @doc """
  Hands the form the tab's state, and keeps it in the process for a form
  that mounts later; tells the browser tab whether it edits the entry.
  `extra` says how the tab came to edit: `%{handover: copy | nil}` (adopt
  the copy, or offer the others), `%{late_handover: copy}`.
  """
  def publish(socket, state, extra \\ nil) do
    access = %{mode: state.mode, other: state.other, closed?: state.closed?}
    Process.put(@key, access)

    if form_id = form_id(socket) do
      message = [id: form_id, event: "tab_access", access: access]
      message = if extra, do: Keyword.merge(message, Map.to_list(extra)), else: message
      send_update(BrandoAdmin.Components.Form, message)
    end

    push_event(socket, "b:brando-tab-mode", %{key: state.topic, editing: state.mode == :editing})
  end

  defp form_id(socket) do
    case socket.assigns[:schema] do
      nil -> nil
      schema -> "#{schema.__naming__().singular}_form"
    end
  end

  # Brando's own tests wait less (`:tab_handover_timeout`), compiled in only
  # where `config :brando, :form_load_gate?, true`.
  if Application.compile_env(:brando, :form_load_gate?, false) do
    def handover_timeout, do: Application.get_env(:brando, :tab_handover_timeout, 5_000)
  else
    def handover_timeout, do: 5_000
  end
end
