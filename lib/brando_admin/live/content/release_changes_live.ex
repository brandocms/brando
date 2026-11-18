defmodule BrandoAdmin.Content.ReleaseChangesLive do
  @moduledoc """
  Block modules → Release changes: the module definitions this site's
  release ships that differ from the ones it uses, reviewed, verified and
  applied (`Brando.Content.Definitions.Release`).

  Superusers, or with groups authorization those granted
  `brando.module_definitions.apply`. Each definition tree shows its template
  diff, its refs and vars, the entries it re-renders (with Verify's dry
  run and a per-block HTML diff) and a side-by-side preview. A conflict
  needs a choice, a definition never applied from files an explicit
  Replace, and one that needs a migration can't be applied. After an apply,
  a banner follows the renders and offers Keep and Revert
  (`Brando.Content.Definitions.Release.Batches`).
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{DefinitionApply, Definitions}
  alias Brando.Content.Definitions.Release
  alias Brando.Content.Definitions.Release.{Batches, Entries, Preview, Proposed, Review, Verify}
  alias BrandoAdmin.Components.ReleaseChanges, as: RC
  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def __authorization__, do: {:apply, :module_definitions}

  @tick 1_000
  @filters %{q: "", type: "", language: "", status: "", verdict: "", sort: "verify", dir: :asc, page: 1}

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      user = Brando.Users.get_user_by_session_token(token)

      if Release.authorize(user) == :ok do
        Phoenix.PubSub.subscribe(Brando.pubsub(), Verify.topic())
        Phoenix.PubSub.subscribe(Brando.pubsub(), Definitions.topic())

        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> assign(:current_user, user)
         |> assign(:page_title, gettext("Release changes"))
         |> set_admin_locale()
         |> assign(
           selected: nil,
           choices: %{},
           replace: MapSet.new(),
           current: nil,
           tab: "template",
           filters: @filters,
           diff: nil,
           confirm?: false,
           confirm_error: nil,
           preview: blank_preview(),
           tick: nil,
           renders: nil
         )
         |> load()}
      else
        {:ok,
         socket
         |> put_flash(:error, gettext("You do not have permission for this action."))
         |> push_navigate(to: "/admin")}
      end
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp blank_preview,
    do: %{
      key: nil,
      keys: nil,
      marks: [],
      marks?: true,
      viewport: "mobile",
      full?: false,
      focus: nil,
      share: nil,
      error: nil
    }

  ## Loading

  defp load(socket) do
    user = socket.assigns.current_user

    case Release.plan(user: user.id) do
      {:ok, :off} ->
        assign(socket, state: :off, report: nil, rows: [])

      {:error, message} ->
        assign(socket, state: :error, error: message, report: nil, rows: [])

      {:ok, report} ->
        socket |> assign(state: :ready, error: nil, report: report) |> derive(report) |> load_batch()
    end
  end

  defp derive(socket, report) do
    rows = Review.rows(report)
    module_ids = rows |> Enum.flat_map(& &1.uids) |> Entries.module_ids()
    entries = Entries.list(module_ids)

    by_row =
      Map.new(rows, fn row -> {row.uid, Enum.filter(entries, &Enum.any?(&1.modules, fn uid -> uid in row.uids end))} end)

    ready = for row <- rows, row.group == :ready, into: MapSet.new(), do: row.uid

    selected =
      case socket.assigns.selected do
        nil -> ready
        selected -> MapSet.intersection(selected, MapSet.new(rows, & &1.uid))
      end

    current =
      cond do
        socket.assigns.current && Enum.any?(rows, &(&1.uid == socket.assigns.current)) -> socket.assigns.current
        String.starts_with?(socket.assigns.current || "", "applied:") -> socket.assigns.current
        rows != [] -> hd(Enum.sort_by(rows, &(&1.group != :ready))).uid
        true -> nil
      end

    socket
    |> assign(
      rows: rows,
      counts: Review.counts(rows),
      entries: entries,
      entries_by_row: by_row,
      totals: Entries.counts(entries),
      selected: selected,
      choices: Map.take(socket.assigns.choices, Enum.map(rows, & &1.uid)),
      replace: MapSet.intersection(socket.assigns.replace, MapSet.new(rows, & &1.uid)),
      current: current,
      last_applied: last_applied(report),
      verify: Verify.get()
    )
    |> load_detail()
  end

  defp last_applied(report) do
    report.items
    |> Enum.map(& &1.applied)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(& &1.at, DateTime, fn -> nil end)
    |> case do
      %{release: release} when is_binary(release) -> release
      _ -> nil
    end
  end

  # The current row's definitions: the release's, the database's and the
  # last apply's, per item
  defp load_detail(%{assigns: %{current: "applied:" <> uid}} = socket) do
    rows = Brando.Repo.all(from(a in DefinitionApply, where: a.uid == ^uid, order_by: [desc: a.id], limit: 1))
    assign(socket, :detail, %{applied_row: List.first(rows), definitions: Review.definitions(socket.assigns.report, uid)})
  end

  defp load_detail(%{assigns: %{current: nil}} = socket), do: assign(socket, :detail, nil)

  defp load_detail(socket) do
    row = current_row(socket.assigns)
    definitions = if row, do: Map.new(row.items, &{&1.uid, Review.definitions(socket.assigns.report, &1.uid)}), else: %{}
    assign(socket, :detail, %{definitions: definitions})
  end

  defp load_batch(socket) do
    case Batches.pending() do
      nil ->
        assign(socket, batch: nil, batch_status: nil, renders: nil, applied_entries: [])

      batch ->
        status = Batches.status(batch, socket.assigns.current_user)
        names = Map.new(batch.definitions["items"] || [], &{&1["uid"], &1["name"]})
        changed = Enum.map(status.changed_since, &Map.put(&1, :name, names[&1.uid]))

        uids = Enum.map(batch.definitions["items"] || [], & &1["uid"])
        applied_entries = uids |> Entries.module_ids() |> Entries.list()

        socket
        |> assign(batch: batch, batch_status: %{status | changed_since: changed}, applied_entries: applied_entries)
        |> assign_renders(status.renders)
        |> schedule_tick()
    end
  end

  defp assign_renders(socket, nil), do: assign(socket, :renders, nil)

  defp assign_renders(socket, renders) do
    jobs = renders.failed ++ renders.pending
    labels = entry_labels(socket.assigns.entries ++ (socket.assigns[:applied_entries] || []))

    states =
      Map.new(jobs, fn job ->
        state =
          cond do
            job in renders.failed -> :failed
            job.state == "executing" -> :running
            true -> :queued
          end

        {{schema_module(job.schema), job.entry_id}, state}
      end)

    failures =
      for job <- renders.failed, job.worker == :render do
        key = {schema_module(job.schema), job.entry_id}
        %{label: labels[key] || "#{job.schema} ##{job.entry_id}", error: job.error}
      end

    total = renders.rendered + length(renders.failed) + Enum.count(renders.pending, &(&1.worker == :render))

    assign(socket, :renders, %{
      rendered: renders.rendered,
      failed: length(renders.failed),
      pending:
        Enum.count(renders.pending, &(&1.worker == :render)) + Enum.count(renders.pending, &(&1.worker == :cascade)),
      total: total,
      states: states,
      failures: failures
    })
  end

  defp entry_labels(entries), do: Map.new(entries, &{&1.key, &1.title})

  defp schema_module(nil), do: nil
  defp schema_module(schema) when is_binary(schema), do: Module.concat([schema])

  defp schedule_tick(%{assigns: %{renders: %{pending: pending}, tick: nil}} = socket) when pending > 0,
    do: assign(socket, :tick, Process.send_after(self(), :tick, @tick))

  defp schedule_tick(socket), do: socket

  ## Events

  def handle_event("select_row", %{"uid" => uid}, socket) do
    socket = socket |> assign(current: uid, filters: @filters) |> discard_preview() |> load_detail()

    tab =
      if String.starts_with?(uid, "applied:") and socket.assigns.tab in ["refs", "preview"],
        do: "template",
        else: socket.assigns.tab

    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("toggle_row", %{"uid" => uid}, socket) do
    row = Enum.find(socket.assigns.rows, &(&1.uid == uid))

    if row && RC.selectable?(row, socket.assigns.choices, socket.assigns.replace) do
      {:noreply, update(socket, :selected, &toggle(&1, uid))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_ready", _, socket) do
    ready = for row <- socket.assigns.rows, row.group == :ready, do: row.uid

    selected =
      if Enum.all?(ready, &MapSet.member?(socket.assigns.selected, &1)),
        do: Enum.reduce(ready, socket.assigns.selected, &MapSet.delete(&2, &1)),
        else: Enum.reduce(ready, socket.assigns.selected, &MapSet.put(&2, &1))

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(template refs entries preview) do
    socket = assign(socket, :tab, tab)

    {:noreply,
     if(tab == "preview" and is_nil(socket.assigns.preview.keys), do: render_preview(socket, nil), else: socket)}
  end

  def handle_event("choose", %{"uid" => uid, "choice" => choice}, socket) when choice in ~w(here release) do
    {:noreply, socket |> update(:choices, &Map.put(&1, uid, choice)) |> update(:selected, &MapSet.put(&1, uid))}
  end

  def handle_event("toggle_replace", %{"uid" => uid}, socket) do
    replace = toggle(socket.assigns.replace, uid)

    selected =
      if MapSet.member?(replace, uid),
        do: MapSet.put(socket.assigns.selected, uid),
        else: MapSet.delete(socket.assigns.selected, uid)

    {:noreply, assign(socket, replace: replace, selected: selected)}
  end

  def handle_event("verify_all", _, socket), do: {:noreply, start_verify(socket, socket.assigns.entries)}

  def handle_event("verify_row", %{"uid" => uid}, socket),
    do: {:noreply, start_verify(socket, socket.assigns.entries_by_row[uid] || [])}

  def handle_event("verify_current", _, socket),
    do: {:noreply, start_verify(socket, socket.assigns.entries_by_row[socket.assigns.current] || [])}

  def handle_event("cancel_verify", _, socket), do: {:noreply, assign(socket, :verify, Verify.cancel())}

  def handle_event("filter", params, socket) do
    filters =
      Map.merge(socket.assigns.filters, %{
        q: params["q"] || "",
        type: params["type"] || "",
        language: params["language"] || "",
        status: params["status"] || "",
        page: 1
      })

    {:noreply, assign(socket, :filters, filters)}
  end

  def handle_event("chip", %{"verdict" => verdict}, socket),
    do: {:noreply, update(socket, :filters, &%{&1 | verdict: verdict, page: 1})}

  def handle_event("sort", %{"col" => col}, socket) when col in ~w(title type status verify) do
    {:noreply,
     update(socket, :filters, fn filters ->
       dir = if filters.sort == col and filters.dir == :asc, do: :desc, else: :asc
       %{filters | sort: col, dir: dir}
     end)}
  end

  def handle_event("page", %{"page" => page}, socket),
    do: {:noreply, update(socket, :filters, &%{&1 | page: max(String.to_integer(page), 1)})}

  def handle_event("open_diff", %{"key" => key}, socket) do
    case find_entry(socket, key) do
      nil ->
        {:noreply, socket}

      entry ->
        proposed = Proposed.build(socket.assigns.report, conflicts: conflicts(socket.assigns))

        case Verify.blocks(entry.schema, entry.id, proposed) do
          {:ok, blocks} -> {:noreply, assign(socket, :diff, %{entry: entry, blocks: blocks, show_unchanged?: false})}
          {:error, message} -> {:noreply, put_flash(socket, :error, message)}
        end
    end
  end

  def handle_event("close_diff", _, socket), do: {:noreply, assign(socket, :diff, nil)}

  def handle_event("toggle_unchanged", _, socket),
    do: {:noreply, update(socket, :diff, &%{&1 | show_unchanged?: !&1.show_unchanged?})}

  def handle_event("preview_entry", %{"key" => key}, socket) do
    {:noreply, socket |> assign(tab: "preview", diff: nil) |> render_preview(key)}
  end

  def handle_event("viewport", %{"viewport" => vp}, socket) when vp in ~w(mobile tablet desktop),
    do: {:noreply, update(socket, :preview, &%{&1 | viewport: vp})}

  def handle_event("toggle_marks", _, socket), do: {:noreply, update(socket, :preview, &%{&1 | marks?: !&1.marks?})}

  def handle_event("full_screen", %{"on" => on}, socket) do
    full? = on == "true"
    preview = %{socket.assigns.preview | full?: full?, viewport: if(full?, do: "desktop", else: "mobile")}
    {:noreply, assign(socket, :preview, preview)}
  end

  def handle_event("focus_change", %{"step" => step}, socket) do
    %{marks: marks, focus: focus} = socket.assigns.preview

    if marks == [] do
      {:noreply, socket}
    else
      index = Enum.find_index(marks, &(&1.uid == focus)) || -1
      next = Enum.at(marks, rem(index + String.to_integer(step) + length(marks), length(marks)))
      {:noreply, update(socket, :preview, &%{&1 | focus: next.uid})}
    end
  end

  def handle_event("share_preview", _, socket) do
    with key when is_binary(key) <- socket.assigns.preview.key,
         %{} = entry <- find_entry(socket, key),
         proposed = Proposed.build(socket.assigns.report, conflicts: conflicts(socket.assigns)),
         {:ok, url, days} <- Preview.share(proposed, entry.schema, entry.id, socket.assigns.current_user) do
      {:noreply,
       socket
       |> update(:preview, &%{&1 | share: %{url: url, days: days}})
       |> push_event("release:copy", %{text: url})}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_confirm", _, socket), do: {:noreply, assign(socket, confirm?: true, confirm_error: nil)}
  def handle_event("close_confirm", _, socket), do: {:noreply, assign(socket, :confirm?, false)}

  def handle_event("apply", _, socket) do
    user = socket.assigns.current_user
    {rows, keep_here, _excluded} = scope(socket.assigns)

    with :ok <- Release.authorize(user),
         :ok <- keep_versions_here(keep_here, user),
         {:ok, applied} <- apply_rows(rows, socket.assigns, user) do
      {:noreply,
       socket
       |> assign(confirm?: false, selected: nil, choices: %{}, replace: MapSet.new())
       |> put_flash(:notice, applied_text(applied, keep_here))
       |> load()}
    else
      {:error, reason} -> {:noreply, assign(socket, :confirm_error, error_text(reason))}
    end
  end

  def handle_event("keep_batch", _, socket) do
    case socket.assigns.batch && Batches.keep(socket.assigns.batch, socket.assigns.current_user) do
      {:ok, _} -> {:noreply, socket |> put_flash(:notice, gettext("The apply is kept.")) |> load()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("revert_batch", _, socket) do
    case socket.assigns.batch && Batches.revert(socket.assigns.batch, socket.assigns.current_user) do
      {:ok, result} -> {:noreply, socket |> put_flash(:notice, reverted_text(result)) |> load()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      nil -> {:noreply, socket}
    end
  end

  ## Messages

  def handle_info({:release_verify, prefix, run}, socket) do
    if prefix == Brando.Tenant.current_prefix(), do: {:noreply, assign(socket, :verify, run)}, else: {:noreply, socket}
  end

  # Definitions changed here, by an apply or a save: plan again
  def handle_info({event, prefix}, socket)
      when event in [:definitions_applied, :definitions_changed, :definitions_batch_changed] do
    if prefix == Brando.Tenant.current_prefix() and socket.assigns[:socket_connected],
      do: {:noreply, load(socket)},
      else: {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    socket = assign(socket, :tick, nil)

    case socket.assigns.batch do
      %{run_id: run} when is_binary(run) ->
        socket = assign_renders(socket, Definitions.refresh_status(run))
        socket = if socket.assigns.renders.pending == 0, do: load_batch(socket), else: socket
        {:noreply, schedule_tick(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def terminate(_reason, socket) do
    if socket.assigns[:preview], do: Preview.discard(socket.assigns.preview.keys)
    :ok
  end

  ## Helpers

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language |> to_string() |> Gettext.put_locale()
    socket
  end

  defp toggle(set, uid), do: if(MapSet.member?(set, uid), do: MapSet.delete(set, uid), else: MapSet.put(set, uid))

  defp current_row(%{rows: rows, current: current}), do: Enum.find(rows, &(&1.uid == current))

  defp find_entry(socket, key), do: Enum.find(socket.assigns.entries, &(RC.entry_key(&1) == key))

  defp start_verify(socket, []), do: socket

  defp start_verify(socket, entries) do
    {:ok, run} = Verify.start(socket.assigns.report, entries, conflicts: conflicts(socket.assigns))
    socket |> assign(:verify, run) |> assign(:tab, if(socket.assigns.tab == "preview", do: "preview", else: "entries"))
  end

  defp render_preview(socket, key) do
    entries = socket.assigns.entries_by_row[socket.assigns.current] || []
    entry = (key && find_entry(socket, key)) || List.first(entries)
    socket = discard_preview(socket)

    case entry do
      nil ->
        update(socket, :preview, &%{&1 | error: gettext("No entry uses this module yet.")})

      entry ->
        proposed = Proposed.build(socket.assigns.report, conflicts: conflicts(socket.assigns))

        case Preview.render(proposed, entry.schema, entry.id, socket.assigns.current_user) do
          {:ok, keys} ->
            update(
              socket,
              :preview,
              &%{&1 | key: RC.entry_key(entry), keys: keys, marks: keys.marks, focus: nil, share: nil, error: nil}
            )

          {:error, reason} ->
            update(socket, :preview, &%{&1 | key: RC.entry_key(entry), keys: nil, marks: [], error: error_text(reason)})
        end
    end
  end

  defp discard_preview(socket) do
    Preview.discard(socket.assigns.preview.keys)
    update(socket, :preview, &%{&1 | keys: nil, marks: [], focus: nil, share: nil, error: nil})
  end

  # What the apply covers: the rows to apply, those to keep as they are here,
  # and those left out, with why
  defp scope(assigns) do
    rows = Enum.filter(assigns.rows, &MapSet.member?(assigns.selected, &1.uid))
    {keep_here, apply_rows} = Enum.split_with(rows, &(assigns.choices[&1.uid] == "here"))

    excluded =
      for row <- assigns.rows, not MapSet.member?(assigns.selected, row.uid) do
        why =
          cond do
            row.group == :blocked and row.status == :deleted -> gettext("in the trash here")
            row.group == :blocked -> gettext("needs a migration")
            row.status == :never_applied -> gettext("not replaced")
            row.status == :conflict -> gettext("choose a version first")
            true -> gettext("not selected")
          end

        %{row: row, why: why}
      end

    {apply_rows, keep_here, excluded}
  end

  defp keep_versions_here([], _user), do: :ok

  defp keep_versions_here(rows, user) do
    rows
    |> Enum.flat_map(fn row -> for item <- row.items, item.action == :conflict, do: item.uid end)
    |> Enum.reduce_while(:ok, fn uid, :ok ->
      case Release.keep_here(uid, user: user.id) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp apply_rows([], _assigns, _user), do: {:ok, nil}

  defp apply_rows(rows, assigns, user) do
    uids = Enum.map(rows, & &1.uid)
    replace = for row <- rows, row.status == :never_applied, item <- row.items, item.state == :never_applied, do: item.uid

    discard =
      for row <- rows,
          assigns.choices[row.uid] == "release",
          item <- row.items,
          item.state == :changed_in_both,
          do: item.uid

    Release.apply(uids, user: user.id, replace: replace, discard: discard, wait: false)
  end

  defp applied_text(nil, keep_here),
    do: ngettext("Kept 1 version here.", "Kept %{count} versions here.", length(keep_here))

  defp applied_text(%{result: result}, _keep_here),
    do: ngettext("Applied 1 module change.", "Applied %{count} module changes.", length(result.changes))

  defp reverted_text(%{reverted: reverted, conflicts: conflicts}) do
    text = ngettext("Reverted 1 module.", "Reverted %{count} modules.", length(reverted))

    if conflicts == [],
      do: text,
      else:
        text <>
          " " <>
          ngettext(
            "1 changed here since was left as it is.",
            "%{count} changed here since were left as they are.",
            length(conflicts)
          )
  end

  defp error_text(:forbidden), do: gettext("You do not have permission for this action.")
  defp error_text(:kept), do: gettext("This apply is already kept.")
  defp error_text(:reverted), do: gettext("This apply is already reverted.")
  defp error_text(:not_revertible), do: gettext("This can’t be reverted.")
  defp error_text(:no_preview_target), do: gettext("This content type has no preview target.")
  defp error_text(message) when is_binary(message), do: message
  defp error_text(other), do: inspect(other)

  # The entries of the current row, filtered, searched and sorted
  defp shown_entries(assigns) do
    all = assigns.entries_by_row[assigns.current] || []
    results = results(assigns)
    f = assigns.filters
    q = String.downcase(String.trim(f.q))

    all
    |> Enum.filter(fn entry ->
      (q == "" or String.contains?(String.downcase(entry.title), q) or
         String.contains?(String.downcase(entry.url || ""), q)) and
        (f.type == "" or entry.type == f.type) and
        (f.language == "" or entry.language == f.language) and
        (f.status == "" or to_string(entry.status) == f.status) and
        verdict_match?(f.verdict, entry, results, assigns.renders)
    end)
    |> Enum.sort_by(&sort_key(&1, f.sort, results), if(f.dir == :asc, do: :asc, else: :desc))
  end

  defp verdict_match?("", _entry, _results, _renders), do: true
  defp verdict_match?("r-failed", entry, _results, %{states: s}), do: s[entry.key] == :failed
  defp verdict_match?("r-queued", entry, _results, %{states: s}), do: s[entry.key] in [:queued, :running]
  defp verdict_match?(verdict, entry, results, _renders), do: to_string(get_in(results, [entry.key, :verdict])) == verdict

  defp sort_key(entry, "title", _results), do: String.downcase(entry.title)
  defp sort_key(entry, "type", _results), do: {entry.type, entry.language || ""}
  defp sort_key(entry, "status", _results), do: to_string(entry.status)

  defp sort_key(entry, "verify", results) do
    rank = %{failed: 0, changed: 1, same: 2}
    {Map.get(rank, get_in(results, [entry.key, :verdict]), 3), String.downcase(entry.title)}
  end

  defp results(%{verify: %{results: results}}), do: results
  defp results(_), do: %{}

  defp stale?(%{verify: %{fingerprint: fp}, report: report} = assigns),
    do: fp != Verify.fingerprint(report, conflicts: conflicts(assigns))

  defp stale?(_), do: false

  # The conflicts rendered with the release's version: those it was chosen
  # for, and the one on screen
  defp conflicts(assigns) do
    for row <- assigns.rows,
        assigns.choices[row.uid] == "release" or MapSet.member?(assigns.replace, row.uid) or
          (row.uid == assigns.current and row.group == :choice),
        item <- row.items,
        item.action == :conflict,
        do: item.uid
  end

  # Per row: how many of its entries Verify found failing, and whether it
  # verified them all
  defp row_verify(assigns) do
    results = results(assigns)

    Map.new(assigns.rows, fn row ->
      entries = assigns.entries_by_row[row.uid] || []
      verified = Enum.count(entries, &Map.has_key?(results, &1.key))
      failed = Enum.count(entries, &(get_in(results, [&1.key, :verdict]) == :failed))
      {row.uid, if(verified > 0, do: %{failed: failed, done?: verified == length(entries) and entries != []})}
    end)
  end

  defp entry_counts(assigns) do
    applied =
      for item <- applied_items(assigns), into: %{} do
        {"applied:" <> item["uid"], assigns.applied_entries |> Enum.count(&(item["uid"] in &1.modules))}
      end

    Map.merge(Map.new(assigns.entries_by_row, fn {uid, entries} -> {uid, length(entries)} end), applied)
  end

  defp applied_items(%{batch: %{definitions: %{"items" => items}}}), do: items
  defp applied_items(_), do: []

  defp confirm_entries(assigns) do
    Map.new(assigns.rows, fn row ->
      entries = assigns.entries_by_row[row.uid] || []
      {row.uid, %{count: length(entries), live: Enum.count(entries, &(&1.status == :published))}}
    end)
  end

  defp open_failures(assigns, rows) do
    results = results(assigns)

    rows
    |> Enum.flat_map(&(assigns.entries_by_row[&1.uid] || []))
    |> Enum.uniq_by(& &1.key)
    |> Enum.count(&(get_in(results, [&1.key, :verdict]) == :failed))
  end

  ## Render

  def render(%{socket_connected: false} = assigns), do: ~H""

  def render(assigns) do
    ~H"""
    <div class="admin-workspace release-review" data-testid="release-changes">
      <header class="workspace-heading">
        <div>
          <.link navigate="/admin/config/content/modules" class="workspace-eyebrow">← {gettext("Block modules")}</.link>
          <h1><.icon name="package" class="workspace-heading-icon" />{gettext("Release changes")}</h1>
          <p>
            {gettext(
              "Module definitions in this site’s release that differ from the ones it uses. Review them, verify that the affected entries render, then apply. Nothing changes until you apply."
            )}
          </p>
        </div>
      </header>

      <%= case @state do %>
        <% :off -> %>
          <Workspace.empty
            title={gettext("No module definitions in this release")}
            description={gettext("The release has no priv/modules, or release_path isn't configured.")}
          />
        <% :error -> %>
          <RC.notice tone="error" icon="circle-x" headline={gettext("The release’s definitions can’t be planned")}>
            {@error}
          </RC.notice>
        <% :ready -> %>
          <RC.banner :if={@batch} batch={@batch} renders={@renders} changed_since={@batch_status.changed_since} />
          <RC.summary
            report={@report}
            counts={@counts}
            totals={@totals}
            last_applied={@last_applied}
            verify={@verify}
            selected_count={MapSet.size(@selected)}
            waiting?={!!(@renders && @renders.pending > 0)}
          />
          <p :if={@rows == [] and !@batch} class="release-tab-note" data-testid="release-nothing">
            {gettext("Nothing to apply: this site has every definition in the release.")}
          </p>
          <div :if={@rows != [] or @batch} class="release-layout">
            <RC.rail
              rows={@rows}
              applied={applied_items(assigns)}
              current={@current}
              selected={@selected}
              choices={@choices}
              replace={@replace}
              row_verify={row_verify(assigns)}
              entry_counts={entry_counts(assigns)}
              batch={@batch}
              rendering?={!!(@renders && @renders.pending > 0)}
            />
            <section class="release-detail" data-testid="release-detail">
              <.detail {assigns} />
            </section>
          </div>
          <RC.confirm
            :if={@rows != []}
            open?={@confirm?}
            rows={elem(scope(assigns), 0)}
            keep_here={elem(scope(assigns), 1)}
            excluded={elem(scope(assigns), 2)}
            failures={open_failures(assigns, elem(scope(assigns), 0))}
            entries={confirm_entries(assigns)}
            error={@confirm_error}
          />
          <RC.block_diff :if={@diff} diff={@diff} />
      <% end %>
    </div>
    """
  end

  defp detail(%{current: "applied:" <> uid} = assigns) do
    item = Enum.find(applied_items(assigns), &(&1["uid"] == uid)) || %{"uid" => uid}
    changed = Enum.find(assigns.batch_status.changed_since, &(&1.uid == uid))
    applied_row = assigns.detail.applied_row
    here = assigns.detail.definitions.here
    entries = assigns.applied_entries |> Enum.filter(&(uid in &1.modules))
    title = item["name"] || uid
    {ns, name} = split_name(title)

    assigns =
      assign(assigns,
        item: item,
        changed: changed,
        applied_row: applied_row,
        here: here,
        row: %{uid: uid, namespace: ns, title: name},
        applied_entries: entries
      )

    ~H"""
    <RC.detail_head row={@row} verify?={false}>
      <:class_line>
        <span class="badge badge--success">{gettext("Applied")}</span>
        <span :if={@changed} class="badge badge--attention">{gettext("Changed here since")}</span>
        {cond do
          @changed -> gettext("Revert would leave this module as it is.")
          @renders && @renders.pending > 0 -> gettext("Re-rendering its entries.")
          true -> nil
        end}
      </:class_line>
    </RC.detail_head>
    <RC.tabs tab={@tab} entries={length(@applied_entries)} tabs={~w(template entries)} />
    <div class="release-tab-body">
      <%= if @tab == "entries" do %>
        <RC.entries
          entries={@applied_entries}
          all={@applied_entries}
          filters={@filters}
          results={%{}}
          renders={@renders}
          total={length(@applied_entries)}
        />
      <% else %>
        <RC.template_diff
          :if={@applied_row && @changed}
          id="applied-template"
          label={gettext("%{name} · template", name: @row.title)}
          description={gettext("Applied (%{version}) → edited here", version: @applied_row.release)}
          old={@applied_row.definition && @applied_row.definition["code"]}
          new={@here && @here["code"]}
          type={@here && @here["type"]}
        />
        <RC.template_diff
          :if={@applied_row && !@changed}
          id="applied-template"
          label={gettext("%{name} · template", name: @row.title)}
          description={gettext("Before → applied (%{version})", version: @applied_row.release)}
          old={@applied_row.previous && @applied_row.previous["code"]}
          new={@here && @here["code"]}
          type={@here && @here["type"]}
        />
      <% end %>
    </div>
    """
  end

  defp detail(%{current: nil} = assigns), do: ~H""

  defp detail(assigns) do
    row = current_row(assigns)
    entries = assigns.entries_by_row[row.uid] || []
    root_record = Brando.Repo.get_by(Brando.Content.Module, uid: row.uid)

    assigns =
      assign(assigns,
        row: row,
        row_entries: entries,
        module_id: root_record && root_record.id,
        shown: shown_entries(assigns)
      )

    ~H"""
    <RC.detail_head
      row={@row}
      meta={meta(@row, @row_entries)}
      verify?={@row_entries != [] and @row.group != :blocked}
      module_id={@module_id}
    >
      <:class_line>
        <span class={["badge", status_badge(@row.status)]}>{RC.status_label(@row.status)}</span>
        <span :if={@row.class} class="badge badge--outline">{RC.class_label(@row.class)}</span>
        {RC.class_help(@row.class)}
      </:class_line>
    </RC.detail_head>
    <RC.tabs tab={@tab} entries={length(@row_entries)} />
    <div class="release-tab-body">
      <%= case @tab do %>
        <% "template" -> %>
          <.choice_body row={@row} detail={@detail} report={@report} choices={@choices} replace={@replace} />
          <%= for item <- @row.items, defs = @detail.definitions[item.uid], defs.release, @row.status not in [:conflict] do %>
            <RC.template_diff
              :if={defs.release["kind"] == "module" and (is_nil(defs.here) or defs.here["code"] != defs.release["code"])}
              id={"tpl-#{item.uid}"}
              label={gettext("%{name} · template", name: item.name)}
              description={template_description(item, defs, @report.version)}
              old={defs.here && defs.here["code"]}
              new={defs.release["code"]}
              type={defs.release["type"]}
            />
            <RC.template_diff
              :if={defs.release["kind"] != "module" or (defs.here && defs.here["code"] == defs.release["code"])}
              id={"def-#{item.uid}"}
              label={gettext("%{name} · definition", name: item.name)}
              description={template_description(item, defs, @report.version) <> " · " <> gettext("the template is unchanged")}
              old={Review.definition_text(defs.here)}
              new={Review.definition_text(defs.release)}
            />
          <% end %>
        <% "refs" -> %>
          <%= for item <- @row.items, defs = @detail.definitions[item.uid] do %>
            <RC.structure name={item.name} structure={Review.structure(defs.here, defs.release)} />
          <% end %>
          <p class="release-tab-note">
            {gettext("Refs, vars and metadata as the plan compares them. The template diff is under Template.")}
          </p>
        <% "entries" -> %>
          <RC.entries
            entries={@shown}
            all={@row_entries}
            filters={@filters}
            results={results(assigns)}
            verify={@verify}
            stale?={stale?(assigns)}
            total={length(@shown)}
          />
        <% "preview" -> %>
          <RC.preview
            row={@row}
            entries={@row_entries}
            preview={@preview}
            version={@report.version}
            last_applied={@last_applied}
          />
      <% end %>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :detail, :map, required: true
  attr :report, :map, required: true
  attr :choices, :map, required: true
  attr :replace, :any, required: true

  defp choice_body(%{row: %{status: :conflict}} = assigns) do
    item = Enum.find(assigns.row.items, &(&1.action == :conflict)) || hd(assigns.row.items)
    defs = assigns.detail.definitions[item.uid]
    base = defs.applied && Review.definition_text(defs.applied.definition)
    hunks = if base, do: Review.three_way(base, Review.definition_text(defs.here), Review.definition_text(defs.release))
    assigns = assign(assigns, item: item, defs: defs, hunks: hunks, who: RC.person(item.edited))

    ~H"""
    <RC.notice headline={gettext("Changed here and in this release")}>
      {gettext(
        "%{name} edited this module on %{when}, after it was last applied. The release changes it too. It isn’t applied until you choose which version to keep.",
        name: @who,
        when: RC.date(@item.edited && @item.edited.at)
      )}
    </RC.notice>
    <h3 class="release-section-title">
      {gettext("Three versions")}
      <small :if={@hunks}>{ngettext("1 changed region", "%{count} changed regions", length(@hunks))}</small>
    </h3>
    <RC.three_way
      :if={@hunks}
      hunks={@hunks}
      applied={@defs.applied}
      edited={@item.edited}
      version={@report.version}
      type={@defs.release && @defs.release["type"]}
    />
    <RC.template_diff
      :if={!@hunks}
      id={"conflict-#{@item.uid}"}
      label={gettext("%{name} · definition", name: @item.name)}
      description={
        gettext("Edited here → release %{version}. The version last applied isn’t recorded.", version: @report.version)
      }
      old={Review.definition_text(@defs.here)}
      new={Review.definition_text(@defs.release)}
      type={@defs.release && @defs.release["type"]}
    />
    <h3 class="release-section-title">{gettext("Which version should the site use?")}</h3>
    <div class="release-choices" data-testid="release-choices">
      <label>
        <input
          type="radio"
          name={"choice-#{@row.uid}"}
          checked={@choices[@row.uid] == "here"}
          phx-click="choose"
          phx-value-uid={@row.uid}
          phx-value-choice="here"
          data-testid="release-choice-here"
        />
        <strong>{gettext("Keep the version edited here")}</strong>
        <p>
          {gettext(
            "%{name}’s edit stays and this module is left out of the apply. The release file is then out of date: Block modules marks it until a developer exports the module (Block modules → Export, or mix brando.modules export) and commits it to priv/modules.",
            name: @who
          )}
        </p>
      </label>
      <label>
        <input
          type="radio"
          name={"choice-#{@row.uid}"}
          checked={@choices[@row.uid] == "release"}
          phx-click="choose"
          phx-value-uid={@row.uid}
          phx-value-choice="release"
          data-testid="release-choice-release"
        />
        <strong>{gettext("Use the release’s version")}</strong>
        <p>
          {gettext("%{name}’s edit is replaced when you apply. The apply keeps it, and Revert brings it back.", name: @who)}
        </p>
      </label>
    </div>
    """
  end

  defp choice_body(%{row: %{status: :never_applied}} = assigns) do
    ~H"""
    <RC.notice headline={gettext("Never applied from the release’s files")}>
      {gettext(
        "This module was made or changed here before the site applied releases, and it differs from the release’s file. Nothing records which one is newer, so it’s kept as it is unless you replace it."
      )}
    </RC.notice>
    <div class="release-choices" style="grid-template-columns:1fr">
      <label>
        <input
          type="checkbox"
          checked={MapSet.member?(@replace, @row.uid)}
          phx-click="toggle_replace"
          phx-value-uid={@row.uid}
          data-testid="release-replace"
        />
        <strong>{gettext("Replace with the release’s version")}</strong>
        <p>
          {gettext(
            "The version here is replaced when you apply; the apply keeps it, and Revert brings it back. From then on this module follows the release’s files."
          )}
        </p>
      </label>
    </div>
    """
  end

  defp choice_body(%{row: %{status: :blocked}} = assigns) do
    ~H"""
    <RC.notice tone="error" icon="ban" headline={gettext("Can’t be applied until the content is migrated")}>
      {gettext(
        "The release changes what blocks hold content in. Applying it would drop that content, so this module is shown but not applied."
      )}
      <ul>
        <li :for={item <- @row.items} :if={item.action == :migration_required}>{item.name}: {item.reason}</li>
      </ul>
      <:actions>
        <.link navigate="/admin/config/content/modules/stale-blocks" class="btn btn--sm">{gettext("Blocks on older versions")}</.link>
      </:actions>
    </RC.notice>
    <p class="release-tab-note">
      {gettext(
        "A developer moves the content with a data migration in a later release. When it has run, the blocks show up under Blocks on older versions, and this module can be applied."
      )}
    </p>
    """
  end

  defp choice_body(%{row: %{status: :deleted}} = assigns) do
    ~H"""
    <RC.notice tone="error" icon="trash-2" headline={gettext("In the trash here")}>
      {gettext("Restore the module to apply the release’s version.")}
    </RC.notice>
    """
  end

  defp choice_body(assigns), do: ~H""

  defp template_description(item, defs, version) do
    case {item.action, defs.applied} do
      {:create, _} ->
        gettext("New in release %{version}", version: version)

      {_, %{release: release}} when is_binary(release) ->
        gettext("Applied (%{applied}) → release %{version}", applied: release, version: version)

      _ ->
        gettext("Here → release %{version}", version: version)
    end
  end

  defp meta(row, entries) do
    counts = Entries.counts(entries)

    children =
      if row.children == [],
        do: "",
        else: " · " <> ngettext("1 child module", "%{count} child modules", length(row.children))

    entries =
      if counts.entries == 0,
        do: "",
        else:
          " · " <>
            ngettext("1 entry", "%{count} entries", counts.entries) <> " · " <> gettext("%{live} live", live: counts.live)

    children <> entries
  end

  defp status_badge(:create), do: "badge--success"
  defp status_badge(status) when status in [:conflict, :never_applied], do: "badge--attention"
  defp status_badge(status) when status in [:blocked, :deleted], do: "badge--error"
  defp status_badge(_), do: nil

  defp split_name(name) do
    case String.split(name, " › ") do
      [single] -> {nil, single}
      parts -> {Enum.join(Enum.drop(parts, -1), " › "), List.last(parts)}
    end
  end
end
