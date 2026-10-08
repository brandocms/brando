defmodule BrandoAdmin.Sites.SEOLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.SEO
  use Gettext, backend: Brando.Gettext

  alias Brando.AI
  alias Brando.SEO.Analytics
  alias Brando.SEO.Analyze
  alias Brando.SEO.Audit
  alias Brando.SEO.Generate
  alias Brando.SEO.StructuredData
  alias Brando.SEO.Suggestions
  alias Brando.Sites
  alias BrandoAdmin.Components.AIAction
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.SuggestionReview
  alias BrandoAdmin.Components.Workspace

  # Image alt text shares the suggestion queue; it is reviewed in the image library.
  @meta_fields [:meta_description, :meta_title]

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), Suggestions.topic())

    {:ok,
     socket
     |> assign_current_user(token)
     |> assign_entry_id()
     |> assign_404s()
     |> assign_index_now()
     |> assign(:redirect_drafts, MapSet.new())
     |> assign_audit_defaults()
     |> assign(:page_title, gettext("SEO"))}
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] == "content", do: "content", else: "settings"
    socket = assign(socket, :tab, tab)

    if tab == "content" and socket.assigns.audit_status == :idle do
      {:noreply, socket |> start_audit() |> start_structured_data()}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace settings-workspace seo-workspace">
      <Workspace.header
        eyebrow={gettext("Configuration")}
        title={gettext("SEO")}
        subtitle={gettext("Metadata, indexing and redirects for the site, and a review of its content.")}
      />
      <nav class="pill-tabs seo-tabs" aria-label={gettext("SEO sections")}>
        <button type="button" phx-click="tab" phx-value-tab="settings" aria-current={@tab == "settings" && "page"}>
          {gettext("Settings")}
        </button>
        <button type="button" phx-click="tab" phx-value-tab="content" aria-current={@tab == "content" && "page"}>
          {gettext("Content SEO")}
          <.score_badge :if={@audit} score={@audit.score} />
        </button>
      </nav>

      <div :if={@tab == "settings"}>
        <.live_component
          module={Form}
          id="seo_form"
          entry_id={@entry_id}
          current_user={@current_user}
          schema={@schema}
          layout={:settings}
        />

        <.index_now settings={@index_now} live?={@index_now_live?} available?={@index_now_available?} />

        <section class="workspace-panel seo-not-found">
          <header class="workspace-panel-heading">
            <div>
              <h2>{gettext("Not found (404)")}</h2><p>
                {gettext(
                  "Requests for URLs that do not exist, over the last %{days} days. Add a redirect above when a page has moved.",
                  days: @four_oh_four_days
                )}
              </p>
            </div>
          </header>
          <.not_found_lists items={@four_oh_fours} redirect_drafts={@redirect_drafts} />
        </section>
      </div>

      <div :if={@tab == "content"} id="seo-content-audit">
        <.content_audit
          audit={@audit}
          audit_status={@audit_status}
          audit_schemas={@audit_schemas}
          selected_schemas={@selected_schemas}
          include_drafts={@include_drafts}
          expanded={@expanded}
          language={@audit_language}
          ai_available={@ai_available}
          ai_context_fields={@ai_context_fields}
          picker_open={@picker_open}
          generating={@generating}
          suggestions={@suggestions}
          batch_confirm={@batch_confirm}
          accepting_all={@accepting_all}
          critiques={@critiques}
          sort={@sort}
          queries={@queries}
        />
        <.structured_data
          result={@structured_data}
          status={@structured_data_status}
          language={@audit_language}
        />
      </div>
    </div>
    """
  end

  attr :settings, :any, required: true
  attr :live?, :boolean, required: true
  attr :available?, :boolean, required: true

  defp index_now(assigns) do
    ~H"""
    <section class="workspace-panel seo-indexnow" id="seo-indexnow">
      <header class="workspace-panel-heading">
        <div>
          <h2>{gettext("IndexNow")}</h2>
          <p>
            {gettext(
              "Tells Bing, Copilot, Yandex and the search engines that use Bing's index when entries are published, changed, unpublished or deleted, so they visit those pages again soon. Google doesn't take part."
            )}
          </p>
        </div>
        <div class="workspace-heading-actions">
          <button
            :if={@settings}
            type="button"
            class={["workspace-button", !@settings.enabled && "primary"]}
            phx-click="toggle_indexnow"
            disabled={!@available?}
            data-testid="indexnow-toggle"
          >
            {if @settings.enabled, do: gettext("Turn off"), else: gettext("Turn on")}
          </button>
        </div>
      </header>
      <div :if={@settings} class="seo-indexnow-body">
        <dl class="seo-indexnow-facts">
          <div>
            <dt>{gettext("Status")}</dt>
            <dd data-testid="indexnow-status">
              <%= cond do %>
                <% !@available? -> %>
                  {gettext("Off in this deployment's configuration")}
                <% !@settings.enabled -> %>
                  {gettext("Off")}
                <% !@live? -> %>
                  {gettext("On, but this environment is not live, so it doesn't submit")}
                <% true -> %>
                  {gettext("On")}
              <% end %>
            </dd>
          </div>
          <div>
            <dt>{gettext("Last submission")}</dt>
            <dd>
              <%= if @settings.last_submitted_at do %>
                {Brando.Utils.Datetime.format_datetime(@settings.last_submitted_at, "%d/%m/%y, %H:%M")} · {ngettext(
                  "one URL",
                  "%{count} URLs",
                  @settings.last_url_count || 0
                )}
              <% else %>
                {gettext("Nothing submitted yet")}
              <% end %>
            </dd>
          </div>
          <div :if={@settings.last_submitted_at}>
            <dt>{gettext("Response")}</dt>
            <dd class="workspace-mono" data-testid="indexnow-response">
              {response_summary(@settings)}
            </dd>
          </div>
          <div :if={@settings.key}>
            <dt>{gettext("Key file")}</dt>
            <dd>
              <a class="workspace-mono" href={Brando.Utils.hostname("#{@settings.key}.txt")} target="_blank" rel="noopener">
                /{@settings.key}.txt
              </a>
            </dd>
          </div>
        </dl>
      </div>
    </section>
    """
  end

  defp response_summary(%{last_status: nil, last_response: response}), do: response
  defp response_summary(%{last_status: status, last_response: response}), do: "#{status} #{response}"

  attr :items, :list, required: true
  attr :redirect_drafts, :any, required: true

  # Real misses first, where a redirect may help; scanner probes folded away
  # under them, closed by default.
  defp not_found_lists(assigns) do
    {probes, misses} = Enum.split_with(assigns.items, &Brando.Sites.FourOhFour.probe?(&1.url))
    assigns = assign(assigns, probes: probes, misses: misses)

    ~H"""
    <BrandoAdmin.Components.Workspace.empty
      :if={@misses == []}
      title={gettext("No missing URLs recorded")}
      description={gettext("Missing pages will appear here when they are requested.")}
    />
    <.not_found_table
      :if={@misses != []}
      items={@misses}
      label={gettext("Not found (404)")}
      redirectable
      redirect_drafts={@redirect_drafts}
    />
    <details :if={@probes != []} class="seo-not-found-probes">
      <summary>
        {ngettext("%{count} bot probe", "%{count} bot probes", length(@probes), count: length(@probes))}
        <span>
          {gettext("Scanners looking for WordPress, PHP scripts and exposed config files. Nothing to redirect.")}
        </span>
      </summary>
      <.not_found_table items={@probes} label={gettext("Bot probes")} />
    </details>
    """
  end

  attr :items, :list, required: true
  attr :label, :string, required: true
  attr :redirectable, :boolean, default: false
  attr :redirect_drafts, :any, default: MapSet.new()

  defp not_found_table(assigns) do
    ~H"""
    <div class="workspace-table-scroll" tabindex="0" role="region" aria-label={@label}>
      <table class="workspace-table">
        <thead>
          <tr>
            <th>{gettext("URL")}</th><th>{gettext("Hits")}</th><th>{gettext("Last hit")}</th>
            <th :if={@redirectable}><span class="visually-hidden">{gettext("Actions")}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @items}>
            <td>
              <span class="workspace-mono">{item.url}</span>
              <span :if={item[:referrer]} class="seo-not-found-referrer">
                {gettext("Mostly from %{referrer}", referrer: item.referrer)}
              </span>
            </td>
            <td>{item.hits}</td>
            <td>{item.last_hit_at}</td>
            <td :if={@redirectable} class="seo-not-found-action">
              <%= if MapSet.member?(@redirect_drafts, item.url) do %>
                <span class="seo-not-found-added"><.icon name="check" />{gettext("Added above")}</span>
              <% else %>
                <button type="button" class="seo-row-action" phx-click="redirect_404" phx-value-url={item.url}>
                  <.icon name="redo-2" />{gettext("Redirect")}
                </button>
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :score, :integer, default: nil

  defp score_badge(assigns) do
    ~H"""
    <span
      :if={@score}
      class="seo-score-badge"
      data-level={score_level(@score)}
      aria-label={gettext("Score %{score} of 100", score: @score)}
    >
      {@score}
    </span>
    """
  end

  attr :audit, :any
  attr :audit_status, :any
  attr :audit_schemas, :list
  attr :selected_schemas, :list
  attr :include_drafts, :boolean
  attr :expanded, :any
  attr :language, :string
  attr :ai_available, :boolean
  attr :ai_context_fields, :map
  attr :picker_open, :boolean
  attr :generating, :any
  attr :suggestions, :list
  attr :batch_confirm, :boolean
  attr :accepting_all, :boolean
  attr :critiques, :map
  attr :sort, :string
  attr :queries, :map

  defp content_audit(assigns) do
    assigns =
      assigns
      |> assign(:plausible?, source?(assigns.audit, :plausible))
      |> assign(:search_console?, source?(assigns.audit, :search_console))

    ~H"""
    <section class="workspace-panel seo-audit">
      <header class="workspace-panel-heading">
        <div>
          <h2>{gettext("Content SEO")}</h2><p>
            {gettext(
              "Published entries with a page of their own, checked for a meta title and description, an image, a URL and copy shared with other entries. Language: %{language}.",
              language: @language
            )}
          </p>
        </div>
        <div class="workspace-heading-actions">
          <button
            type="button"
            class="workspace-button primary"
            phx-click="rerun_audit"
            disabled={@audit_status == :running}
          >
            {gettext("Run again")}
          </button>
        </div>
      </header>

      <div class="seo-audit-filters" role="group" aria-label={gettext("Content types")}>
        <button
          :for={schema <- @audit_schemas}
          type="button"
          class="seo-chip"
          aria-pressed={to_string(schema in @selected_schemas)}
          phx-click="toggle_schema"
          phx-value-schema={inspect(schema)}
        >
          {Brando.Blueprint.get_plural(schema)}
        </button>
        <button
          type="button"
          class="seo-chip seo-chip-toggle"
          aria-pressed={to_string(@include_drafts)}
          phx-click="toggle_drafts"
        >
          {gettext("Include drafts")}
        </button>
      </div>

      <div :if={@audit && @audit.analytics} class="seo-sources">
        <p>
          {gettext("Traffic from %{sources}, last %{days} days.",
            sources: Enum.map_join(@audit.analytics.sources, ", ", &source_label/1),
            days: @audit.analytics.period_days
          )}
        </p>
        <p :for={{source, error} <- @audit.analytics.errors} class="error" role="alert">
          {gettext("%{source} could not be read: %{error}", source: source_name(source), error: error)}
        </p>
        <div
          :if={@plausible? or @search_console?}
          class="seo-sort"
          role="group"
          aria-label={gettext("Sort entries")}
        >
          <span>{gettext("Sort")}</span>
          <button
            :for={{value, label} <- sort_options(@plausible?, @search_console?)}
            type="button"
            class="seo-chip"
            aria-pressed={to_string(@sort == value)}
            phx-click="sort"
            phx-value-sort={value}
          >
            {label}
          </button>
        </div>
      </div>

      <.context_picker
        :if={@ai_available}
        schemas={@selected_schemas}
        ai_context_fields={@ai_context_fields}
        open={@picker_open}
      />

      <div :if={@audit_status == :running} class="seo-audit-status" role="status" aria-live="polite">
        <span class="seo-spinner" aria-hidden="true"></span>{gettext("Auditing entries…")}
      </div>

      <div :if={match?({:error, _}, @audit_status)} class="seo-audit-status error" role="alert">
        {gettext("The audit could not run.")} {elem(@audit_status, 1)}
      </div>

      <%= if @audit && @audit_status == :done do %>
        <.overview audit={@audit} ai_available={@ai_available} generating={@generating} />

        <.batch
          :if={@ai_available}
          candidates={batch_candidates(@audit, @suggestions)}
          confirm={@batch_confirm}
          max={Suggestions.max_batch()}
        />
        <SuggestionReview.review
          :if={@suggestions != []}
          id="seo-suggestions"
          heading={gettext("Suggested descriptions")}
          suggestions={@suggestions}
          accepting_all={@accepting_all}
          subtitle={&suggestion_schema_name/1}
          label={&gettext("Suggested description for %{title}", title: &1.title)}
        />

        <BrandoAdmin.Components.Workspace.empty
          :if={@audit.rows == []}
          title={gettext("Nothing to audit")}
          description={gettext("No published entries in the selected content types for this language.")}
        />

        <div
          :if={@audit.rows != []}
          class="workspace-table-scroll"
          tabindex="0"
          role="region"
          aria-label={gettext("Audited entries")}
        >
          <table class="workspace-table seo-audit-table">
            <thead>
              <tr>
                <th>{gettext("Entry")}</th>
                <th>{gettext("URL")}</th>
                <th>{gettext("Score")}</th>
                <th :if={@plausible?}>{gettext("Visitors")}</th>
                <th :if={@search_console?}>{gettext("Search")}</th>
                <th>{gettext("Issues")}</th>
                <th><span class="sr-only">{gettext("Details")}</span></th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- sort_rows(@audit.rows, @sort) do %>
                <% key = row_key(row) %>
                <% open? = MapSet.member?(@expanded, key) %>
                <tr class="seo-audit-row" data-open={to_string(open?)}>
                  <td>
                    <strong>{row.title}</strong>
                    <small>{Brando.Blueprint.get_singular(row.schema)}
                    <%= if row.status != :published do %>
                      · {row.status}
                    <% end %></small>
                  </td>
                  <td class="workspace-mono">{row.url || "—"}</td>
                  <td><.score_badge score={row.score} /></td>
                  <td :if={@plausible?} class="seo-number">{figure(row.traffic, :visitors)}</td>
                  <td :if={@search_console?} class="seo-number">
                    {figure(row.traffic, :clicks)}
                    <small :if={(row.traffic || %{})[:impressions]}>
                      {gettext("of %{impressions}", impressions: row.traffic.impressions)}
                    </small>
                  </td>
                  <td>{issues_summary(row)}</td>
                  <td>
                    <button
                      type="button"
                      class="seo-row-toggle"
                      phx-click="toggle_row"
                      phx-value-key={key}
                      aria-expanded={to_string(open?)}
                      aria-controls={"seo-row-#{key}"}
                    >
                      {if open?, do: gettext("Hide"), else: gettext("Details")}
                    </button>
                  </td>
                </tr>
                <tr :if={open?} id={"seo-row-#{key}"} class="seo-audit-details">
                  <td colspan={5 + Enum.count([@plausible?, @search_console?], & &1)}>
                    <div class="seo-audit-details-grid">
                      <div class="seo-check-card">
                        <table class="seo-check-table">
                          <thead>
                            <tr>
                              <th scope="col">{gettext("Check")}</th>
                              <th scope="col">{gettext("Status")}</th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr :for={check <- row.checks} data-status={check.status}>
                              <td class="seo-check-label">
                                {check.label}
                                <small :if={check.status in [:warn, :fail, :skip] and check.hint}>{check.hint}</small>
                              </td>
                              <td class="seo-check-verdict">
                                <span :if={check.value} class="seo-check-value">{check.value}</span>
                                <span class={["seo-check-badge", to_string(check.status)]}>
                                  {status_label(check.status)}
                                </span>
                              </td>
                            </tr>
                          </tbody>
                        </table>
                      </div>
                      <div class="seo-search-preview">
                        <span class="seo-preview-url">{row.url}</span>
                        <div class="seo-preview-title">{row.shown_title || row.title}</div>
                        <p>{row.shown_description || gettext("(no description — the site fallback is shown)")}</p>
                        <div class="seo-preview-actions">
                          <.link class="seo-row-action" navigate={row.schema.__admin_route__(:update, [row.id])}>
                            {gettext("Open entry")}
                          </.link>
                          <AIAction.button
                            :if={@ai_available}
                            phx-click="generate_description"
                            phx-value-key={key}
                            busy={MapSet.member?(@generating, key)}
                            disabled={MapSet.member?(@generating, key)}
                          >
                            <%= if MapSet.member?(@generating, key) do %>
                              {gettext("Writing…")}
                            <% else %>
                              {if row.meta_description, do: gettext("Rewrite description"), else: gettext("Write description")}
                            <% end %>
                          </AIAction.button>
                          <.link
                            :if={warns?(row, :image_alt)}
                            class="seo-row-action"
                            navigate={
                              Brando.routes().admin_live_path(Brando.RuntimeConfig.endpoint(), BrandoAdmin.Images.AltTextLive)
                            }
                          >
                            {gettext("Write alt text")}
                          </.link>
                          <AIAction.button
                            :if={@ai_available and row.meta_description}
                            phx-click="critique"
                            phx-value-key={key}
                            busy={@critiques[key] == :running}
                            disabled={@critiques[key] == :running}
                          >
                            {gettext("Review with AI")}
                          </AIAction.button>
                        </div>
                        <.critique :if={@critiques[key]} critique={@critiques[key]} />
                        <.traffic
                          :if={@plausible? or @search_console?}
                          traffic={row.traffic}
                          plausible?={@plausible?}
                          search_console?={@search_console?}
                          queries={@queries[key]}
                        />
                      </div>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>
    """
  end

  attr :result, :any
  attr :status, :any
  attr :language, :string

  @structured_data_rows 50

  # Site-wide: every content type with a JSON-LD mapping, whatever the chips
  # above select. Each row opens the entry with its Structured data tab.
  defp structured_data(assigns) do
    assigns = assign(assigns, :max_rows, @structured_data_rows)

    ~H"""
    <section class="workspace-panel seo-structured-data" id="seo-structured-data">
      <header class="workspace-panel-heading">
        <div>
          <h2>{gettext("Structured data")}</h2><p>
            {gettext(
              "Published entries of every content type with a JSON-LD mapping, checked against what Google requires (errors) and recommends (warnings). Language: %{language}.",
              language: @language
            )}
          </p>
        </div>
      </header>

      <div :if={@status == :running} class="seo-audit-status" role="status" aria-live="polite">
        <span class="seo-spinner" aria-hidden="true"></span>{gettext("Checking structured data…")}
      </div>

      <div :if={match?({:error, _}, @status)} class="seo-audit-status error" role="alert">
        {gettext("The structured data could not be checked.")} {elem(@status, 1)}
      </div>

      <%= if @result && @status == :done do %>
        <div class="seo-audit-overview">
          <dl class="seo-stats seo-structured-data-stats">
            <div class="seo-stat">
              <dt>{gettext("Checked")}</dt>
              <dd>{@result.checked}</dd>
            </div>
            <div class="seo-stat" data-warn={to_string(@result.with_errors > 0)} data-testid="structured-data-errors">
              <dt>{gettext("With errors")}</dt>
              <dd>{@result.with_errors}</dd>
            </div>
            <div class="seo-stat" data-warn={to_string(@result.with_warnings > 0)} data-testid="structured-data-warnings">
              <dt>{gettext("With warnings only")}</dt>
              <dd>{@result.with_warnings}</dd>
            </div>
          </dl>
        </div>

        <BrandoAdmin.Components.Workspace.empty
          :if={@result.rows == []}
          title={gettext("No structured data issues")}
          description={gettext("Every checked entry has what Google requires and recommends.")}
        />

        <div
          :if={@result.rows != []}
          class="workspace-table-scroll"
          tabindex="0"
          role="region"
          aria-label={gettext("Entries with structured data issues")}
        >
          <table class="workspace-table seo-structured-data-table">
            <thead>
              <tr>
                <th>{gettext("Entry")}</th>
                <th>{gettext("Type")}</th>
                <th>{gettext("Errors")}</th>
                <th>{gettext("Warnings")}</th>
                <th>{gettext("First issue")}</th>
                <th><span class="visually-hidden">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- Enum.take(@result.rows, @max_rows)} class="seo-structured-data-row">
                <td>
                  <strong>{row.title}</strong>
                  <small>{Brando.Blueprint.get_singular(row.schema)}</small>
                </td>
                <td class="workspace-mono">{row.type || "—"}</td>
                <td class="seo-number" data-warn={to_string(row.errors > 0)}>{row.errors}</td>
                <td class="seo-number">{row.warnings}</td>
                <td class="seo-structured-data-issue">{first_issue(row)}</td>
                <td>
                  <a :if={row.admin_url} class="seo-row-action" href={row.admin_url}>
                    {gettext("Open structured data")}
                  </a>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="seo-structured-data-meta">
          <span :if={length(@result.rows) > @max_rows}>
            {gettext("Showing %{shown} of %{count} entries with issues, most errors first.",
              shown: @max_rows,
              count: length(@result.rows)
            )}
          </span>
          {gettext("Checked in %{ms} ms. Kept for ten minutes; Run again checks again.", ms: @result.duration_ms)}
        </p>
      <% end %>
    </section>
    """
  end

  defp first_issue(%{issues: [issue | _]}),
    do: BrandoAdmin.Components.Form.StructuredData.describe_issue(issue)

  defp first_issue(_row), do: "—"

  attr :candidates, :list
  attr :confirm, :boolean
  attr :max, :integer

  # Bulk writing asks first: every entry is a paid request, and the count and
  # the cap should be read before anything is sent.
  defp batch(assigns) do
    assigns = assign(assigns, :count, min(length(assigns.candidates), assigns.max))

    ~H"""
    <div :if={@candidates != []} class="seo-batch" id="seo-batch">
      <p :if={!@confirm}>
        {ngettext(
          "One entry has no meta description.",
          "%{count} entries have no meta description.",
          length(@candidates)
        )}
      </p>
      <p :if={@confirm}>
        {ngettext(
          "Writes a description for one entry. Nothing is saved until you accept it.",
          "Writes descriptions for %{count} entries. Nothing is saved until you accept them.",
          @count
        )}
        <span :if={length(@candidates) > @max}>
          {gettext("At most %{max} per run; run it again for the rest.", max: @max)}
        </span>
      </p>
      <div class="seo-batch-actions">
        <AIAction.button :if={!@confirm} phx-click="confirm_batch">
          {gettext("Write missing descriptions")}
        </AIAction.button>
        <AIAction.button :if={@confirm} variant={:primary} phx-click="start_batch">
          {ngettext("Write one description", "Write %{count} descriptions", @count)}
        </AIAction.button>
        <button :if={@confirm} type="button" class="workspace-button" phx-click="cancel_batch">
          {gettext("Cancel")}
        </button>
      </div>
    </div>
    """
  end

  attr :traffic, :map
  attr :plausible?, :boolean
  attr :search_console?, :boolean
  attr :queries, :any

  defp traffic(assigns) do
    ~H"""
    <div class="seo-traffic">
      <dl>
        <div :if={@plausible?}>
          <dt>{gettext("Visitors")}</dt>
          <dd>{figure(@traffic, :visitors)}</dd>
        </div>
        <div :if={@search_console?}>
          <dt>{gettext("Search impressions")}</dt>
          <dd>{figure(@traffic, :impressions)}</dd>
        </div>
        <div :if={@search_console?}>
          <dt>{gettext("Clicks")}</dt>
          <dd>{figure(@traffic, :clicks)}</dd>
        </div>
        <div :if={@search_console? and @traffic[:impressions]}>
          <dt>{gettext("Click-through")}</dt>
          <dd>{Brando.SEO.Checks.percent(@traffic.ctr)}</dd>
        </div>
        <div :if={@search_console? and @traffic[:impressions]}>
          <dt>{gettext("Average position")}</dt>
          <dd>{:erlang.float_to_binary(@traffic.position / 1, decimals: 1)}</dd>
        </div>
      </dl>
      <div :if={@search_console?} class="seo-queries">
        <h4>{gettext("Top searches")}</h4>
        <%= case @queries do %>
          <% {:ok, []} -> %>
            <p>{gettext("Google has not shown this page for any search in the period.")}</p>
          <% {:ok, queries} -> %>
            <table>
              <thead>
                <tr>
                  <th scope="col">{gettext("Search")}</th>
                  <th scope="col">{gettext("Impressions")}</th>
                  <th scope="col">{gettext("Clicks")}</th>
                  <th scope="col">{gettext("Position")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={query <- queries}>
                  <td>{query.query}</td>
                  <td>{query.impressions}</td>
                  <td>{query.clicks}</td>
                  <td>{:erlang.float_to_binary(query.position / 1, decimals: 1)}</td>
                </tr>
              </tbody>
            </table>
          <% {:error, message} -> %>
            <p class="error">{message}</p>
          <% _ -> %>
            <p><span class="seo-spinner" aria-hidden="true"></span>{gettext("Loading searches…")}</p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :critique, :any

  defp critique(assigns) do
    ~H"""
    <div class={["seo-critique", match?({:ok, _}, @critique) && "ai-proposal"]} role="status" aria-live="polite">
      <%= case @critique do %>
        <% :running -> %>
          <p><span class="seo-spinner" aria-hidden="true"></span>{gettext("Reviewing…")}</p>
        <% {:ok, points} -> %>
          <h4 class="ai-proposal-label"><.icon name="sparkles" />{gettext("AI review")}</h4>
          <ul>
            <li :for={point <- points}>{point}</li>
          </ul>
        <% {:error, message} -> %>
          <p class="error">{message}</p>
      <% end %>
    </div>
    """
  end

  attr :schemas, :list
  attr :ai_context_fields, :map
  attr :open, :boolean

  # Open state lives on the server rather than in a `<details>`: picking a field
  # patches the chips, and a browser-held `open` does not survive that.
  defp context_picker(assigns) do
    ~H"""
    <div class="seo-context-picker">
      <button
        type="button"
        class="seo-context-summary"
        phx-click="toggle_picker"
        aria-expanded={to_string(@open)}
        aria-controls="seo-context-fields"
      >
        {gettext("What the AI reads")}
      </button>
      <div :if={@open} id="seo-context-fields">
        <p>
          {gettext(
            "The entry fields a generated description is written from. Block fields are read from the last rendered version of the entry."
          )}
        </p>
        <p :if={AI.model_spec(AI.field_ai_opts(:meta_description))} class="seo-context-model">
          {gettext("Written by %{model}.", model: AI.model_spec(AI.field_ai_opts(:meta_description)))}
        </p>
        <div :for={schema <- @schemas} class="seo-context-schema">
          <h4>{Brando.Blueprint.get_plural(schema)}</h4>
          <div class="seo-audit-filters" role="group" aria-label={Brando.Blueprint.get_plural(schema)}>
            <button
              :for={field <- AI.Context.available_fields(schema)}
              type="button"
              class="seo-chip"
              aria-pressed={to_string(field in Map.get(@ai_context_fields, schema, []))}
              phx-click="toggle_context_field"
              phx-value-schema={inspect(schema)}
              phx-value-field={field}
            >
              {field}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :audit, :any
  attr :ai_available, :boolean, default: false
  attr :generating, :any, default: MapSet.new()

  defp overview(assigns) do
    ~H"""
    <div class="seo-audit-overview">
      <dl class="seo-stats">
        <div class="seo-stat">
          <dt>{gettext("Score")}</dt>
          <dd><.score_badge score={@audit.score} /><span :if={!@audit.score}>—</span></dd>
        </div>
        <div class="seo-stat">
          <dt>{gettext("Audited")}</dt>
          <dd>{length(@audit.rows)}</dd>
        </div>
        <div class="seo-stat" data-warn={to_string(@audit.missing_descriptions > 0)}>
          <dt>{gettext("Missing description")}</dt>
          <dd>{@audit.missing_descriptions}</dd>
        </div>
        <div class="seo-stat" data-warn={to_string(@audit.missing_images > 0)}>
          <dt>{gettext("Missing image")}</dt>
          <dd>{@audit.missing_images}</dd>
        </div>
        <div class="seo-stat" data-warn={to_string(@audit.missing_urls > 0)}>
          <dt>{gettext("No URL")}</dt>
          <dd>{@audit.missing_urls}</dd>
        </div>
        <div class="seo-stat" data-warn={to_string(@audit.thin_content > 0)}>
          <dt>{gettext("Thin content")}</dt>
          <dd>{@audit.thin_content}</dd>
        </div>
        <div :if={source?(@audit, :plausible)} class="seo-stat" data-warn={to_string(@audit.unvisited > 0)}>
          <dt>{gettext("Not visited")}</dt>
          <dd>{@audit.unvisited}</dd>
        </div>
        <div :if={source?(@audit, :search_console)} class="seo-stat" data-warn={to_string(@audit.low_click_through > 0)}>
          <dt>{gettext("Low click-through")}</dt>
          <dd>{@audit.low_click_through}</dd>
        </div>
        <div class="seo-stat">
          <dt>{gettext("Sitemap")}</dt>
          <dd data-text>{if @audit.sitemap?, do: gettext("checked"), else: gettext("not generated")}</dd>
        </div>
      </dl>

      <div :if={@audit.redirect_suggestions != []} class="seo-redirects">
        <h3>{gettext("Missing redirects")}</h3>
        <p>
          {gettext(
            "Requested URLs that no longer exist but match an entry's slug. Creating a redirect adds it to the settings."
          )}
        </p>
        <table class="workspace-table seo-redirects-table">
          <thead>
            <tr>
              <th>{gettext("Requested")}</th><th>{gettext("Hits")}</th><th>{gettext("Suggested destination")}</th><th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={suggestion <- @audit.redirect_suggestions}>
              <td class="workspace-mono seo-redirect-url">{suggestion.url}</td>
              <td class="seo-redirect-hits" data-label={gettext("Hits")}>{suggestion.hits}</td>
              <td class="seo-redirect-to">
                <strong>{suggestion.title}</strong>
                <small class="workspace-mono">{suggestion.to}</small>
                <small :if={suggestion.confidence == :close}>{gettext("Close match — check before creating")}</small>
              </td>
              <td class="seo-redirect-action">
                <button
                  type="button"
                  class="seo-row-action"
                  phx-click="create_redirect"
                  phx-value-from={suggestion.url}
                  phx-value-to={suggestion.to}
                >
                  {gettext("Create redirect")}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@audit.duplicate_descriptions != [] or @audit.duplicate_titles != []} class="seo-duplicates">
        <h3>{gettext("Duplicates")}</h3>
        <.duplicate_group
          :for={{value, rows} <- @audit.duplicate_descriptions}
          kind={gettext("Same description")}
          field="meta_description"
          action={gettext("Write a new description")}
          value={value}
          rows={rows}
          ai_available={@ai_available}
          generating={@generating}
        />
        <.duplicate_group
          :for={{value, rows} <- @audit.duplicate_titles}
          kind={gettext("Same title")}
          field="meta_title"
          action={gettext("Write a new title")}
          value={value}
          rows={rows}
          ai_available={@ai_available}
          generating={@generating}
        />
      </div>
    </div>
    """
  end

  attr :kind, :string
  attr :field, :string
  attr :action, :string
  attr :value, :string
  attr :rows, :list
  attr :ai_available, :boolean
  attr :generating, :any

  # One card per shared value: what is shared and how widely, the text itself
  # (clamped, in full on hover), then a row per entry to go and fix it. Each
  # entry can have its copy rewritten on its own, so one can keep the text
  # while the others get new; a rewritten entry drops out on the re-audit.
  defp duplicate_group(assigns) do
    ~H"""
    <section class="seo-duplicate">
      <header>
        <h4>{@kind}</h4>
        <span class="workspace-badge warning">
          {ngettext("%{count} entry", "%{count} entries", length(@rows))}
        </span>
      </header>
      <blockquote title={@value}>{@value}</blockquote>
      <ul>
        <li :for={row <- @rows}>
          <div>
            <.link navigate={row.schema.__admin_route__(:update, [row.id])}>{row.title}</.link>
            <small>
              {Brando.Blueprint.get_singular(row.schema)}<span :if={row.url}> · <code>{row.url}</code></span>
            </small>
          </div>
          <div class="seo-duplicate-actions">
            <AIAction.button
              :if={@ai_available}
              phx-click="generate_description"
              phx-value-key={row_key(row)}
              phx-value-field={@field}
              busy={MapSet.member?(@generating, row_key(row))}
              disabled={MapSet.member?(@generating, row_key(row))}
            >
              {if MapSet.member?(@generating, row_key(row)), do: gettext("Writing…"), else: @action}
            </AIAction.button>
            <.link class="seo-row-action" navigate={row.schema.__admin_route__(:update, [row.id])}>
              {gettext("Open entry")}
            </.link>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(settings content) do
    {:noreply, push_patch(socket, to: Brando.routes().admin_live_path(socket, __MODULE__, tab: tab))}
  end

  def handle_event("toggle_indexnow", _params, socket) do
    result = if socket.assigns.index_now.enabled, do: Brando.IndexNow.disable(), else: Brando.IndexNow.enable()

    case result do
      {:ok, settings} ->
        message = if settings.enabled, do: gettext("IndexNow is on"), else: gettext("IndexNow is off")
        send(self(), {:toast, message})
        {:noreply, assign(socket, :index_now, settings)}

      {:error, _changeset} ->
        send(self(), {:toast, gettext("Could not change IndexNow")})
        {:noreply, socket}
    end
  end

  def handle_event("toggle_schema", %{"schema" => schema}, socket) do
    schema = Enum.find(socket.assigns.audit_schemas, &(inspect(&1) == schema))
    selected = socket.assigns.selected_schemas

    selected =
      cond do
        is_nil(schema) -> selected
        schema in selected -> List.delete(selected, schema)
        true -> selected ++ [schema]
      end

    {:noreply, socket |> assign(:selected_schemas, selected) |> start_audit()}
  end

  def handle_event("toggle_drafts", _params, socket) do
    {:noreply, socket |> update(:include_drafts, &(!&1)) |> start_audit()}
  end

  def handle_event("rerun_audit", _params, socket) do
    {:noreply,
     socket
     |> assign(:queries, %{})
     |> start_audit(refresh_analytics: true)
     |> start_structured_data(refresh: true)}
  end

  def handle_event("sort", %{"sort" => sort}, socket) when sort in ~w(score visitors impressions) do
    {:noreply, assign(socket, :sort, sort)}
  end

  # Adds the 404 to the redirects in the form above as a new, unsaved row, so
  # the editor picks where it goes and saves it with the form. Written into
  # the form rather than the database: the form holds the redirects too, and
  # its next save would drop a row it never saw. The destination is filled in
  # when the content audit already matched the URL to an entry.
  def handle_event("redirect_404", %{"url" => url}, socket) do
    to =
      case socket.assigns.audit do
        %{redirect_suggestions: suggestions} -> Enum.find_value(suggestions, &(&1.url == url && &1.to))
        _ -> nil
      end

    send_update(Form,
      id: "seo_form",
      event: "append_embed",
      field: :redirects,
      attrs: %{from: url, to: to || "", code: 301},
      focus: :to
    )

    {:noreply, update(socket, :redirect_drafts, &MapSet.put(&1, url))}
  end

  def handle_event("create_redirect", %{"from" => from, "to" => to}, socket) do
    %{current_user: user, audit_language: language, audit: audit} = socket.assigns

    case create_redirect(from, to, language, user) do
      {:ok, _seo} ->
        Brando.Sites.FourOhFour.remove(from)
        remaining = Enum.reject(audit.redirect_suggestions, &(&1.url == from))
        send(self(), {:toast, gettext("Redirect created")})

        {:noreply,
         socket
         |> assign(:audit, %{audit | redirect_suggestions: remaining})
         |> assign(:four_oh_fours, Brando.Sites.FourOhFour.list())}

      {:error, _changeset} ->
        send(self(), {:toast, gettext("Could not create the redirect")})
        {:noreply, socket}
    end
  end

  def handle_event("toggle_picker", _params, socket) do
    {:noreply, update(socket, :picker_open, &(!&1))}
  end

  def handle_event("toggle_context_field", %{"schema" => schema, "field" => field}, socket) do
    %{ai_context_fields: context_fields, current_user: user, audit_language: language} = socket.assigns
    schema = Enum.find(socket.assigns.audit_schemas, &(inspect(&1) == schema))
    field = field |> AI.Context.normalize_fields() |> List.first()

    if schema && field in AI.Context.available_fields(schema) do
      selected = Map.get(context_fields, schema, [])
      selected = if field in selected, do: List.delete(selected, field), else: selected ++ [field]

      case Generate.store_context_fields(schema, language, selected, user) do
        {:ok, _seo} ->
          # Re-read rather than trusting `selected`: clearing a schema's pick
          # entirely drops back to what its blueprint declares, and the chips
          # should show what the prompt will actually read.
          {:noreply, assign_ai_context_fields(socket, socket.assigns.audit_schemas)}

        {:error, _} ->
          send(self(), {:toast, gettext("Could not store the AI context fields")})
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Writes the meta description, or the meta title when a duplicate-title card
  # asks for one.
  def handle_event("generate_description", %{"key" => key} = params, socket) do
    %{audit: audit, current_user: user, ai_available: available?} = socket.assigns
    row = audit && Enum.find(audit.rows, &(row_key(&1) == key))
    field = if params["field"] == "meta_title", do: :meta_title, else: :meta_description

    if available? and row do
      fields = Map.get(socket.assigns.ai_context_fields, row.schema)
      run = fn -> generate_field(row, field, user, fields) end

      {:noreply,
       socket
       |> update(:generating, &MapSet.put(&1, key))
       |> start_async({:generate, key}, in_captured_context(socket, run))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("critique", %{"key" => key}, socket) do
    %{audit: audit, ai_available: available?} = socket.assigns
    row = audit && Enum.find(audit.rows, &(row_key(&1) == key))

    if available? and row do
      search_console? = source?(audit, :search_console)

      # The searches a page is found by say more about what its description
      # should promise than anything on the page itself.
      run = fn -> Analyze.critique(row.schema, row.id, queries: critique_queries(row, search_console?)) end

      {:noreply,
       socket
       |> update(:critiques, &Map.put(&1, key, :running))
       |> start_async({:critique, key}, in_captured_context(socket, run))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_batch", _params, socket), do: {:noreply, assign(socket, :batch_confirm, true)}
  def handle_event("cancel_batch", _params, socket), do: {:noreply, assign(socket, :batch_confirm, false)}

  def handle_event("start_batch", _params, socket) do
    %{audit: audit, suggestions: suggestions, audit_language: language, current_user: user} = socket.assigns

    if socket.assigns.ai_available and audit do
      {:ok, count} = Suggestions.enqueue(batch_candidates(audit, suggestions), language, user)
      send(self(), {:toast, ngettext("Writing one description", "Writing %{count} descriptions", count)})
      {:noreply, socket |> assign(:batch_confirm, false) |> assign_suggestions()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("accept_suggestion", %{"suggestion_id" => id} = params, socket) do
    case Suggestions.accept(id, params["text"], socket.assigns.current_user) do
      {:ok, suggestion} ->
        send(self(), {:toast, gettext("Description saved")})
        {:noreply, socket |> forget_critique(suggestion) |> assign_suggestions() |> start_audit()}

      {:error, reason} ->
        send(self(), {:toast, save_error(reason)})
        {:noreply, assign_suggestions(socket)}
    end
  end

  def handle_event("reject_suggestion", %{"id" => id}, socket) do
    Suggestions.reject(id, socket.assigns.current_user)
    {:noreply, assign_suggestions(socket)}
  end

  def handle_event("accept_all_suggestions", _params, socket) do
    %{audit_language: language, current_user: user} = socket.assigns
    run = fn -> Suggestions.accept_all(language, user, @meta_fields) end

    {:noreply,
     socket
     |> assign(:accepting_all, true)
     |> start_async(:accept_all, in_captured_context(socket, run))}
  end

  def handle_event("toggle_row", %{"key" => key}, socket) do
    expanded = socket.assigns.expanded

    if MapSet.member?(expanded, key) do
      {:noreply, assign(socket, :expanded, MapSet.delete(expanded, key))}
    else
      {:noreply, socket |> assign(:expanded, MapSet.put(expanded, key)) |> load_queries(key)}
    end
  end

  def handle_async(:audit, {:ok, %Audit.Result{} = result}, socket) do
    # Row keys are the schema and id, so an expanded row survives a re-run —
    # which is what you want after generating a description from inside it.
    {:noreply, assign(socket, audit: result, audit_status: :done)}
  end

  def handle_async(:audit, {:exit, reason}, socket) do
    {:noreply, assign(socket, audit_status: {:error, Exception.format_exit(reason)})}
  end

  def handle_async(:structured_data, {:ok, %StructuredData.Result{} = result}, socket) do
    {:noreply, assign(socket, structured_data: result, structured_data_status: :done)}
  end

  def handle_async(:structured_data, {:exit, reason}, socket) do
    {:noreply, assign(socket, structured_data_status: {:error, Exception.format_exit(reason)})}
  end

  # The entry is written before the audit re-runs, so the row picks the new
  # description up from the database rather than from the reply.
  def handle_async({:generate, key}, {:ok, {:ok, generated}}, socket) do
    message = if generated[:field] == :meta_title, do: gettext("Title written"), else: gettext("Description written")
    send(self(), {:toast, message})

    {:noreply,
     socket
     |> update(:generating, &MapSet.delete(&1, key))
     |> update(:critiques, &Map.delete(&1, key))
     |> start_audit()}
  end

  def handle_async({:generate, key}, {:ok, {:error, reason}}, socket) do
    message = if match?(%Ecto.Changeset{}, reason), do: save_error(reason), else: AI.error_message(reason)
    send(self(), {:toast, message})
    {:noreply, update(socket, :generating, &MapSet.delete(&1, key))}
  end

  def handle_async({:generate, key}, {:exit, _reason}, socket) do
    send(self(), {:toast, AI.error_message(:failed)})
    {:noreply, update(socket, :generating, &MapSet.delete(&1, key))}
  end

  def handle_async({:queries, key}, {:ok, result}, socket) do
    result = if result == :not_configured, do: {:ok, []}, else: result
    {:noreply, update(socket, :queries, &Map.put(&1, key, result))}
  end

  def handle_async({:queries, key}, {:exit, _reason}, socket) do
    {:noreply, update(socket, :queries, &Map.put(&1, key, {:error, gettext("Could not read the searches")}))}
  end

  def handle_async({:critique, key}, {:ok, {:ok, points}}, socket) do
    {:noreply, update(socket, :critiques, &Map.put(&1, key, {:ok, points}))}
  end

  def handle_async({:critique, key}, {:ok, {:error, reason}}, socket) do
    {:noreply, update(socket, :critiques, &Map.put(&1, key, {:error, AI.error_message(reason)}))}
  end

  def handle_async({:critique, key}, {:exit, _reason}, socket) do
    {:noreply, update(socket, :critiques, &Map.put(&1, key, {:error, AI.error_message(:failed)}))}
  end

  def handle_async(:accept_all, result, socket) do
    case result do
      {:ok, {accepted, 0}} ->
        send(self(), {:toast, ngettext("One description saved", "%{count} descriptions saved", accepted)})

      {:ok, {accepted, failed}} ->
        send(
          self(),
          {:toast, gettext("%{accepted} saved, %{failed} could not be saved", accepted: accepted, failed: failed)}
        )

      {:exit, _reason} ->
        send(self(), {:toast, gettext("Could not save the descriptions")})
    end

    {:noreply, socket |> assign(:accepting_all, false) |> assign_suggestions() |> start_audit()}
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  # Read from the database, so only once the socket is connected.
  defp assign_404s(socket) do
    socket
    |> assign(:four_oh_fours, if(connected?(socket), do: Brando.Sites.FourOhFour.list(), else: []))
    |> assign(:four_oh_four_days, Brando.Sites.FourOhFour.retention_days())
  end

  # Read from the database, so only once the socket is connected.
  defp assign_index_now(socket) do
    socket
    |> assign(:index_now, if(connected?(socket), do: Brando.IndexNow.settings()))
    |> assign(:index_now_live?, Brando.IndexNow.live_environment?())
    |> assign(:index_now_available?, Brando.IndexNow.available?())
  end

  defp assign_audit_defaults(socket) do
    schemas = Audit.schemas()
    default = if Brando.Pages.Page in schemas, do: [Brando.Pages.Page], else: schemas

    socket
    |> assign(:tab, "settings")
    |> assign(:audit, nil)
    |> assign(:audit_sandbox, sandbox_owner(socket))
    |> assign(:audit_status, :idle)
    |> assign(:structured_data, nil)
    |> assign(:structured_data_status, :idle)
    |> assign(:audit_schemas, schemas)
    |> assign(:selected_schemas, default)
    |> assign(:include_drafts, false)
    |> assign(:expanded, MapSet.new())
    |> assign(:generating, MapSet.new())
    |> assign(:critiques, %{})
    |> assign(:sort, "score")
    |> assign(:queries, %{})
    |> assign(:suggestions, [])
    |> assign(:batch_confirm, false)
    |> assign(:accepting_all, false)
    |> assign(:ai_available, AI.configured?())
    |> assign(:picker_open, false)
    |> assign(:audit_language, content_language(socket))
    |> assign_ai_context_fields(schemas)
  end

  # What a generated description is written from, per schema: the site's stored
  # pick, or the blueprint's own declaration until someone changes it here.
  defp assign_ai_context_fields(socket, schemas) do
    assign(socket, :ai_context_fields, Generate.context_field_map(schemas, content_language(socket)))
  end

  # The audit runs in a task, which starts without this process's context:
  # the tenant prefix, the authorization scope the reads must be made under,
  # the Gettext locale the check labels are translated in, and — on a
  # sandboxed e2e server — the SQL sandbox owner. Carry all four across.
  defp start_audit(socket, opts \\ []) do
    language = content_language(socket)
    schemas = socket.assigns.selected_schemas
    include_drafts? = socket.assigns.include_drafts
    refresh? = Keyword.get(opts, :refresh_analytics, false)

    run = fn ->
      Audit.run(language, schemas: schemas, include_drafts: include_drafts?, refresh_analytics: refresh?)
    end

    socket
    |> assign(:audit_status, :running)
    |> assign(:audit_language, language)
    |> assign_suggestions()
    |> start_async(:audit, in_captured_context(socket, run))
  end

  # Site-wide and cached for ten minutes (`Brando.SEO.StructuredData`), so
  # opening the tab again within that time reads the cache.
  defp start_structured_data(socket, opts \\ []) do
    language = content_language(socket)
    refresh? = Keyword.get(opts, :refresh, false)
    run = fn -> StructuredData.run(language, refresh: refresh?) end

    socket
    |> assign(:structured_data_status, :running)
    |> start_async(:structured_data, in_captured_context(socket, run))
  end

  defp assign_suggestions(socket) do
    assign(socket, :suggestions, Suggestions.list_open(socket.assigns.audit_language, @meta_fields))
  end

  # Entries with no description of their own, less those a suggestion is
  # already on its way for or waiting on review.
  defp batch_candidates(audit, suggestions) do
    waiting = MapSet.new(suggestions, &{&1.schema, &1.entry_id})

    Enum.filter(audit.rows, fn row ->
      not MapSet.member?(waiting, {inspect(row.schema), row.id}) and
        Enum.any?(row.checks, &(&1.key == :meta_description_present and &1.status == :fail))
    end)
  end

  defp forget_critique(socket, suggestion) do
    key = "#{String.replace(suggestion.schema, ".", "-")}-#{suggestion.entry_id}"
    update(socket, :critiques, &Map.delete(&1, key))
  end

  defp suggestion_schema_name(suggestion) do
    case Brando.SEO.Suggestion.schema_module(suggestion) do
      nil -> suggestion.schema
      schema -> Brando.Blueprint.get_singular(schema)
    end
  end

  # Search Console is asked for a page's searches only when the row opens:
  # one request each, cached for an hour.
  defp load_queries(socket, key) do
    %{audit: audit, queries: queries} = socket.assigns
    row = audit && Enum.find(audit.rows, &(row_key(&1) == key))

    if row && row.url && source?(audit, :search_console) && not Map.has_key?(queries, key) do
      page = row.traffic || row.url

      socket
      |> update(:queries, &Map.put(&1, key, :loading))
      |> start_async({:queries, key}, in_captured_context(socket, fn -> Analytics.top_queries(page) end))
    else
      socket
    end
  end

  defp generate_field(row, field, user, context_fields) do
    with {:ok, generated} <- Generate.generate(row.schema, row.id, field, user, context_fields: context_fields) do
      {:ok, Map.put(generated, :field, field)}
    end
  end

  defp critique_queries(row, search_console?) do
    case search_console? && Analytics.top_queries(row.traffic || row.url) do
      {:ok, queries} -> queries
      _ -> []
    end
  end

  defp warns?(row, key), do: Enum.any?(row.checks, &(&1.key == key and &1.status in [:warn, :fail]))

  defp source?(%{analytics: %{sources: sources}}, source), do: Enum.any?(sources, &(&1.source == source))
  defp source?(_audit, _source), do: false

  defp source_name(:plausible), do: "Plausible"
  defp source_name(:search_console), do: "Google Search Console"

  defp source_label(%{source: source, target: target}), do: "#{source_name(source)} (#{target})"

  defp sort_options(plausible?, search_console?) do
    [{"score", gettext("Lowest score")}] ++
      if(plausible?, do: [{"visitors", gettext("Most visited")}], else: []) ++
      if(search_console?, do: [{"impressions", gettext("Most seen in search")}], else: [])
  end

  # Busy pages with a poor score first is the order worth fixing in; the
  # audit's own order (lowest score) stays the default.
  defp sort_rows(rows, "score"), do: rows

  defp sort_rows(rows, field) do
    field = String.to_existing_atom(field)
    Enum.sort_by(rows, &{-((&1.traffic || %{})[field] || 0), &1.score || 0})
  end

  defp figure(nil, _field), do: "—"
  defp figure(traffic, field), do: traffic |> Map.get(field) |> then(&if(is_nil(&1), do: "—", else: to_string(&1)))

  defp save_error(:not_found), do: gettext("This suggestion was already reviewed")
  defp save_error(:empty), do: gettext("Write a description before accepting it")

  # The entry's own validation still applies, so an entry saved before a field
  # became required cannot take a description until that field is filled in.
  defp save_error(%Ecto.Changeset{errors: errors}) do
    fields = errors |> Keyword.keys() |> Enum.uniq() |> Enum.join(", ")
    gettext("The entry cannot be saved until these fields are fixed: %{fields}", fields: fields)
  end

  defp save_error(_), do: gettext("Could not save the description")

  defp in_captured_context(socket, fun) do
    scope = Brando.Authorization.Boundary.current_scope()
    locale = Gettext.get_locale(Brando.Gettext)
    sandbox = socket.assigns.audit_sandbox

    Brando.Tenant.capture_context(fn ->
      if sandbox, do: Phoenix.Ecto.SQL.Sandbox.allow(sandbox, Ecto.Adapters.SQL.Sandbox)
      Gettext.with_locale(Brando.Gettext, locale, fn -> Brando.Authorization.Boundary.with_scope(scope, fun) end)
    end)
  end

  defp sandbox_owner(socket) do
    if Application.get_env(Brando.otp_app(), :sql_sandbox, false) && connected?(socket) do
      get_connect_info(socket, :user_agent)
    end
  end

  defp content_language(%{assigns: %{current_user: %{config: %{content_language: language}}}}), do: to_string(language)
  defp content_language(_socket), do: to_string(Brando.config(:default_language))

  defp assign_entry_id(%{assigns: %{current_user: %{config: %{content_language: content_language}}}} = socket) do
    case Sites.get_seo(%{matches: %{language: content_language}}) do
      {:ok, seo} ->
        assign(socket, :entry_id, seo.id)

      {:error, _} ->
        first_seo = List.first(Sites.list_seos!())

        {:ok, seo} =
          Sites.duplicate_seo(first_seo.id, :system, merge_fields: %{language: content_language})

        assign(socket, :entry_id, seo.id)
    end
  end

  # Appends to the embedded redirects through a changeset so the existing
  # rows keep their identity instead of being re-cast from params.
  defp create_redirect(from, to, language, user) do
    with {:ok, seo} <- Sites.get_seo(%{matches: %{language: language}}) do
      redirects = (seo.redirects || []) ++ [%Brando.Sites.Redirect{from: from, to: to, code: 301}]

      seo
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:redirects, redirects)
      |> Sites.update_seo(user)
    end
  end

  defp row_key(row), do: "#{row.schema |> inspect() |> String.replace(".", "-")}-#{row.id}"

  defp issues_summary(row) do
    failing = Enum.filter(row.checks, &(&1.status in [:fail, :warn]))

    case failing do
      [] -> gettext("None")
      [check] -> check.label
      [check | rest] -> gettext("%{label} +%{count}", label: check.label, count: length(rest))
    end
  end

  defp score_level(score) when score >= 80, do: "good"
  defp score_level(score) when score >= 50, do: "fair"
  defp score_level(_), do: "poor"

  defp status_label(:pass), do: gettext("OK")
  defp status_label(:warn), do: gettext("Warning")
  defp status_label(:fail), do: gettext("Failed")
  defp status_label(:skip), do: gettext("Not checked")

  def handle_info({:content_language, _language}, socket) do
    send_update_after(
      BrandoAdmin.Components.Form,
      [id: "seo_form", action: :refresh_entry],
      500
    )

    socket = socket |> assign_entry_id() |> assign_ai_context_fields(socket.assigns.audit_schemas)

    if socket.assigns.tab == "content" do
      {:noreply, socket |> start_audit() |> start_structured_data()}
    else
      {:noreply, assign(socket, audit: nil, audit_status: :idle, structured_data: nil, structured_data_status: :idle)}
    end
  end

  def handle_info({:seo_suggestions_updated, language}, socket) do
    if language == socket.assigns.audit_language,
      do: {:noreply, assign_suggestions(socket)},
      else: {:noreply, socket}
  end

  def handle_info({:EXIT, _port, :normal}, socket) do
    {:noreply, socket}
  end
end
