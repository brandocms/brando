defmodule BrandoAdmin.Components.ReleaseChanges do
  @moduledoc """
  The parts of Block modules → Release changes (`BrandoAdmin.Content.ReleaseChangesLive`):
  the summary card, the definitions rail, the detail's tabs, the conflict
  views, the entries table, the side-by-side preview, the per-block HTML
  diff, the apply dialog and the apply's banner. Styles:
  `assets/css/views/config/ReleaseChanges.css`.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.Definitions.Release.Review
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.TextDiff
  alias Phoenix.LiveView.JS

  ## Summary

  attr :report, :map, required: true
  attr :counts, :map, required: true
  attr :totals, :map, required: true
  attr :last_applied, :any, default: nil
  attr :verify, :any, default: nil
  attr :selected_count, :integer, required: true
  attr :waiting?, :boolean, default: false

  def summary(assigns) do
    ~H"""
    <section class="release-summary" aria-label={gettext("Release summary")} data-testid="release-summary">
      <div class="release-summary-head">
        <div class="release-id">
          <.icon name="package" />
          <strong>{gettext("Release")} <code>{@report.version}</code></strong>
          <span :if={@last_applied} class="release-built">
            {gettext("last applied %{version}", version: @last_applied)}
          </span>
        </div>
        <div class="release-actions">
          <button
            :if={running?(@verify)}
            class="btn"
            type="button"
            phx-click="cancel_verify"
            data-testid="release-cancel-verify"
          >
            <.icon name="x" />{gettext("Cancel verify")}
          </button>
          <button
            :if={!running?(@verify)}
            class="btn"
            type="button"
            phx-click="verify_all"
            disabled={@totals.entries == 0 or @waiting?}
            data-testid="release-verify-all"
          >
            <.icon name="play" />{gettext("Verify all")}
          </button>
          <button
            class="btn btn--primary"
            type="button"
            phx-click="open_confirm"
            disabled={@selected_count == 0 or @waiting?}
            data-testid="release-apply"
          >
            {apply_label(@selected_count)}
          </button>
        </div>
      </div>
      <dl class="release-counts">
        <div class="release-counts-rows">
          <div>
            <dt>{gettext("Changes")}</dt>
            <dd>
              <.count n={@counts.actions.update} label={ngettext("update", "updates", @counts.actions.update)} />
              <.count n={@counts.actions.new} label={gettext("new")} class="badge--success" />
              <.count
                n={@counts.actions.conflict}
                label={ngettext("conflict", "conflicts", @counts.actions.conflict)}
                class="badge--attention"
              />
              <.count n={@counts.actions.never_applied} label={gettext("never applied")} class="badge--attention" />
            </dd>
          </div>
          <div>
            <dt>{gettext("Change classes")}</dt>
            <dd>
              <.count n={@counts.classes.metadata} label={gettext("metadata")} class="badge--outline" />
              <.count n={@counts.classes.render} label={gettext("render")} class="badge--outline" />
              <.count n={@counts.classes.compatible} label={gettext("compatible")} class="badge--outline" />
              <.count
                n={@counts.classes.destructive}
                label={gettext("destructive")}
                class={if @counts.classes.destructive > 0, do: "badge--attention", else: "badge--outline"}
              />
              <.count n={@counts.classes.migration_required} label={gettext("needs migration")} class="badge--error" />
            </dd>
          </div>
        </div>
        <div class="release-counts-total">
          <dt>{gettext("Entries affected")}</dt>
          <dd>
            <div class="release-total" data-testid="release-total">
              <strong>{@totals.entries}</strong>
              <span>
                {gettext("%{live} live", live: @totals.live)} · {ngettext("1 type", "%{count} types", @totals.types)}
              </span>
            </div>
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :n, :integer, required: true
  attr :label, :string, required: true
  attr :class, :string, default: nil

  defp count(assigns) do
    ~H"""
    <span class={["badge", @class, @n == 0 && "is-zero"]}><b>{@n}</b> {@label}</span>
    """
  end

  defp apply_label(0), do: gettext("Apply…")
  defp apply_label(n), do: ngettext("Apply 1 change…", "Apply %{count} changes…", n)

  defp running?(%{status: :running}), do: true
  defp running?(_), do: false

  ## Rail

  attr :rows, :list, required: true
  attr :applied, :list, default: []
  attr :current, :string, default: nil
  attr :selected, :any, required: true
  attr :choices, :map, required: true
  attr :replace, :any, required: true
  attr :row_verify, :map, required: true
  attr :entry_counts, :map, required: true
  attr :batch, :any, default: nil
  attr :rendering?, :boolean, default: false

  def rail(assigns) do
    groups = Enum.group_by(assigns.rows, & &1.group)
    ready = Map.get(groups, :ready, [])
    selectable = Enum.count(assigns.rows, &selectable?(&1, assigns.choices, assigns.replace))

    assigns =
      assigns
      |> assign(:groups, groups)
      |> assign(:all_ready?, ready != [] and Enum.all?(ready, &MapSet.member?(assigns.selected, &1.uid)))
      |> assign(:selectable, selectable)

    ~H"""
    <aside class="release-defs" aria-label={gettext("Module definitions in this release")} data-testid="release-rail">
      <div class="release-defs-head">
        <label :if={@groups[:ready]}>
          <input type="checkbox" checked={@all_ready?} phx-click="toggle_ready" data-testid="release-toggle-ready" />
          {gettext("Ready to apply")}
        </label>
        <span :if={!@groups[:ready]}>{ngettext("1 waiting", "%{count} waiting", length(@rows))}</span>
        <span>
          {gettext("%{selected} of %{total} selected", selected: MapSet.size(@selected), total: length(@rows))}
        </span>
      </div>
      <%= for {group, title} <- [choice: gettext("Needs a choice"), ready: gettext("Ready to apply"), blocked: gettext("Can’t be applied yet")], rows = @groups[group] do %>
        <h3>{title}</h3>
        <ul>
          <.def_row
            :for={row <- rows}
            row={row}
            current={@current}
            checked={MapSet.member?(@selected, row.uid)}
            selectable={selectable?(row, @choices, @replace)}
            note={row_note(row, @choices, @replace)}
            verify={@row_verify[row.uid]}
            entries={@entry_counts[row.uid] || 0}
          />
        </ul>
      <% end %>
      <%= if @applied != [] do %>
        <h3>
          {if @rendering?, do: gettext("Applied · rendering"), else: gettext("Applied %{when}", when: when_label(@batch))}
        </h3>
        <ul>
          <li
            :for={item <- @applied}
            class="release-def"
            aria-current={to_string(@current == "applied:" <> item["uid"])}
            phx-click="select_row"
            phx-value-uid={"applied:" <> item["uid"]}
            data-testid="release-applied-row"
          >
            <span></span>
            <div>
              <span class="release-def-name"><.def_name name={item["name"] || item["uid"]} /></span>
              <div class="release-def-meta">
                <span class="release-def-count">{entries_label(@entry_counts["applied:" <> item["uid"]] || 0)}</span>
                <span :if={@rendering?} class="release-def-verify">
                  <.icon name="loader-circle" class="spin" />{gettext("Rendering")}
                </span>
                <span :if={!@rendering?} class="release-def-verify is-applied">
                  <.icon name="check" />{gettext("Applied")}
                </span>
              </div>
            </div>
          </li>
        </ul>
      <% end %>
    </aside>
    """
  end

  attr :name, :string, required: true

  defp def_name(assigns) do
    assigns = assign(assigns, :parts, assigns.name |> String.split(" › ") |> Enum.reverse())

    ~H"""
    <%= case @parts do %>
      <% [single] -> %>
        {single}
      <% [last | rest] -> %>
        <span>{rest |> Enum.reverse() |> Enum.join(" › ")} ›</span> {last}
    <% end %>
    """
  end

  attr :row, :map, required: true
  attr :current, :string, default: nil
  attr :checked, :boolean, required: true
  attr :selectable, :boolean, required: true
  attr :note, :string, default: nil
  attr :verify, :any, default: nil
  attr :entries, :integer, required: true

  defp def_row(assigns) do
    ~H"""
    <li
      class={["release-def", @row.group == :blocked && "is-blocked"]}
      aria-current={to_string(@current == @row.uid)}
      phx-click="select_row"
      phx-value-uid={@row.uid}
      data-testid="release-row"
      data-uid={@row.uid}
    >
      <.icon :if={@row.group == :blocked} name="lock" class="release-def-lock" />
      <input
        :if={@row.group != :blocked}
        type="checkbox"
        checked={@checked}
        disabled={!@selectable}
        aria-label={gettext("Apply %{name}", name: row_name(@row))}
        phx-click="toggle_row"
        phx-value-uid={@row.uid}
        data-testid="release-row-check"
      />
      <div>
        <span class="release-def-name">
          <span :if={@row.namespace}>{@row.namespace} ›</span> {@row.title}
        </span>
        <span :if={@row.children != []} class="release-def-child">
          {ngettext("with child %{names}", "with children %{names}", length(@row.children),
            names: Enum.join(@row.children, ", ")
          )}
        </span>
        <div class="release-def-meta">
          <span class={["badge", status_class(@row.status)]}>{status_label(@row.status)}</span>
          <span :if={@row.class} class={["badge", class_badge(@row.class)]}>{class_label(@row.class)}</span>
          <span class="release-def-count">{row_count_label(@row, @entries)}</span>
          <.row_verify verify={@verify} />
        </div>
        <span :if={@note} class="release-def-note">{@note}</span>
      </div>
    </li>
    """
  end

  attr :verify, :any, required: true

  defp row_verify(%{verify: %{failed: failed}} = assigns) when failed > 0 do
    ~H"""
    <span class="release-def-verify is-failed">
      <.icon name="circle-x" />{ngettext("1 fails", "%{count} fail", @verify.failed)}
    </span>
    """
  end

  defp row_verify(%{verify: %{done?: true}} = assigns) do
    ~H"""
    <span class="release-def-verify is-ok"><.icon name="circle-check" />{gettext("Renders")}</span>
    """
  end

  defp row_verify(assigns), do: ~H""

  defp row_name(row), do: Enum.join(Enum.reject([row.namespace, row.title], &is_nil/1), " › ")

  defp row_count_label(%{status: :create}, 0), do: gettext("Not used yet")
  defp row_count_label(%{class: :metadata}, 0), do: gettext("No re-render")
  defp row_count_label(_row, n), do: entries_label(n)

  defp entries_label(n), do: pngettext("release", "1 entry", "%{count} entries", n)

  @doc "Whether a rail row can be checked: ready, or a choice was made."
  def selectable?(%{group: :ready}, _choices, _replace), do: true
  def selectable?(%{group: :blocked}, _choices, _replace), do: false

  def selectable?(%{status: :never_applied, uid: uid}, _choices, replace), do: MapSet.member?(replace, uid)
  def selectable?(%{uid: uid}, choices, _replace), do: Map.has_key?(choices, uid)

  defp row_note(%{group: :blocked, note: note}, _choices, _replace), do: note

  defp row_note(%{status: :never_applied, uid: uid}, _choices, replace) do
    if MapSet.member?(replace, uid),
      do: gettext("Replaced with the release’s version"),
      else: gettext("Kept as it is unless you replace it")
  end

  defp row_note(%{status: :conflict, uid: uid}, choices, _replace) do
    case choices[uid] do
      "here" -> gettext("Keeps the version edited here")
      "release" -> gettext("Uses the release’s version")
      _ -> gettext("Choose which version to keep")
    end
  end

  defp row_note(_row, _choices, _replace), do: nil

  defp when_label(%{applied_at: at}), do: Brando.Utils.Datetime.format_datetime(at, "%d.%m %H:%M")
  defp when_label(_), do: ""

  @doc "A rail row's status, as its badge says it."
  def status_label(:update), do: pgettext("release", "Update")
  def status_label(:create), do: gettext("New")
  def status_label(:conflict), do: gettext("Conflict")
  def status_label(:never_applied), do: gettext("Never applied")
  def status_label(:blocked), do: gettext("Blocked")
  def status_label(:deleted), do: gettext("In the trash")

  defp status_class(:create), do: "badge--success"
  defp status_class(status) when status in [:conflict, :never_applied], do: "badge--attention"
  defp status_class(status) when status in [:blocked, :deleted], do: "badge--error"
  defp status_class(_), do: nil

  @doc "A `ModuleDiff` class, as its badge says it."
  def class_label(:metadata), do: gettext("Metadata")
  def class_label(:render), do: gettext("Render")
  def class_label(:compatible), do: gettext("Compatible")
  def class_label(:destructive), do: gettext("Destructive")
  def class_label(:migration_required), do: gettext("Needs migration")
  def class_label(other), do: to_string(other)

  defp class_badge(:destructive), do: "badge--attention"
  defp class_badge(:migration_required), do: "badge--error"
  defp class_badge(_), do: "badge--outline"

  @doc "What a `ModuleDiff` class does to the blocks, in a sentence."
  def class_help(:metadata), do: gettext("Name, help text or icon only. Nothing re-renders.")
  def class_help(:render), do: gettext("Blocks re-render; their content is untouched.")

  def class_help(:compatible),
    do: gettext("Adds refs or vars. Existing blocks get the defaults and keep their content, then re-render.")

  def class_help(:destructive),
    do: gettext("Removes refs or vars. Blocks keep what they hold in them until you resolve the blocks after the apply.")

  def class_help(:migration_required),
    do: gettext("Changes what blocks hold content in. It can’t be applied until a migration has moved that content.")

  def class_help(_), do: nil

  ## Detail

  attr :row, :map, required: true
  attr :meta, :string, default: nil
  attr :verify?, :boolean, default: true
  attr :module_id, :any, default: nil
  slot :class_line

  def detail_head(assigns) do
    ~H"""
    <header class="release-detail-head">
      <div>
        <h2><span :if={@row[:namespace]}>{@row.namespace} ›</span> {@row.title}</h2>
        <p class="release-detail-meta"><code>{@row.uid}</code>{@meta}</p>
      </div>
      <div class="release-detail-actions">
        <button
          :if={@verify?}
          class="btn btn--sm"
          type="button"
          phx-click="verify_row"
          phx-value-uid={@row.uid}
          data-testid="release-verify-row"
        >
          <.icon name="play" />{pgettext("release", "Verify")}
        </button>
        <.link
          :if={@module_id}
          navigate={"/admin/config/content/modules/update/#{@module_id}"}
          class="btn btn--sm btn--quiet"
        >
          {gettext("Open module")} <.icon name="external-link" />
        </.link>
      </div>
    </header>
    <p class="release-class">{render_slot(@class_line)}</p>
    """
  end

  attr :tab, :string, required: true
  attr :entries, :integer, required: true
  attr :tabs, :list, default: ~w(template refs entries preview)

  def tabs(assigns) do
    ~H"""
    <div class="release-tabs">
      <nav class="pill-tabs" aria-label={gettext("Definition")}>
        <button
          :for={tab <- @tabs}
          type="button"
          aria-current={if @tab == tab, do: "page", else: "false"}
          phx-click="tab"
          phx-value-tab={tab}
          data-testid={"release-tab-#{tab}"}
        >
          {tab_label(tab)}
          <span :if={tab == "entries"} class="pill-tabs-count">{@entries}</span>
        </button>
      </nav>
    </div>
    """
  end

  defp tab_label("template"), do: gettext("Template")
  defp tab_label("refs"), do: gettext("Refs & vars")
  defp tab_label("entries"), do: gettext("Entries")
  defp tab_label("preview"), do: gettext("Preview")

  ## Template

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :old, :any, required: true
  attr :new, :any, required: true
  attr :type, :any, default: :liquid

  def template_diff(assigns) do
    ~H"""
    <TextDiff.diff
      id={@id}
      label={@label}
      description={@description}
      before={@old || ""}
      after={@new || ""}
      highlight={if @type in [:heex, "heex"], do: :heex, else: :liquid}
      context={4}
      empty_text={gettext("No template")}
    />
    """
  end

  ## Refs & vars

  attr :name, :string, required: true
  attr :structure, :map, required: true

  def structure(assigns) do
    rows =
      Enum.map(assigns.structure.metadata, &Map.put(&1, :kind, :field)) ++
        Enum.map(assigns.structure.refs, &Map.put(&1, :kind, :ref)) ++
        Enum.map(assigns.structure.vars, &Map.put(&1, :kind, :var))

    {changed, same} = Enum.split_with(rows, &(&1.change != :same))
    assigns = assign(assigns, changed: changed, same: same)

    ~H"""
    <div class="release-struct" data-testid="release-structure">
      <table>
        <caption>{@name}</caption>
        <thead>
          <tr>
            <th style="width:30%">{gettext("Field")}</th>
            <th>{gettext("Change")}</th>
            <th style="width:34%">{gettext("Effect on blocks")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @changed} class={"is-#{row.change}"}>
            <td>
              <span class="release-struct-key">
                <span class="release-struct-mark">{mark(row.change)}</span>
                <.struct_key row={row} />
              </span>
            </td>
            <td class="release-struct-change"><.struct_change row={row} /></td>
            <td class="release-struct-effect">{effect(row)}</td>
          </tr>
          <tr :if={@same != []}>
            <td>
              <span class="release-struct-key">
                <span class="release-struct-mark"></span>
                <span>
                  <%= for {row, i} <- Enum.with_index(@same) do %>
                    <code>{row.key}</code>{if i < length(@same) - 1, do: ", "}
                  <% end %>
                </span>
              </span>
            </td>
            <td class="release-struct-effect">{gettext("Unchanged")}</td>
            <td class="release-struct-effect">—</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :row, :map, required: true

  defp struct_key(%{row: %{kind: :field}} = assigns), do: ~H"<span>{field_label(@row.key)}</span>"

  defp struct_key(assigns) do
    ~H"""
    <span><code>{@row.key}</code> {if @row.kind == :ref, do: "ref", else: "var"}{@row[:type] && " · #{@row.type}"}</span>
    """
  end

  defp struct_change(%{row: %{change: :added}} = assigns), do: ~H|<ins>{gettext("Added")}</ins>|
  defp struct_change(%{row: %{change: :removed}} = assigns), do: ~H|<del>{gettext("Removed")}</del>|

  defp struct_change(%{row: %{kind: :field}} = assigns) do
    ~H"""
    <del>{short(@row.before)}</del><br /><ins>{short(@row.after)}</ins>
    """
  end

  defp struct_change(assigns) do
    ~H"""
    {gettext("Changed: %{fields}", fields: Enum.join(@row.fields, ", "))}
    """
  end

  defp mark(:added), do: "+"
  defp mark(:removed), do: "−"
  defp mark(:changed), do: "~"
  defp mark(_), do: ""

  defp effect(%{kind: :field}), do: gettext("None")
  defp effect(%{kind: :var, change: :added}), do: gettext("Blocks get the default")
  defp effect(%{kind: :ref, change: :added}), do: gettext("Blocks get the ref, empty or with its default")
  defp effect(%{change: :removed}), do: gettext("Blocks keep what they hold until it is resolved")
  defp effect(_), do: gettext("Blocks re-render")

  defp field_label("name"), do: gettext("Name")
  defp field_label("namespace"), do: gettext("Namespace")
  defp field_label("help_text"), do: gettext("Help text")
  defp field_label("class"), do: gettext("Class")
  defp field_label(field), do: field |> String.replace("_", " ") |> String.capitalize()

  defp short(%{} = map), do: Review.text(map, to_string(Brando.config(:default_admin_language) || "en"))
  defp short(nil), do: "—"
  defp short(value) when is_binary(value), do: value
  defp short(value), do: inspect(value)

  ## Notices and conflicts

  attr :tone, :string, default: nil
  attr :icon, :string, default: "triangle-alert"
  attr :headline, :string, required: true
  slot :inner_block
  slot :actions

  def notice(assigns) do
    ~H"""
    <div class={["release-notice", @tone && "is-#{@tone}"]}>
      <.icon name={@icon} />
      <p class="release-notice-headline">{@headline}</p>
      <div class="release-notice-text">{render_slot(@inner_block)}</div>
      <div :if={@actions != []} class="release-notice-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  attr :hunks, :list, required: true
  attr :applied, :any, default: nil
  attr :edited, :any, default: nil
  attr :version, :string, required: true
  attr :type, :any, default: :liquid

  def three_way(assigns) do
    ~H"""
    <div class="release-threeway" data-testid="release-threeway">
      <div class="threeway-head">
        <div>
          <strong>{gettext("Last applied")}</strong>
          <span :if={@applied}>
            {if @applied.release, do: gettext("Release %{version}", version: @applied.release), else: gettext("Imported")} · {date(
              @applied.applied_at
            )}
          </span>
          <span :if={@applied && @applied.applied_by}>
            {gettext("Applied by %{name}", name: @applied.applied_by.name)}
          </span>
        </div>
        <div>
          <strong>{gettext("Edited here")}</strong>
          <span :if={@edited}>{date(@edited.at)}</span>
          <Content.modal_person :if={@edited && @edited.by} user={@edited.by} compact />
        </div>
        <div>
          <strong>{gettext("Release file")}</strong>
          <span>{gettext("Release %{version}", version: @version)}</span>
        </div>
      </div>
      <%= for hunk <- @hunks do %>
        <div class="threeway-hunk">{hunk_label(hunk)}</div>
        <div :for={{row, i} <- Enum.with_index(hunk.rows)} class={["threeway-row", i == 0 && "is-first"]}>
          <.three_cell cell={row.base} type={@type} />
          <.three_cell cell={row.ours} type={@type} />
          <.three_cell cell={row.theirs} type={@type} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :cell, :any, required: true
  attr :type, :any, required: true

  defp three_cell(%{cell: {class, line}} = assigns) do
    language = if assigns.type in [:heex, "heex"], do: :heex, else: :liquid
    html = if line, do: line |> TextDiff.Highlight.tokens(language) |> TextDiff.Highlight.to_html(), else: ""
    assigns = assign(assigns, class: class, html: html)

    ~H"""
    <div class={@class}>{@html}</div>
    """
  end

  defp hunk_label(%{from: from, to: to, where: where}) do
    where =
      case where do
        :both -> gettext("changed on both sides")
        :here -> gettext("changed here only")
        :release -> gettext("changed in the release only")
      end

    gettext("Lines %{from}–%{to} · %{where}", from: from, to: to, where: where)
  end

  @doc "A time as the screen shows it, in the site's time zone."
  def date(nil), do: ""
  def date(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> date()
  def date(at), do: Brando.Utils.Datetime.format_datetime(at, "%d %b %Y, %H:%M")

  @doc "Who made an edit (`edited` of a plan item), or someone."
  def person(%{by: %{name: name}}), do: name
  def person(_), do: gettext("Someone")

  ## Entries

  attr :entries, :list, required: true
  attr :all, :list, required: true
  attr :filters, :map, required: true
  attr :results, :map, required: true
  attr :renders, :any, default: nil
  attr :verify, :any, default: nil
  attr :stale?, :boolean, default: false
  attr :total, :integer, required: true
  attr :page_size, :integer, default: 20

  def entries(assigns) do
    pages = max(ceil(assigns.total / assigns.page_size), 1)
    page = min(assigns.filters.page, pages)
    from = (page - 1) * assigns.page_size
    assigns = assign(assigns, pages: pages, page: page, from: from)

    ~H"""
    <.verify_strip verify={@verify} all={@all} results={@results} renders={@renders} stale?={@stale?} />
    <form class="release-entries-tools" phx-change="filter" phx-submit="filter" id="release-entries-filter">
      <div class="release-search">
        <.icon name="search" />
        <input
          type="search"
          name="q"
          value={@filters.q}
          phx-debounce="250"
          placeholder={ngettext("Search 1 entry", "Search %{count} entries", length(@all))}
          aria-label={gettext("Search entries")}
        />
      </div>
      <select class="admin-select" name="type" aria-label={gettext("Type")}>
        <option value="">{gettext("All types (%{count})", count: types_count(@all))}</option>
        <option :for={{type, n} <- group_count(@all, & &1.type)} value={type} selected={@filters.type == type}>
          {type} · {n}
        </option>
      </select>
      <select class="admin-select" name="language" aria-label={gettext("Language")}>
        <option value="">{gettext("All languages")}</option>
        <option
          :for={{lang, _n} <- group_count(@all, & &1.language)}
          :if={lang}
          value={lang}
          selected={@filters.language == lang}
        >
          {String.upcase(lang)}
        </option>
      </select>
      <select class="admin-select" name="status" aria-label={gettext("Status")}>
        <option value="">{gettext("All statuses")}</option>
        <option
          :for={{status, _n} <- group_count(@all, & &1.status)}
          :if={status}
          value={status}
          selected={@filters.status == to_string(status)}
        >
          {status_text(status)}
        </option>
      </select>
    </form>
    <div :if={@results != %{} or @renders} class="release-filter-chips" role="group" aria-label={gettext("Result")}>
      <button
        :for={{key, label} <- chips(@renders)}
        type="button"
        class="btn btn--pill"
        aria-pressed={to_string(@filters.verdict == key)}
        phx-click="chip"
        phx-value-verdict={key}
      >
        {label}
        <span class={["badge badge--count", key in ["failed", "r-failed"] && "badge--error"]}>{chip_count(
          key,
          @all,
          @results,
          @renders
        )}</span>
      </button>
    </div>
    <div class="release-entries" data-testid="release-entries">
      <table>
        <colgroup>
          <col /><col class="col-type" /><col class="col-status" /><col class="col-verify" /><col class="col-actions" />
        </colgroup>
        <thead>
          <tr>
            <th><.sort_button col="title" label={gettext("Entry")} filters={@filters} /></th>
            <th><.sort_button col="type" label={gettext("Type · language")} filters={@filters} /></th>
            <th><.sort_button col="status" label={gettext("Status")} filters={@filters} /></th>
            <th>
              <.sort_button
                col="verify"
                label={if @renders, do: gettext("Render"), else: gettext("Verify")}
                filters={@filters}
              />
            </th>
            <th><span class="sr-only">{gettext("Actions")}</span></th>
          </tr>
        </thead>
        <tbody>
          <%= for entry <- Enum.slice(@entries, @from, @page_size) do %>
            <% result = @results[entry.key] %>
            <% failure = result && List.first(result.failures) %>
            <tr class={[failed?(entry, result, @renders) && "is-failed", failure && "has-error"]} data-testid="release-entry">
              <td>
                <.link :if={entry.admin_url} navigate={entry.admin_url} class="entry-title">{entry.title}</.link>
                <span :if={!entry.admin_url} class="entry-title">{entry.title}</span>
                <span :if={entry.url} class="entry-url">{entry.url}</span>
              </td>
              <td>
                <span class="type-lang">{entry.type} <span :if={entry.language} class="lang">{entry.language}</span></span>
              </td>
              <td>
                <span :if={entry.status} class={["badge", "status-#{entry.status}"]}>
                  <span class="badge-dot"></span>{status_text(entry.status)}
                </span>
              </td>
              <td><.verdict entry={entry} result={result} renders={@renders} verify={@verify} /></td>
              <td>
                <div class="row-actions">
                  <button
                    :if={result && result.verdict in [:changed, :failed]}
                    class="btn btn--sm"
                    type="button"
                    phx-click="open_diff"
                    phx-value-key={entry_key(entry)}
                    data-testid="release-open-diff"
                  >
                    <.icon name="git-compare" />{gettext("HTML diff")}
                  </button>
                  <button
                    class="btn btn--sm btn--icon btn--quiet"
                    type="button"
                    phx-click="preview_entry"
                    phx-value-key={entry_key(entry)}
                    data-tooltip={gettext("Preview before and after")}
                    aria-label={gettext("Preview before and after")}
                  >
                    <.icon name="eye" />
                  </button>
                  <a
                    :if={entry.url}
                    class="btn btn--sm btn--icon btn--quiet"
                    href={entry.url}
                    target="_blank"
                    rel="noopener"
                    data-tooltip={gettext("Open the public page")}
                    aria-label={gettext("Open the public page")}
                  >
                    <.icon name="external-link" />
                  </a>
                </div>
              </td>
            </tr>
            <tr :if={failure} class="entry-error-row is-failed">
              <td colspan="5">
                <span class="entry-error">
                  {gettext("Block %{index}", index: failure.index)}{failure.module && ", #{failure.module}"} · {first_line(
                    failure.message
                  )}
                </span>
              </td>
            </tr>
          <% end %>
          <tr :if={@entries == []}>
            <td colspan="5" class="release-struct-effect">{gettext("No entries match.")}</td>
          </tr>
        </tbody>
      </table>
      <div class="release-entries-foot">
        <span>
          {gettext("Showing %{from}–%{to} of %{total}",
            from: min(@from + 1, @total),
            to: min(@from + @page_size, @total),
            total: @total
          )}
        </span>
        <span :if={@pages > 1} class="pager">
          <button class="btn btn--sm" type="button" disabled={@page <= 1} phx-click="page" phx-value-page={@page - 1}>
            {gettext("Previous")}
          </button>
          <span>{gettext("Page %{page} of %{pages}", page: @page, pages: @pages)}</span>
          <button class="btn btn--sm" type="button" disabled={@page >= @pages} phx-click="page" phx-value-page={@page + 1}>
            {gettext("Next")}
          </button>
        </span>
      </div>
    </div>
    """
  end

  attr :col, :string, required: true
  attr :label, :string, required: true
  attr :filters, :map, required: true

  defp sort_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="sort"
      phx-value-col={@col}
      aria-sort={if @filters.sort == @col, do: if(@filters.dir == :asc, do: "ascending", else: "descending")}
    >
      {@label}
      <.icon name={sort_icon(@filters, @col)} />
    </button>
    """
  end

  defp sort_icon(%{sort: col, dir: :asc}, col), do: "arrow-up"
  defp sort_icon(%{sort: col, dir: :desc}, col), do: "arrow-down"
  defp sort_icon(_, _), do: "arrow-up-down"

  attr :verify, :any, default: nil
  attr :all, :list, required: true
  attr :results, :map, required: true
  attr :renders, :any, default: nil
  attr :stale?, :boolean, default: false

  defp verify_strip(%{renders: %{} = renders} = assigns) do
    assigns = assign(assigns, :r, renders)

    ~H"""
    <div class="release-verify-strip" data-testid="release-render-strip">
      <div class="release-verify-summary">
        <span class="release-verify-title">
          <span :if={@r.pending > 0} class="is-running"><.icon name="loader-circle" class="spin" /></span>
          <span :if={@r.pending == 0 and @r.failed > 0} class="is-failed"><.icon name="circle-x" /></span>
          {if @r.pending > 0,
            do: ngettext("Re-rendering 1 entry", "Re-rendering %{count} entries", @r.total),
            else: ngettext("Re-rendered 1 entry", "Re-rendered %{count} entries", @r.total)}
        </span>
        <.progress done={@r.rendered} failed={@r.failed} total={@r.total} queued={@r.pending} />
      </div>
    </div>
    """
  end

  defp verify_strip(%{verify: %{status: :running} = run} = assigns) do
    counts = verdict_counts(assigns.all, run.results)
    assigns = assign(assigns, run: run, counts: counts)

    ~H"""
    <div class="release-verify-strip" data-testid="release-verify-strip">
      <div class="release-verify-summary">
        <span class="release-verify-title">
          <span class="is-running"><.icon name="loader-circle" class="spin" /></span>
          {gettext("Verifying %{done} of %{total} entries", done: @run.done, total: @run.total)}
          <small>· {gettext("nothing is written")}</small>
        </span>
        <div class="release-progress">
          <div class="release-progress-bar">
            <span style={"width:#{pct(@counts.changed + @counts.same, @run.total)}%"}></span>
            <span
              class="is-failed"
              style={"width:#{pct(@counts.failed, @run.total)}%;left:#{pct(@counts.changed + @counts.same, @run.total)}%"}
            ></span>
          </div>
          <div class="release-progress-legend">
            <span><i class="legend-dot"></i><b>{@counts.changed}</b> {gettext("render")}</span>
            <span><i class="legend-dot is-queued"></i><b>{@counts.same}</b> {gettext("unchanged")}</span>
            <span class="is-failed"><i class="legend-dot is-failed"></i><b>{@counts.failed}</b> {gettext("fail")}</span>
            <span><b>{@run.total - @run.done}</b> {gettext("waiting")}</span>
          </div>
        </div>
      </div>
      <button class="btn btn--sm" type="button" phx-click="cancel_verify"><.icon name="x" />{gettext("Cancel")}</button>
    </div>
    """
  end

  defp verify_strip(%{results: results} = assigns) when map_size(results) > 0 do
    counts = verdict_counts(assigns.all, results)
    assigns = assign(assigns, counts: counts)

    ~H"""
    <div class="release-verify-strip" data-testid="release-verify-strip">
      <div class="release-verify-summary">
        <span class="release-verify-title">
          <span :if={@counts.failed > 0} class="is-failed"><.icon name="circle-x" /></span>
          <span :if={@counts.failed == 0} class="is-ok"><.icon name="circle-check" /></span>
          {if @counts.failed > 0,
            do: gettext("%{failed} of %{total} entries fail to render", failed: @counts.failed, total: length(@all)),
            else: gettext("%{count} of %{total} entries verified", count: @counts.changed + @counts.same, total: length(@all))}
          <small :if={@verify && @verify.finished_at}>
            · {gettext("verified %{when}", when: date(@verify.finished_at))}
          </small>
          <small :if={@stale?}>· {gettext("the definitions changed since")}</small>
        </span>
        <div class="release-progress-legend">
          <span><b>{@counts.changed}</b> {gettext("render with changes")}</span>
          <span><b>{@counts.same}</b> {gettext("output unchanged")}</span>
          <span class="is-failed"><b>{@counts.failed}</b> {gettext("fail")}</span>
        </div>
      </div>
      <button class="btn btn--sm" type="button" phx-click="verify_current"><.icon name="rotate-ccw" />{gettext("Verify again")}</button>
    </div>
    """
  end

  defp verify_strip(assigns) do
    ~H"""
    <div class="release-verify-strip">
      <div class="release-verify-summary">
        <span class="release-verify-title">{gettext("Not verified yet")}</span>
        <span class="release-struct-effect">
          {gettext("Verify renders each entry with the release’s definitions and writes nothing.")}
        </span>
      </div>
      <button class="btn btn--sm" type="button" phx-click="verify_current" data-testid="release-verify-entries">
        <.icon name="play" />{pgettext("release", "Verify")}
      </button>
    </div>
    """
  end

  attr :done, :integer, required: true
  attr :failed, :integer, required: true
  attr :queued, :integer, required: true
  attr :total, :integer, required: true

  def progress(assigns) do
    ~H"""
    <div class="release-progress">
      <div class="release-progress-bar">
        <span style={"width:#{pct(@done, @total)}%"}></span>
        <span class="is-failed" style={"width:#{pct(@failed, @total)}%;left:#{pct(@done, @total)}%"}></span>
      </div>
      <div class="release-progress-legend">
        <span><i class="legend-dot"></i><b>{@done}</b> {gettext("of %{total} rendered", total: @total)}</span>
        <span class="is-failed"><i class="legend-dot is-failed"></i><b>{@failed}</b> {gettext("failed")}</span>
        <span><i class="legend-dot is-queued"></i><b>{@queued}</b> {gettext("queued")}</span>
      </div>
    </div>
    """
  end

  defp pct(_n, 0), do: 0
  defp pct(n, total), do: Float.round(n * 100 / total, 1)

  attr :entry, :map, required: true
  attr :result, :any, default: nil
  attr :renders, :any, default: nil
  attr :verify, :any, default: nil

  defp verdict(%{renders: %{states: states}} = assigns) do
    assigns = assign(assigns, :state, states[assigns.entry.key] || :rendered)

    ~H"""
    <span :if={@state == :rendered} class="verify is-ok"><.icon name="circle-check" />{gettext("Rendered")}</span>
    <span :if={@state == :running} class="verify is-running"><.icon name="loader-circle" class="spin" />{gettext("Rendering…")}</span>
    <span :if={@state == :queued} class="verify is-waiting"><.icon name="clock" />{gettext("Queued")}</span>
    <span :if={@state == :failed} class="verify is-failed"><.icon name="circle-x" />{gettext("Failed")}</span>
    """
  end

  defp verdict(%{result: %{verdict: :changed}} = assigns) do
    ~H"""
    <span class="verify is-ok"><.icon name="circle-check" />{gettext("Renders")}</span>
    <span class="verify-detail">{ngettext("1 block differs", "%{count} blocks differ", @result.changed)}</span>
    """
  end

  defp verdict(%{result: %{verdict: :same}} = assigns) do
    ~H"""
    <span class="verify is-same"><.icon name="equal" />{gettext("Output unchanged")}</span>
    """
  end

  defp verdict(%{result: %{verdict: :failed}} = assigns) do
    ~H"""
    <span class="verify is-failed"><.icon name="circle-x" />{gettext("Fails")}</span>
    """
  end

  defp verdict(%{verify: %{status: :running, keys: keys}, entry: entry} = assigns) do
    assigns = assign(assigns, :waiting?, MapSet.member?(keys, entry.key))

    ~H"""
    <span :if={@waiting?} class="verify is-waiting"><.icon name="circle-dashed" />{gettext("Waiting")}</span>
    """
  end

  defp verdict(assigns), do: ~H""

  defp failed?(entry, _result, %{states: states}), do: states[entry.key] == :failed
  defp failed?(_entry, %{verdict: :failed}, _renders), do: true
  defp failed?(_entry, _result, _renders), do: false

  @doc "An entry's key as a string for phx-value: `Schema:id`."
  def entry_key(%{schema: schema, id: id}), do: "#{inspect(schema)}:#{id}"

  defp first_line(nil), do: ""
  defp first_line(message), do: message |> String.split("\n", parts: 2) |> hd()

  defp chips(nil) do
    [
      {"", gettext("All")},
      {"failed", gettext("Fails")},
      {"changed", gettext("Renders")},
      {"same", gettext("Unchanged")}
    ]
  end

  defp chips(_renders), do: [{"", gettext("All")}, {"r-failed", gettext("Failed")}, {"r-queued", gettext("Queued")}]

  defp chip_count("", all, _results, _renders), do: length(all)
  defp chip_count("r-failed", all, _results, %{states: s}), do: Enum.count(all, &(s[&1.key] == :failed))
  defp chip_count("r-queued", all, _results, %{states: s}), do: Enum.count(all, &(s[&1.key] in [:queued, :running]))

  defp chip_count(verdict, all, results, _renders),
    do: Enum.count(all, &(to_string(get_in(results, [&1.key, :verdict])) == verdict))

  @doc "Counts of verdicts among `entries`."
  def verdict_counts(entries, results) do
    verdicts = Enum.map(entries, &get_in(results, [&1.key, :verdict]))

    %{
      changed: Enum.count(verdicts, &(&1 == :changed)),
      same: Enum.count(verdicts, &(&1 == :same)),
      failed: Enum.count(verdicts, &(&1 == :failed))
    }
  end

  defp types_count(all), do: all |> Enum.map(& &1.type) |> Enum.uniq() |> length()
  defp group_count(all, fun), do: all |> Enum.frequencies_by(fun) |> Enum.sort_by(fn {k, n} -> {-n, to_string(k)} end)

  @doc "An entry's status, as its badge says it."
  def status_text(:published), do: gettext("Live")
  def status_text(:draft), do: gettext("Draft")
  def status_text(:pending), do: gettext("Pending")
  def status_text(:deleted), do: gettext("Trashed")
  def status_text(:disabled), do: gettext("Disabled")
  def status_text(other), do: other |> to_string() |> String.capitalize()

  ## Preview

  attr :row, :map, required: true
  attr :entries, :list, required: true
  attr :preview, :map, required: true
  attr :version, :string, required: true
  attr :last_applied, :string, default: nil

  def preview(assigns) do
    ~H"""
    <div
      class={["release-preview", @preview.full? && "release-preview-full"]}
      id="release-preview"
      phx-hook="Brando.ReleaseChanges"
    >
      <header :if={@preview.full?}>
        <h2><span :if={@row[:namespace]}>{@row.namespace} ›</span> {@row.title}</h2>
        <.preview_tools entries={@entries} preview={@preview} />
      </header>
      <.preview_tools :if={!@preview.full?} entries={@entries} preview={@preview} />
      <div class="release-preview-marks">
        <button
          class="btn btn--sm btn--pill"
          type="button"
          aria-pressed={to_string(@preview.marks?)}
          phx-click="toggle_marks"
          data-testid="release-marks-toggle"
        >
          <.icon name="highlighter" />{gettext("Mark changes")}
        </button>
        <span :if={@preview.marks != []} class="release-changed-nav">
          {ngettext("1 block differs", "%{count} blocks differ", length(@preview.marks))}
          <button
            class="btn btn--sm btn--icon"
            type="button"
            phx-click="focus_change"
            phx-value-step="-1"
            aria-label={gettext("Previous changed block")}
          >
            <.icon name="chevron-up" />
          </button>
          <button
            class="btn btn--sm btn--icon"
            type="button"
            phx-click="focus_change"
            phx-value-step="1"
            aria-label={gettext("Next changed block")}
          >
            <.icon name="chevron-down" />
          </button>
        </span>
        <p class="release-preview-legend">
          <i :if={@preview.marks?}></i>
          {if @preview.marks?, do: gettext("Blocks that differ are outlined in both.")}
          {gettext("The proposed side is rendered by the server with the release’s definitions; nothing is saved.")}
        </p>
        <span :if={@preview.share} class="release-share" data-testid="release-share-result">
          <.icon name="check" />{gettext("Preview link copied · expires in %{days} days", days: @preview.share.days)}
        </span>
      </div>
      <p :if={@preview.error} class="release-notice is-error">
        <.icon name="circle-x" /><span>{@preview.error}</span>
      </p>
      <div :if={@preview.keys} class="release-preview-pair">
        <.pane
          id="release-preview-before"
          key={@preview.keys.before}
          label={gettext("Now")}
          sub={if @last_applied, do: gettext("Live · %{version}", version: @last_applied), else: gettext("Live")}
          preview={@preview}
        />
        <.pane
          id="release-preview-after"
          key={@preview.keys.after}
          label={gettext("With this release")}
          sub={@version}
          preview={@preview}
        />
      </div>
    </div>
    """
  end

  attr :entries, :list, required: true
  attr :preview, :map, required: true

  defp preview_tools(assigns) do
    ~H"""
    <form class="release-preview-tools" phx-change="preview_entry" id="release-preview-tools">
      <select class="admin-select" name="key" aria-label={gettext("Entry")}>
        <option :for={entry <- @entries} value={entry_key(entry)} selected={@preview.key == entry_key(entry)}>
          {entry.title} · {entry.type}{entry.language && " · #{entry.language}"}
        </option>
      </select>
      <span class="btn-group" role="group" aria-label={gettext("Viewport")}>
        <button
          :for={
            {vp, icon, label} <- [
              {"mobile", "smartphone", gettext("Mobile")},
              {"tablet", "tablet", gettext("Tablet")},
              {"desktop", "monitor", gettext("Desktop")}
            ]
          }
          class="btn btn--sm"
          type="button"
          aria-pressed={to_string(@preview.viewport == vp)}
          data-tooltip={label}
          aria-label={label}
          phx-click="viewport"
          phx-value-viewport={vp}
        >
          <.icon name={icon} />{if @preview.full?, do: label}
        </button>
      </span>
      <span class="spacer"></span>
      <button :if={@preview.keys} class="btn btn--sm" type="button" phx-click="share_preview" data-testid="release-share">
        <.icon name="share-2" />{gettext("Share preview")}
      </button>
      <button
        :if={!@preview.full?}
        class="btn btn--sm"
        type="button"
        phx-click="full_screen"
        phx-value-on="true"
        data-testid="release-full-screen"
      >
        <.icon name="maximize-2" />{gettext("Full screen")}
      </button>
      <button
        :if={@preview.full?}
        class="btn btn--sm"
        type="button"
        phx-click="full_screen"
        phx-value-on="false"
        data-testid="release-exit-full-screen"
      >
        <.icon name="minimize-2" />{gettext("Exit full screen")} <kbd>Esc</kbd>
      </button>
    </form>
    """
  end

  attr :id, :string, required: true
  attr :key, :any, required: true
  attr :label, :string, required: true
  attr :sub, :string, required: true
  attr :preview, :map, required: true

  defp pane(assigns) do
    ~H"""
    <div class="release-preview-pane" data-vp={@preview.viewport}>
      <header><strong>{@label}</strong><span>{@sub}</span></header>
      <div class="release-preview-viewport">
        <iframe
          :if={is_binary(@key)}
          id={@id}
          title={@label}
          src={"/__livepreview?key=#{@key}"}
          sandbox={Brando.Plug.LivePreview.sandbox_flags()}
          phx-hook="Brando.ReleasePreview"
          data-viewport={@preview.viewport}
          data-full={to_string(@preview.full?)}
          data-marks={Jason.encode!(if @preview.marks?, do: @preview.marks, else: [])}
          data-focus={@preview.focus}
        ></iframe>
        <p :if={!is_binary(@key)} class="release-notice is-error">
          <.icon name="circle-x" />
          <span>{gettext("The page can’t be rendered with this release: %{error}", error: elem(@key, 1))}</span>
        </p>
      </div>
    </div>
    """
  end

  ## Per-block HTML diff

  attr :diff, :map, required: true

  def block_diff(assigns) do
    entry = assigns.diff.entry
    blocks = assigns.diff.blocks
    shown = if assigns.diff.show_unchanged?, do: blocks, else: Enum.filter(blocks, &(&1.state in [:changed, :failed]))
    changed = Enum.count(blocks, &(&1.state == :changed))
    failed = Enum.count(blocks, &(&1.state == :failed))
    assigns = assign(assigns, entry: entry, blocks: blocks, shown: shown, changed: changed, failed: failed)

    ~H"""
    <Content.modal
      id="release-block-diff"
      title={@entry.title}
      subtitle={gettext("Rendered HTML per block · %{type} · nothing is saved", type: @entry.type)}
      icon="code"
      layout="release-diff"
      show
      close={JS.push("close_diff")}
    >
      <:header>
        <button class="btn btn--sm" type="button" phx-click="preview_entry" phx-value-key={entry_key(@entry)}>
          <.icon name="eye" />{gettext("Preview")}
        </button>
        <.link :if={@entry.admin_url} navigate={@entry.admin_url} class="btn btn--sm btn--quiet">
          {gettext("Open entry")} <.icon name="external-link" />
        </.link>
      </:header>
      <div class="modal-sections">
        <nav class="modal-section-nav" aria-label={gettext("Blocks")}>
          <p class="nav-legend">
            {ngettext("1 block", "%{count} blocks", length(@blocks))} · {ngettext("1 differs", "%{count} differ", @changed)} · {ngettext(
              "1 fails",
              "%{count} fail",
              @failed
            )}
          </p>
          <a
            :for={block <- @blocks}
            :if={@diff.show_unchanged? or block.state in [:changed, :failed]}
            href={"#release-block-#{block.index}"}
            class={block.state in [:same, :untouched] && "is-unchanged"}
          >
            <span class="block-index">{block.index}</span>
            <span class="block-name">{block.module || gettext("Block")}<small>{block_state_label(block)}</small></span>
            <.icon name={block_state_icon(block.state)} class={"block-state is-#{block_state_class(block.state)}"} />
          </a>
          <label class="nav-toggle">
            <input type="checkbox" checked={@diff.show_unchanged?} phx-click="toggle_unchanged" />
            {gettext("Show unchanged blocks")}
          </label>
        </nav>
        <div class="modal-section-content">
          <%= for block <- @shown do %>
            <div class="block-diff-head" id={"release-block-#{block.index}"}>
              <h3>{block.index} · {block.module || gettext("Block")}</h3>
              <span>{gettext("Block")} <code>{block.uid}</code></span>
            </div>
            <TextDiff.diff
              :if={block.state == :changed}
              id={"release-block-diff-#{block.index}"}
              label={gettext("Rendered HTML")}
              description={gettext("Now → with this release")}
              before={pretty(block.before)}
              after={pretty(block.after)}
              highlight={:html}
              context={3}
            />
            <div :if={block.state == :failed} class="block-error" data-testid="release-block-error">
              <strong>{gettext("Fails to render with this release.")}</strong>
              {gettext("Live, the block keeps the HTML it has now until the template or its content is fixed.")}
              <pre>{block.message}</pre>
            </div>
            <p :if={block.state in [:same, :untouched]} class="release-tab-note">{gettext("The output is unchanged.")}</p>
          <% end %>
          <p :if={@shown == []} class="release-tab-note">{gettext("No block differs.")}</p>
        </div>
      </div>
      <:footer>
        <span class="modal-footer-note">{gettext("The HTML is shown one tag a line.")}</span>
        <button class="btn" type="button" phx-click="close_diff">{gettext("Close")}</button>
      </:footer>
    </Content.modal>
    """
  end

  defp block_state_icon(:changed), do: "git-compare"
  defp block_state_icon(:failed), do: "circle-x"
  defp block_state_icon(_), do: "equal"

  defp block_state_class(:changed), do: "changed"
  defp block_state_class(:failed), do: "failed"
  defp block_state_class(_), do: "same"

  defp block_state_label(%{state: :failed}), do: gettext("fails")
  defp block_state_label(%{state: :changed}), do: gettext("differs")
  defp block_state_label(_), do: gettext("unchanged")

  # One tag a line, so a diff of rendered HTML reads. Whitespace between
  # tags can show on the page, so it keeps a line of its own (`␣`).
  defp pretty(nil), do: ""

  defp pretty(html) do
    html
    |> String.replace(~r/>(\s*)</, fn match -> if match == "><", do: ">\n<", else: ">\n␣\n<" end)
    |> String.trim()
  end

  ## Apply dialog

  attr :open?, :boolean, required: true
  attr :rows, :list, required: true
  attr :keep_here, :list, required: true
  attr :excluded, :list, required: true
  attr :failures, :integer, required: true
  attr :entries, :map, required: true
  attr :error, :string, default: nil

  def confirm(assigns) do
    renders = Enum.sum(Enum.map(assigns.rows, &assigns.entries[&1.uid].count))
    live = Enum.sum(Enum.map(assigns.rows, &assigns.entries[&1.uid].live))
    updates = Enum.count(assigns.rows, &(&1.status != :create))
    new = Enum.count(assigns.rows, &(&1.status == :create))
    count = length(assigns.rows) + length(assigns.keep_here)
    assigns = assign(assigns, renders: renders, live: live, updates: updates, new: new, count: count)

    ~H"""
    <dialog
      id="release-confirm"
      class="admin-dialog release-confirm"
      aria-labelledby="release-confirm-title"
      phx-hook="Brando.ReleaseDialog"
      data-open={to_string(@open?)}
      data-close="close_confirm"
    >
      <h2 id="release-confirm-title" class="admin-dialog-title">
        {ngettext("Apply 1 module change?", "Apply %{count} module changes?", @count)}
      </h2>
      <div class="admin-dialog-body">
        <p>{scope_line(@updates, @new, @renders, @live)}</p>
        <ul>
          <li :for={row <- @rows}>
            <span>{row_name(row)}{row.children != [] && " + #{length(row.children)}"}</span>
            <span>
              {cond do
                row.status == :create -> gettext("New")
                @entries[row.uid].count == 0 -> gettext("No re-render")
                true -> entries_label(@entries[row.uid].count)
              end}
            </span>
          </li>
          <li :for={row <- @keep_here}>
            <span>{row_name(row)}</span>
            <span>{gettext("Keeps the version here")}</span>
          </li>
        </ul>
        <p :if={@failures > 0} class="release-confirm-warning">
          <.icon name="triangle-alert" />
          <span>
            <strong>{ngettext("1 entry fails to render in Verify.", "%{count} entries fail to render in Verify.", @failures)}</strong>
            {gettext("They keep the HTML they have now until the template or their content is fixed.")}
          </span>
        </p>
        <p :if={@excluded != []} class="release-confirm-excluded">
          {gettext("Not included: %{rows}.", rows: Enum.map_join(@excluded, ", ", &excluded_label/1))}
        </p>
        <p class="release-confirm-undo">{gettext("You can revert this apply until it is kept.")}</p>
        <p :if={@error} class="release-confirm-warning"><.icon name="circle-x" /><span>{@error}</span></p>
      </div>
      <div class="admin-dialog-actions">
        <button class="admin-dialog-button" type="button" phx-click="close_confirm" autofocus={@failures > 0}>
          {gettext("Cancel")}
        </button>
        <button
          class="admin-dialog-button is-primary"
          type="button"
          phx-click="apply"
          phx-disable-with={gettext("Applying…")}
          autofocus={@failures == 0}
          data-testid="release-confirm-apply"
        >
          {if @failures > 0,
            do: ngettext("Apply with 1 failure", "Apply with %{count} failures", @failures),
            else: ngettext("Apply 1 change", "Apply %{count} changes", @count)}
        </button>
      </div>
    </dialog>
    """
  end

  defp scope_line(updates, new, renders, live) do
    changes =
      case {updates, new} do
        {u, 0} ->
          ngettext("Updates 1 module", "Updates %{count} modules", u)

        {0, n} ->
          ngettext("Adds 1 module", "Adds %{count} modules", n)

        {u, n} ->
          ngettext("Updates 1 module", "Updates %{count} modules", u) <> " " <> gettext("and adds %{count}", count: n)
      end

    if renders > 0,
      do:
        changes <> ", " <> gettext("then re-renders %{count} entries, %{live} of them live.", count: renders, live: live),
      else: changes <> "."
  end

  defp excluded_label(%{row: row, why: why}), do: "#{row_name(row)} (#{why})"

  ## Banner

  attr :batch, :map, required: true
  attr :renders, :any, default: nil
  attr :changed_since, :list, default: []
  attr :irreversible, :list, default: []

  def banner(assigns) do
    renders = assigns.renders || %{total: 0, pending: 0, failed: 0, rendered: 0, failures: []}
    items = assigns.batch.definitions["items"] || []
    assigns = assign(assigns, r: renders, items: items, rendering?: renders.pending > 0)

    ~H"""
    <section class={["release-banner", !@rendering? && "is-done"]} role="status" data-testid="release-banner">
      <.icon :if={@rendering?} name="loader-circle" class="spin" />
      <.icon :if={!@rendering?} name="circle-check" />
      <div class="release-banner-body">
        <h2>
          {ngettext("Applied 1 module change", "Applied %{count} module changes", length(@items))}
          <span :if={@rendering?}>· {gettext("re-rendering entries")}</span>
        </h2>
        <p :if={@rendering?}>
          {gettext(
            "The definitions are saved. Entries re-render in the background, and this keeps counting if you leave the page."
          )}
        </p>
        <p :if={!@rendering?}>
          {gettext("Release %{version}, applied by %{name} %{when}.",
            version: @batch.release,
            name: (@batch.applied_by && @batch.applied_by.name) || gettext("the system"),
            when: date(@batch.applied_at)
          )}
          {ngettext("1 entry re-rendered", "%{count} entries re-rendered", @r.rendered)}{if @r.failed > 0,
            do: gettext(" and %{count} failed", count: @r.failed)}.
        </p>
        <.progress
          :if={@r.total > 0 and @rendering?}
          done={@r.rendered}
          failed={@r.failed}
          total={@r.total}
          queued={@r.pending}
        />
        <ul :if={@r.failures != []} class="release-failures">
          <li :for={failure <- @r.failures}>
            <.icon name="circle-x" />
            <span>{failure.label}</span>
            <code>{first_line(failure.error)}</code>
          </li>
        </ul>
        <p :if={!@rendering?}>
          {gettext(
            "Revert restores the versions this apply replaced and re-renders their entries. It stays available until someone keeps the changes or applies the next release."
          )}
        </p>
        <div :for={item <- @irreversible} class="release-banner-conflict" data-testid="release-irreversible">
          <.icon name="triangle-alert" />
          <span>
            <strong>{gettext("%{name} can’t be reverted without a migration", name: item.name || item.uid)}</strong>
            ({item.reason}). {gettext("Revert leaves it as the apply left it.")}
          </span>
        </div>
        <div :for={item <- @changed_since} class="release-banner-conflict">
          <.icon name="triangle-alert" />
          <span>
            <strong>{gettext("%{name} changed here after the apply", name: item.name || item.uid)}</strong>
            ({person(item.edited)}, {date(item.edited && item.edited.at)}). {gettext(
              "Revert leaves it as it is and lists it as a conflict."
            )}
          </span>
        </div>
      </div>
      <div class="release-banner-actions">
        <button
          class="btn"
          type="button"
          disabled={@rendering?}
          phx-click="keep_batch"
          data-confirm-title={gettext("Keep this apply?")}
          data-confirm={gettext("The changes stay, and this apply can no longer be reverted.")}
          data-confirm-ok={gettext("Keep")}
          data-testid="release-keep"
        >
          {gettext("Keep")}
        </button>
        <button
          class="btn"
          type="button"
          disabled={@rendering?}
          phx-click="revert_batch"
          data-confirm-title={gettext("Revert this apply?")}
          data-confirm={
            gettext(
              "The definitions this apply replaced are applied again, and their entries re-render. Definitions changed here since are left as they are."
            )
          }
          data-confirm-ok={gettext("Revert")}
          data-confirm-destructive
          data-testid="release-revert"
        >
          <.icon name="rotate-ccw" />{gettext("Revert…")}
        </button>
      </div>
      <p :if={@rendering?} class="release-banner-hint">
        {gettext("Keep and Revert are available when every entry has rendered.")}
      </p>
    </section>
    """
  end
end
