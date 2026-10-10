defmodule BrandoAdmin.Content.StaleBlocksLive do
  @moduledoc """
  Block modules → Blocks on older versions: the blocks a module save could
  not bring up to date, what they hold that the module no longer defines,
  and resolving it (`Brando.Content.StaleBlocks`).

  `:index` lists the modules that have such blocks (the system check links
  here); `:module` resolves one module's blocks. Each leftover is resolved
  for every block at once, and a block can say otherwise.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.StaleBlocks
  alias Phoenix.LiveView.JS

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def __authorization__, do: {:update, Brando.Content.Module}

  @modules_path "/admin/config/content/modules"

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:current_user, Brando.Users.get_user_by_session_token(token))
       |> set_admin_locale()
       |> assign(:review?, false)
       |> assign(:lost_shown, 40)
       |> assign(:error, nil)
       |> assign(:done, nil)}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  def handle_params(params, url, %{assigns: %{socket_connected: true}} = socket) do
    socket = socket |> assign(:params, params) |> assign(:uri, URI.parse(url))

    case socket.assigns.live_action do
      :index -> {:noreply, assign(socket, :modules, StaleBlocks.modules())}
      :module -> {:noreply, socket |> assign(:module_id, String.to_integer(params["entry_id"])) |> load(reset: true)}
    end
  end

  def handle_params(params, url, socket),
    do: {:noreply, socket |> assign(:params, params) |> assign(:uri, URI.parse(url))}

  defp load(socket, opts) do
    case StaleBlocks.report(socket.assigns.module_id, socket.assigns.current_user) do
      {:ok, report} ->
        socket = assign(socket, :report, report)
        socket = if opts[:reset], do: assign(socket, bulk: %{}, overrides: %{}), else: socket
        plan(socket)

      {:error, reason} ->
        socket
        |> put_flash(:error, reason)
        |> push_navigate(to: @modules_path)
    end
  end

  defp plan(socket) do
    assign(socket, :plan, StaleBlocks.plan(socket.assigns.report, resolutions(socket.assigns)))
  end

  defp resolutions(%{bulk: bulk, overrides: overrides}), do: Map.merge(bulk, overrides)

  def handle_event("choose", params, socket) do
    bulk =
      for {leftover, choice} <- params["bulk"] || %{}, action = parse_choice(choice), into: %{} do
        {kind, key} = parse_leftover(leftover)
        {{kind, key}, action}
      end

    overrides =
      for {block_id, choices} <- params["block"] || %{},
          {leftover, choice} <- choices,
          action = parse_choice(choice),
          into: %{} do
        {kind, key} = parse_leftover(leftover)
        {{String.to_integer(block_id), kind, key}, action}
      end

    {:noreply, socket |> assign(bulk: bulk, overrides: overrides, error: nil, done: nil, review?: false) |> plan()}
  end

  # The review reads the blocks again, so it shows what the resolve will
  # find; the resolve is refused if they change after it (`expect:`).
  def handle_event("review", _, socket), do: {:noreply, socket |> load([]) |> assign(:review?, true)}
  def handle_event("cancel", _, socket), do: {:noreply, assign(socket, :review?, false)}

  def handle_event("resolve", _, socket) do
    %{module_id: module_id, current_user: user, plan: plan} = socket.assigns

    case StaleBlocks.apply(module_id, resolutions(socket.assigns), user, expect: plan.fingerprint) do
      {:ok, result} ->
        send(self(), {:toast, done_line(result)})

        {:noreply,
         socket
         |> assign(review?: false, error: nil, done: result)
         |> load(reset: true)}

      {:error, reason} ->
        {:noreply, socket |> assign(review?: false, error: reason) |> load([])}
    end
  end

  defp parse_choice("drop"), do: :drop
  defp parse_choice("keep"), do: :keep
  defp parse_choice("map:" <> target), do: {:map, target}
  defp parse_choice(_), do: nil

  defp parse_leftover("ref:" <> key), do: {:ref, key}
  defp parse_leftover("var:" <> key), do: {:var, key}

  defp leftover_id(%{kind: kind, key: key}), do: "#{kind}:#{key}"

  defp choice(nil), do: ""
  defp choice(:drop), do: "drop"
  defp choice(:keep), do: "keep"
  defp choice({:map, target}), do: "map:" <> target

  defp done_line(%{stamped: stamped}),
    do: ngettext("Brought %{count} block up to date.", "Brought %{count} blocks up to date.", length(stamped))

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="utils-workspace stale-blocks">
      <header class="utils-page-heading">
        <div>
          <.link navigate="/admin/config/content/modules" class="utils-eyebrow">← {gettext("Block modules")}</.link>
          <h1>{gettext("Blocks on older versions")}</h1>
          <p>
            {gettext(
              "Blocks that a module save could not bring up to date. They hold references or variables their module no longer defines; choose what happens to them, module by module."
            )}
          </p>
        </div>
      </header>

      <p :if={@modules == []} class="stale-blocks-empty">
        {gettext("All blocks are on their module's current version.")}
      </p>

      <div :if={@modules != []} class="utils-maintenance-list stale-blocks-modules">
        <article :for={%{module: module, count: count} <- @modules} data-module={module.uid}>
          <div>
            <h3>{StaleBlocks.module_name(module)}</h3>
            <p>
              {ngettext(
                "%{count} block on an older version than %{version}",
                "%{count} blocks on older versions than %{version}",
                count,
                count: count,
                version: module.version || 1
              )}
            </p>
          </div>
          <div class="utils-row-actions">
            <.link navigate={"/admin/config/content/modules/update/#{module.id}/stale-blocks"} class="utils-button">
              {gettext("Resolve blocks")}
            </.link>
          </div>
        </article>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="utils-workspace stale-blocks">
      <header class="utils-page-heading">
        <div>
          <.link navigate={"/admin/config/content/modules/update/#{@report.module.id}"} class="utils-eyebrow">
            ← {StaleBlocks.module_name(@report.module)}
          </.link>
          <h1>{gettext("Blocks on older versions")}</h1>
          <p :if={@report.blocks != []}>
            {ngettext(
              "%{count} block of %{module} is on an older version than the module's version %{version}. A module save keeps what the module no longer defines, so the block cannot be brought up to date until that is dropped or moved.",
              "%{count} blocks of %{module} are on older versions than the module's version %{version}. A module save keeps what the module no longer defines, so the blocks cannot be brought up to date until that is dropped or moved.",
              length(@report.blocks),
              count: length(@report.blocks),
              module: StaleBlocks.module_name(@report.module),
              version: @report.version
            )}
          </p>
        </div>
      </header>

      <p :if={@done} class="utils-feedback success stale-blocks-done" role="status">
        {done_line(@done)}
        <span :if={done_history_line(@done.entries)} class="stale-blocks-history">
          {done_history_line(@done.entries)}
        </span>
        <span :if={no_history(@done.entries) != []} class="stale-blocks-no-history">
          {no_history_line(no_history(@done.entries))}
        </span>
      </p>
      <p :if={@error} class="utils-feedback error" role="alert">{@error}</p>

      <p :if={@report.blocks == []} class="stale-blocks-empty">
        {gettext("All blocks of %{module} are on version %{version}.",
          module: StaleBlocks.module_name(@report.module),
          version: @report.version
        )}
      </p>

      <form :if={@report.blocks != []} id="stale-blocks-form" phx-change="choose" phx-submit="review">
        <section :if={@report.groups != []} class="stale-blocks-section" aria-labelledby="stale-leftovers-title">
          <div class="utils-section-heading">
            <h2 id="stale-leftovers-title">{gettext("Left over")}</h2>
            <p>
              {gettext(
                "References and variables the module no longer defines. What you choose here applies to every block, unless a block below says otherwise."
              )}
            </p>
          </div>
          <div class="stale-leftovers">
            <div :for={group <- @report.groups} class="stale-leftover" data-leftover={leftover_id(group)}>
              <div class="stale-leftover-what">
                <h3><code>{group.key}</code></h3>
                <p>
                  {StaleBlocks.kind_label(group.kind)} · <code>{Enum.join(group.types, ", ")}</code>
                  · {ngettext(
                    "in %{count} block",
                    "in %{count} blocks",
                    length(group.blocks)
                  )}
                </p>
                <p :if={group.reason == :retyped} class="stale-leftover-note">
                  {gettext("The module's %{key} is now a %{type} reference.", key: group.key, type: group.defined_type)}
                </p>
              </div>
              <label class="stale-leftover-choice">
                <span class="sr-only">{gettext("What happens to %{key}", key: group.key)}</span>
                <select class="admin-select" name={"bulk[#{leftover_id(group)}]"}>
                  <.choice_options targets={group.targets} selected={choice(@bulk[{group.kind, group.key}])} />
                </select>
              </label>
            </div>
          </div>
        </section>

        <section class="stale-blocks-section" aria-labelledby="stale-blocks-title">
          <div class="utils-section-heading">
            <h2 id="stale-blocks-title">
              {gettext("Blocks")} <span class="stale-blocks-count">{length(@report.blocks)}</span>
            </h2>
          </div>
          <ul class="stale-block-list">
            <li
              :for={{block, planned} <- Enum.zip(@report.blocks, @plan.blocks)}
              id={"stale-block-#{block.id}"}
              class={["stale-block", planned.refused != [] && "is-refused"]}
            >
              <div class="stale-block-head">
                <div class="stale-block-where">
                  <%= if block.entries == [] do %>
                    <strong class="stale-block-no-entry">{gettext("Not in any entry")}</strong>
                  <% else %>
                    <span :for={entry <- block.entries} class={["stale-block-entry", entry.trashed? && "is-trashed"]}>
                      <.link :if={entry.url} navigate={entry.url}>{entry.label}</.link>
                      <strong :if={!entry.url}>{entry.label}</strong>
                      <small>{entry.type}<span :if={entry.language}> · {String.upcase(to_string(entry.language))}</span><span :if={
                        entry.trashed?
                      }> · {gettext("In the trash")}</span></small>
                    </span>
                  <% end %>
                </div>
                <div class="stale-block-version">
                  <span class={["stale-block-chip", planned.stamps? && "is-ok"]}>
                    {version_line(block.module_version, @report.version, planned.stamps?)}
                  </span>
                  <small>#{block.id}</small>
                </div>
              </div>

              <p :if={block.leftovers == [] and block.problems == []} class="stale-block-note">
                {gettext("Nothing left over. Resolving re-syncs it with the module.")}
              </p>
              <p :for={problem <- block.problems} class="stale-block-problem">{problem}</p>

              <table :if={block.leftovers != []} class="stale-block-leftovers">
                <thead>
                  <tr>
                    <th scope="col">{gettext("Key")}</th>
                    <th scope="col">{gettext("Type")}</th>
                    <th scope="col">{gettext("Value")}</th>
                    <th scope="col">{gettext("In this block")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={leftover <- block.leftovers} data-leftover={leftover_id(leftover)}>
                    <td><code>{leftover.key}</code></td>
                    <td>
                      {StaleBlocks.kind_label(leftover.kind)} · <code>{leftover.type || "—"}</code>
                    </td>
                    <td class="stale-block-value">
                      <span :if={leftover.preview != ""}>{leftover.preview}</span>
                      <span :if={leftover.preview == ""} class="stale-block-empty-value">{gettext("Empty")}</span>
                    </td>
                    <td>
                      <label>
                        <span class="sr-only">{gettext("What happens to %{key} in this block", key: leftover.key)}</span>
                        <select class="admin-select" name={"block[#{block.id}][#{leftover_id(leftover)}]"}>
                          <option value="" selected={!Map.has_key?(@overrides, {block.id, leftover.kind, leftover.key})}>
                            {gettext("As above")} ({action_label(@bulk[{leftover.kind, leftover.key}])})
                          </option>
                          <.choice_options
                            targets={StaleBlocks.targets(leftover.kind, leftover.key, [leftover.type], @report.defined)}
                            selected={choice(@overrides[{block.id, leftover.kind, leftover.key}])}
                          />
                        </select>
                      </label>
                      <small :for={refusal <- refusals(planned, leftover)} class="stale-block-refused">
                        {refusal.reason}
                      </small>
                    </td>
                  </tr>
                </tbody>
              </table>
            </li>
          </ul>
        </section>

        <div :if={!@review?} class="utils-apply-bar stale-blocks-apply">
          <p>{summary_line(@plan)}</p>
          <button type="submit" class="utils-button primary" disabled={@plan.changed == [] or @plan.refused != []}>
            {gettext("Review changes")}
          </button>
        </div>
      </form>

      <section
        :if={@review? and @report.blocks != []}
        id="stale-blocks-review"
        class="stale-blocks-review"
        aria-labelledby="stale-blocks-review-title"
        tabindex="-1"
        phx-mounted={JS.focus()}
      >
        <div class="utils-section-heading">
          <h2 id="stale-blocks-review-title">{gettext("Review")}</h2>
          <p>
            <span :if={history_line(@plan.entries)} class="stale-blocks-history">{history_line(@plan.entries)}</span>
            <span :if={no_history(@plan.entries) != []} class="stale-blocks-no-history">
              {no_history_line(no_history(@plan.entries))}
            </span>
            <span :if={unowned(@plan) > 0} class="stale-blocks-no-owner">
              {ngettext(
                "%{count} block is not in any entry, so History cannot restore what changes in it.",
                "%{count} blocks are not in any entry, so History cannot restore what changes in them.",
                unowned(@plan)
              )}
            </span>
          </p>
        </div>
        <ul class="stale-blocks-actions">
          <li :for={{action, count} <- action_counts(@plan)}>{action_count_line(action, count)}</li>
        </ul>

        <%= if @plan.lost != [] do %>
          <h3>{gettext("What will be lost")}</h3>
          <ul class="stale-blocks-lost">
            <li :for={change <- Enum.take(@plan.lost, @lost_shown)}>
              <span class="stale-blocks-lost-where">{where(change)}</span>
              <code>{change.key}</code>
              <span :if={change.lost} class="stale-blocks-lost-value">{change.lost}</span>
              <span :if={change.replaces} class="stale-blocks-lost-value">
                {gettext("replaced in %{target}: %{value}", target: target(change), value: change.replaces)}
              </span>
            </li>
          </ul>
          <p :if={length(@plan.lost) > @lost_shown} class="stale-blocks-more">
            {gettext("and %{count} more", count: length(@plan.lost) - @lost_shown)}
          </p>
        <% else %>
          <p class="stale-blocks-nothing-lost">{gettext("Nothing that holds a value is dropped or replaced.")}</p>
        <% end %>

        <p :if={@plan.remaining != []} class="stale-blocks-remaining">
          {ngettext(
            "%{count} block stays on its older version: it still holds something you chose to keep.",
            "%{count} blocks stay on older versions: they still hold something you chose to keep.",
            length(@plan.remaining)
          )}
        </p>

        <div class="utils-apply-bar">
          <p>{summary_line(@plan)}</p>
          <div class="stale-blocks-review-actions">
            <button type="button" class="utils-button quiet" phx-click="cancel">{gettext("Change choices")}</button>
            <button
              id="stale-blocks-resolve"
              type="button"
              class={["utils-button", if(@plan.lost != [], do: "stale-blocks-destructive", else: "primary")]}
              phx-click="resolve"
              disabled={@plan.changed == [] or @plan.refused != []}
              data-confirm-title={ngettext("Resolve %{count} block?", "Resolve %{count} blocks?", length(@plan.changed))}
              data-confirm={confirm_line(@plan)}
              data-confirm-ok={ngettext("Resolve %{count} block", "Resolve %{count} blocks", length(@plan.changed))}
              data-confirm-destructive={@plan.lost != []}
            >
              {ngettext("Resolve %{count} block", "Resolve %{count} blocks", length(@plan.changed))}
            </button>
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :targets, :list, required: true
  attr :selected, :string, required: true

  defp choice_options(assigns) do
    ~H"""
    <option value="keep" selected={@selected == "keep"}>{gettext("Keep for now")}</option>
    <option value="drop" selected={@selected == "drop"}>{gettext("Drop")}</option>
    <optgroup :if={@targets != []} label={gettext("Move to")}>
      <option
        :for={target <- @targets}
        value={"map:" <> target.key}
        selected={@selected == "map:" <> target.key}
        disabled={!target.ok?}
        title={target.reason}
      >
        {target.key} ({target.type}){if !target.ok?, do: " — " <> gettext("not compatible")}
      </option>
    </optgroup>
    """
  end

  defp refusals(planned, leftover),
    do: Enum.filter(planned.refused, &(&1.kind == leftover.kind and &1.key == leftover.key))

  defp action_label(nil), do: gettext("keep for now")
  defp action_label(:keep), do: gettext("keep for now")
  defp action_label(:drop), do: gettext("drop")
  defp action_label({:map, target}), do: gettext("move to %{target}", target: target)

  defp version_line(from, to, true),
    do: gettext("Version %{from} → %{to}", from: from || "–", to: to)

  defp version_line(from, _to, false), do: gettext("Version %{from}", from: from || "–")

  defp summary_line(%{refused: [_ | _] = refused}) do
    ngettext(
      "%{count} choice cannot be made: see the blocks marked below.",
      "%{count} choices cannot be made: see the blocks marked below.",
      length(refused)
    )
  end

  defp summary_line(%{changed: []}), do: gettext("Choose what happens to what is left over.")

  defp summary_line(plan) do
    ngettext(
      "Resolving changes %{count} block in %{entries}; %{stamped} will be up to date.",
      "Resolving changes %{count} blocks in %{entries}; %{stamped} will be up to date.",
      length(plan.changed),
      entries: ngettext("%{count} entry", "%{count} entries", length(plan.entries)),
      stamped: length(plan.stamped)
    )
  end

  defp action_counts(plan) do
    resync = Enum.count(plan.blocks, &(&1.resync? and &1.id in plan.changed))

    plan.changes
    |> Enum.frequencies_by(&{&1.kind, &1.key, &1.action})
    |> Enum.sort()
    |> then(&if(resync > 0, do: &1 ++ [{:resync, resync}], else: &1))
  end

  defp action_count_line(:resync, count),
    do: ngettext("Re-sync %{count} block with nothing left over", "Re-sync %{count} blocks with nothing left over", count)

  defp action_count_line({_kind, key, :drop}, count),
    do: ngettext("Drop %{key} in %{count} block", "Drop %{key} in %{count} blocks", count, key: key)

  defp action_count_line({_kind, key, {:map, target}}, count),
    do:
      ngettext("Move %{key} to %{target} in %{count} block", "Move %{key} to %{target} in %{count} blocks", count,
        key: key,
        target: target
      )

  defp confirm_line(plan), do: lost_line(plan.lost) <> " " <> restore_line(plan)

  defp lost_line([]), do: gettext("Nothing that holds a value is dropped or replaced.")

  defp lost_line(lost),
    do: ngettext("%{count} value is dropped or replaced.", "%{count} values are dropped or replaced.", length(lost))

  defp restore_line(plan) do
    if plan.entries != [] and no_history(plan.entries) == [] and unowned(plan) == 0,
      do: gettext("A revision of each entry is stored first, so History can restore it."),
      else: gettext("History cannot restore all of it; see the review.")
  end

  # What History can restore: only an entry whose schema keeps revisions
  # (`revisioned?`) gets one before the resolve. In the trash or not.
  defp history_line([]), do: nil

  defp history_line(entries) do
    total = length(entries)

    case length(entries) - length(no_history(entries)) do
      ^total ->
        ngettext(
          "This changes %{count} entry. A revision of it is stored first, so History can restore it.",
          "This changes %{count} entries. A revision of each is stored first, so History can restore them.",
          total
        )

      0 ->
        ngettext("This changes %{count} entry.", "This changes %{count} entries.", total)

      revisioned ->
        ngettext("This changes %{count} entry.", "This changes %{count} entries.", total) <>
          " " <>
          ngettext(
            "A revision of %{count} of them is stored first, so History can restore it.",
            "A revision of %{count} of them is stored first, so History can restore them.",
            revisioned
          )
    end
  end

  defp done_history_line(entries) do
    total = length(entries)

    case total - length(no_history(entries)) do
      0 ->
        nil

      ^total ->
        ngettext(
          "A revision of the entry was stored first; History can restore it.",
          "A revision of each entry was stored first; History can restore them.",
          total
        )

      revisioned ->
        ngettext(
          "A revision of %{count} entry was stored first; History can restore it.",
          "Revisions of %{count} entries were stored first; History can restore them.",
          revisioned
        )
    end
  end

  defp no_history(entries), do: Enum.reject(entries, & &1.revisioned?)

  defp no_history_line(entries) do
    ngettext(
      "History cannot restore %{entries}: it keeps no revisions.",
      "History cannot restore %{entries}: they keep no revisions.",
      length(entries),
      entries: Enum.map_join(entries, ", ", & &1.label)
    )
  end

  # Changed blocks no entry owns: nothing stores a revision of them.
  defp unowned(plan), do: Enum.count(plan.blocks, &(&1.entries == [] and &1.id in plan.changed))

  defp where(%{entries: [entry | _]}), do: entry.label
  defp where(%{block_id: id}), do: gettext("Block #%{id}", id: id)

  defp target(%{action: {:map, target}}), do: target

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language |> to_string() |> Gettext.put_locale()
    socket
  end
end
