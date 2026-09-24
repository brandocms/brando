defmodule BrandoAdmin.Sites.SEOLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.SEO
  use Gettext, backend: Brando.Gettext

  alias Brando.AI
  alias Brando.SEO.Analyze
  alias Brando.SEO.Audit
  alias Brando.SEO.Generate
  alias Brando.SEO.Suggestions
  alias Brando.Sites
  alias BrandoAdmin.Components.Form

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), Suggestions.topic())

    {:ok,
     socket
     |> assign_current_user(token)
     |> assign_entry_id()
     |> assign_404s()
     |> assign_audit_defaults()}
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] == "content", do: "content", else: "settings"
    socket = assign(socket, :tab, tab)

    if tab == "content" and socket.assigns.audit_status == :idle do
      {:noreply, start_audit(socket)}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace settings-workspace seo-workspace">
      <nav class="seo-tabs" aria-label={gettext("SEO sections")}>
        <button type="button" phx-click="tab" phx-value-tab="settings" aria-current={@tab == "settings" && "page"}>
          {gettext("Settings")}
        </button>
        <button type="button" phx-click="tab" phx-value-tab="content" aria-current={@tab == "content" && "page"}>
          {gettext("Content SEO")}
          <.score_badge :if={@audit} score={@audit.score} />
        </button>
      </nav>

      <div :if={@tab == "settings"}>
        <.live_component module={Form} id="seo_form" entry_id={@entry_id} current_user={@current_user} schema={@schema}>
          <:header>
            {gettext("Update SEO")}
          </:header>
        </.live_component>

        <section class="workspace-panel seo-not-found">
          <header class="workspace-panel-heading">
            <div>
              <h2>{gettext("Not found (404)")}</h2><p>
                {gettext("Requests for URLs that do not exist. Add a redirect above when a page has moved.")}
              </p>
            </div>
          </header>
          <BrandoAdmin.Components.Workspace.empty
            :if={@four_oh_fours == []}
            title={gettext("No missing URLs recorded")}
            description={gettext("Missing pages will appear here when they are requested.")}
          />
          <div
            :if={@four_oh_fours != []}
            class="workspace-table-scroll"
            tabindex="0"
            role="region"
            aria-label={gettext("Not found (404)")}
          >
            <table class="workspace-table">
              <thead>
                <tr>
                  <th>{gettext("URL")}</th><th>{gettext("Hits")}</th><th>{gettext("Last hit")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={item <- @four_oh_fours}>
                  <td class="workspace-mono">{item.url}</td><td>{item.hits}</td><td>{item.last_hit_at}</td>
                </tr>
              </tbody>
            </table>
          </div>
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
        />
      </div>
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

  defp content_audit(assigns) do
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
        <.overview audit={@audit} />

        <.batch
          :if={@ai_available}
          candidates={batch_candidates(@audit, @suggestions)}
          confirm={@batch_confirm}
          max={Suggestions.max_batch()}
        />
        <.suggestions :if={@suggestions != []} suggestions={@suggestions} accepting_all={@accepting_all} />

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
                <th>{gettext("Issues")}</th>
                <th><span class="sr-only">{gettext("Details")}</span></th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @audit.rows do %>
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
                  <td colspan="5">
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
                                <small :if={check.status in [:warn, :fail] and check.hint}>{check.hint}</small>
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
                        <div class="seo-preview-title">{row.meta_title || row.title}</div>
                        <p>{row.meta_description || gettext("(no description — the site fallback is shown)")}</p>
                        <div class="seo-preview-actions">
                          <.link navigate={row.schema.__admin_route__(:update, [row.id])}>{gettext("Open entry")}</.link>
                          <button
                            :if={@ai_available}
                            type="button"
                            class="seo-row-action"
                            phx-click="generate_description"
                            phx-value-key={key}
                            disabled={MapSet.member?(@generating, key)}
                          >
                            <%= if MapSet.member?(@generating, key) do %>
                              {gettext("Writing…")}
                            <% else %>
                              {if row.meta_description, do: gettext("Rewrite description"), else: gettext("Write description")}
                            <% end %>
                          </button>
                          <button
                            :if={@ai_available and row.meta_description}
                            type="button"
                            class="seo-row-action"
                            phx-click="critique"
                            phx-value-key={key}
                            disabled={@critiques[key] == :running}
                          >
                            {gettext("Review with AI")}
                          </button>
                        </div>
                        <.critique :if={@critiques[key]} critique={@critiques[key]} />
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
        <button :if={!@confirm} type="button" class="workspace-button" phx-click="confirm_batch">
          {gettext("Write missing descriptions")}
        </button>
        <button :if={@confirm} type="button" class="workspace-button primary" phx-click="start_batch">
          {ngettext("Write one description", "Write %{count} descriptions", @count)}
        </button>
        <button :if={@confirm} type="button" class="workspace-button" phx-click="cancel_batch">
          {gettext("Cancel")}
        </button>
      </div>
    </div>
    """
  end

  attr :suggestions, :list
  attr :accepting_all, :boolean

  defp suggestions(assigns) do
    assigns =
      assign(assigns, :counts, Enum.frequencies_by(assigns.suggestions, & &1.status))

    ~H"""
    <section class="seo-suggestions" id="seo-suggestions" aria-labelledby="seo-suggestions-heading">
      <header class="seo-suggestions-heading">
        <div>
          <h3 id="seo-suggestions-heading">{gettext("Suggested descriptions")}</h3>
          <p role="status" aria-live="polite">
            <span :if={@counts[:queued]}>{gettext("%{count} being written", count: @counts[:queued])}</span>
            <span :if={@counts[:pending]}>{gettext("%{count} to review", count: @counts[:pending])}</span>
            <span :if={@counts[:failed]}>{gettext("%{count} failed", count: @counts[:failed])}</span>
          </p>
        </div>
        <button
          :if={@counts[:pending]}
          type="button"
          class="workspace-button primary"
          phx-click="accept_all_suggestions"
          disabled={@accepting_all}
        >
          {if @accepting_all, do: gettext("Saving…"), else: gettext("Accept all")}
        </button>
      </header>
      <ul class="seo-suggestion-list">
        <li
          :for={suggestion <- @suggestions}
          id={"seo-suggestion-#{suggestion.id}"}
          class="seo-suggestion"
          data-status={suggestion.status}
        >
          <div class="seo-suggestion-entry">
            <strong>{suggestion.title}</strong>
            <small>{suggestion_schema_name(suggestion)}</small>
          </div>
          <p :if={suggestion.status == :queued} class="seo-suggestion-note">
            <span class="seo-spinner" aria-hidden="true"></span>{gettext("Writing…")}
          </p>
          <div :if={suggestion.status == :failed} class="seo-suggestion-failed">
            <p role="alert">{suggestion.error}</p>
            <button type="button" class="workspace-button" phx-click="reject_suggestion" phx-value-id={suggestion.id}>
              {gettext("Dismiss")}
            </button>
          </div>
          <form :if={suggestion.status == :pending} class="seo-suggestion-form" phx-submit="accept_suggestion">
            <input type="hidden" name="suggestion_id" value={suggestion.id} />
            <%!-- Ignored after mount so an edit survives other suggestions arriving. --%>
            <textarea
              id={"seo-suggestion-text-#{suggestion.id}"}
              name="text"
              rows="3"
              phx-update="ignore"
              aria-label={gettext("Suggested description for %{title}", title: suggestion.title)}
            >{suggestion.text}</textarea>
            <div class="seo-suggestion-actions">
              <button type="submit" class="workspace-button primary">{gettext("Accept")}</button>
              <button type="button" class="workspace-button" phx-click="reject_suggestion" phx-value-id={suggestion.id}>
                {gettext("Reject")}
              </button>
            </div>
          </form>
        </li>
      </ul>
    </section>
    """
  end

  attr :critique, :any

  defp critique(assigns) do
    ~H"""
    <div class="seo-critique" role="status" aria-live="polite">
      <%= case @critique do %>
        <% :running -> %>
          <p><span class="seo-spinner" aria-hidden="true"></span>{gettext("Reviewing…")}</p>
        <% {:ok, points} -> %>
          <h4>{gettext("AI review")}</h4>
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
        <div class="seo-stat">
          <dt>{gettext("Drafts not audited")}</dt>
          <dd>{@audit.drafts}</dd>
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
              <td class="workspace-mono">{suggestion.url}</td>
              <td>{suggestion.hits}</td>
              <td>
                <strong>{suggestion.title}</strong>
                <small class="workspace-mono">{suggestion.to}</small>
                <small :if={suggestion.confidence == :close}>{gettext("Close match — check before creating")}</small>
              </td>
              <td>
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
          kind={gettext("Description")}
          value={value}
          rows={rows}
        />
        <.duplicate_group :for={{value, rows} <- @audit.duplicate_titles} kind={gettext("Title")} value={value} rows={rows} />
      </div>
    </div>
    """
  end

  attr :kind, :string
  attr :value, :string
  attr :rows, :list

  defp duplicate_group(assigns) do
    ~H"""
    <div class="seo-duplicate">
      <p><strong>{@kind}:</strong> <q>{@value}</q></p>
      <ul>
        <li :for={row <- @rows}>
          <.link navigate={row.schema.__admin_route__(:update, [row.id])}>{row.title}</.link>
          <small>{Brando.Blueprint.get_singular(row.schema)}</small>
        </li>
      </ul>
    </div>
    """
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(settings content) do
    {:noreply, push_patch(socket, to: Brando.routes().admin_live_path(socket, __MODULE__, tab: tab))}
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

  def handle_event("rerun_audit", _params, socket), do: {:noreply, start_audit(socket)}

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

  def handle_event("generate_description", %{"key" => key}, socket) do
    %{audit: audit, current_user: user, ai_available: available?} = socket.assigns
    row = audit && Enum.find(audit.rows, &(row_key(&1) == key))

    if available? and row do
      fields = Map.get(socket.assigns.ai_context_fields, row.schema)
      run = fn -> Generate.generate(row.schema, row.id, :meta_description, user, context_fields: fields) end

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
      run = fn -> Analyze.critique(row.schema, row.id) end

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
    run = fn -> Suggestions.accept_all(language, user) end

    {:noreply,
     socket
     |> assign(:accepting_all, true)
     |> start_async(:accept_all, in_captured_context(socket, run))}
  end

  def handle_event("toggle_row", %{"key" => key}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, key), do: MapSet.delete(expanded, key), else: MapSet.put(expanded, key)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_async(:audit, {:ok, %Audit.Result{} = result}, socket) do
    # Row keys are the schema and id, so an expanded row survives a re-run —
    # which is what you want after generating a description from inside it.
    {:noreply, assign(socket, audit: result, audit_status: :done)}
  end

  def handle_async(:audit, {:exit, reason}, socket) do
    {:noreply, assign(socket, audit_status: {:error, Exception.format_exit(reason)})}
  end

  # The entry is written before the audit re-runs, so the row picks the new
  # description up from the database rather than from the reply.
  def handle_async({:generate, key}, {:ok, {:ok, _generated}}, socket) do
    send(self(), {:toast, gettext("Description written")})

    {:noreply,
     socket
     |> update(:generating, &MapSet.delete(&1, key))
     |> update(:critiques, &Map.delete(&1, key))
     |> start_audit()}
  end

  def handle_async({:generate, key}, {:ok, {:error, reason}}, socket) do
    send(self(), {:toast, AI.error_message(reason)})
    {:noreply, update(socket, :generating, &MapSet.delete(&1, key))}
  end

  def handle_async({:generate, key}, {:exit, _reason}, socket) do
    send(self(), {:toast, AI.error_message(:failed)})
    {:noreply, update(socket, :generating, &MapSet.delete(&1, key))}
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

  defp assign_404s(socket) do
    assign_new(socket, :four_oh_fours, fn -> Brando.Sites.FourOhFour.list() end)
  end

  defp assign_audit_defaults(socket) do
    schemas = Audit.schemas()
    default = if Brando.Pages.Page in schemas, do: [Brando.Pages.Page], else: schemas

    socket
    |> assign(:tab, "settings")
    |> assign(:audit, nil)
    |> assign(:audit_sandbox, sandbox_owner(socket))
    |> assign(:audit_status, :idle)
    |> assign(:audit_schemas, schemas)
    |> assign(:selected_schemas, default)
    |> assign(:include_drafts, false)
    |> assign(:expanded, MapSet.new())
    |> assign(:generating, MapSet.new())
    |> assign(:critiques, %{})
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
  defp start_audit(socket) do
    language = content_language(socket)
    schemas = socket.assigns.selected_schemas
    include_drafts? = socket.assigns.include_drafts

    run = fn -> Audit.run(language, schemas: schemas, include_drafts: include_drafts?) end

    socket
    |> assign(:audit_status, :running)
    |> assign(:audit_language, language)
    |> assign_suggestions()
    |> start_async(:audit, in_captured_context(socket, run))
  end

  defp assign_suggestions(socket) do
    assign(socket, :suggestions, Suggestions.list_open(socket.assigns.audit_language))
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

  defp save_error(:not_found), do: gettext("This suggestion was already reviewed")
  defp save_error(:empty), do: gettext("Write a description before accepting it")
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
      {:noreply, start_audit(socket)}
    else
      {:noreply, assign(socket, audit: nil, audit_status: :idle)}
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
