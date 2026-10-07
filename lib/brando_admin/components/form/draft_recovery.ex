defmodule BrandoAdmin.Components.Form.DraftRecovery do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext
  alias BrandoAdmin.Components.TextDiff
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true

  attr :state, :any, required: true
  attr :target, :any, required: true
  attr :entry_id, :any, default: nil

  attr :part, :atom,
    default: :all,
    values: [:all, :status, :panels],
    doc: "`:status` is the save state for a toolbar or save bar, `:panels` the notice and recovery panel"

  attr :saved_at, :any, default: nil, doc: "When the entry was last saved, for \"Saved 23:20\""

  def render(%{part: :status} = assigns) do
    ~H"""
    <div id={@id} class="draft-save-state" data-state={save_state(@state, @saved_at)} title={status(@state)}>
      <.save_status state={@state} saved_at={@saved_at} target={@target} />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <section id={@id} class="draft-recovery" aria-label={gettext("Recovery copies")} data-testid="draft-recovery">
      <div :if={@part == :all} class="draft-save-state" data-state={save_state(@state, @saved_at)} title={status(@state)}>
        <.save_status state={@state} saved_at={@saved_at} target={@target} />
      </div>

      <div
        :if={@state && !@state.open? && Enum.any?(@state.candidates, &is_nil(&1.dismissed_at))}
        class="draft-recovery-notice"
        data-testid="draft-notice"
      >
        <div class="draft-notice-content">
          <span class="draft-heading-icon"><Brando.HTML.Icon.icon name="rotate-ccw-clock" class="draft-icon" /></span>
          <div>
            <h2>{gettext("Pick up where you left off")}</h2>
            <p>{gettext("You have an unsaved recovery copy for this entry.")}</p>
          </div>
        </div>
        <div class="draft-actions">
          <button type="button" class="draft-button draft-button-primary" phx-click="draft_open" phx-target={@target}>
            {gettext("Review recovery copy")}
          </button>
          <button type="button" class="draft-button" phx-click="draft_dismiss" phx-target={@target}>
            {gettext("Continue without restoring")}
          </button>
        </div>
      </div>

      <div :if={@state && @state.open?} class="draft-recovery-panel" data-testid="draft-panel">
        <header class="draft-panel-header">
          <span class="draft-heading-icon"><Brando.HTML.Icon.icon name="rotate-ccw-clock" class="draft-icon" /></span>
          <div class="draft-heading">
            <h2>{gettext("Recover unsaved changes")}</h2>
            <p>
              {gettext(
                "Review your changes, then bring them back into the editor. Your saved entry changes only when you save."
              )}
            </p>
          </div>
          <button
            type="button"
            class="draft-button draft-button-quiet draft-close"
            phx-click="draft_dismiss"
            phx-target={@target}
            aria-label={gettext("Close recovery panel")}
            title={gettext("Close recovery panel")}
          >
            <Brando.HTML.Icon.icon name="x" class="draft-icon" />
          </button>
        </header>

        <div class="draft-panel-body">
          <div class="draft-copy-section">
            <h3 class="draft-section-label">{gettext("Choose a recovery copy")}</h3>
            <div class="draft-copy-list">
              <table class="draft-copy-table" aria-label={gettext("Recovery copies")}>
                <thead>
                  <tr>
                    <th scope="col">{gettext("Entry")}</th>
                    <th scope="col">{gettext("Captured (UTC)")}</th>
                    <th scope="col">{gettext("Content")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={copy <- @state.candidates}
                    id={"#{@id}-copy-#{copy.id}"}
                    class={selected?(@state, copy) && "draft-copy-selected"}
                  >
                    <th scope="row">
                      <button
                        type="button"
                        class="draft-copy"
                        aria-pressed={to_string(selected?(@state, copy))}
                        phx-click="draft_review"
                        phx-value-id={copy.id}
                        phx-target={@target}
                      >
                        <span class="draft-copy-indicator"><Brando.HTML.Icon.icon name="check" class="draft-icon" /></span>
                        <span class="draft-copy-title">{copy_title(copy)}</span>
                      </button>
                      <span :if={copy.attempted_at} class="draft-copy-reviewed">{gettext("Previously reviewed")}</span>
                    </th>
                    <td>
                      <BrandoAdmin.Dates.time at={copy.updated_at} format={:long} />
                    </td>
                    <td class="draft-copy-contents">{content_summary(copy.payload)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div :if={@state.error} class="draft-error" role="alert">
            <Brando.HTML.Icon.icon name="triangle-alert" class="draft-icon" />
            <div>
              <h3>{gettext("This copy needs attention")}</h3>
              <p>{@state.error}</p>
            </div>
          </div>

          <div :if={@state.selected} class="draft-selected-content">
            <div class="draft-preview-heading">
              <div>
                <h3>{gettext("Content changes")}</h3>
                <p>{gettext("Compare the saved entry with this recovery copy before restoring.")}</p>
              </div>
              <div class="draft-actions">
                <.copy_button
                  id={"#{@id}-copy-text-#{@state.selected.id}"}
                  source={"#{@id}-preview"}
                  label={gettext("Copy text")}
                />
                <a
                  class="draft-button draft-export"
                  download="entry-recovery.json"
                  href={"data:application/json;base64," <> Base.encode64(Jason.encode!(@state.selected.payload, pretty: true))}
                >
                  <Brando.HTML.Icon.icon name="download" class="draft-icon" />{gettext("Download JSON")}
                </a>
              </div>
            </div>
            <.content_preview id={"#{@id}-preview"} sections={@state.preview} />
            <details
              id={"#{@id}-inspector"}
              class="draft-inspector draft-raw-content"
              phx-mounted={JS.ignore_attributes("open")}
            >
              <summary>
                <Brando.HTML.Icon.icon name="chevron-right" class="draft-icon" />{gettext("View full recovery data (JSON)")}
              </summary>
              <div class="draft-raw-toolbar">
                <p>{gettext("Includes all stored values and technical details.")}</p>
                <.copy_button
                  id={"#{@id}-copy-json-#{@state.selected.id}"}
                  source={"#{@id}-payload"}
                  label={gettext("Copy JSON")}
                />
              </div>
              <pre id={"#{@id}-payload"} class="draft-payload" tabindex="0">{Jason.encode!(@state.selected.payload, pretty: true)}</pre>
            </details>

            <article :for={{issue, index} <- Enum.with_index(@state.issues)} class="draft-block-issue">
              <h3><Brando.HTML.Icon.icon name="triangle-alert" class="draft-icon" />{gettext("Block needs review")}</h3>
              <p :for={reason <- issue.reasons}>{reason}</p>
              <details
                id={"#{@id}-issue-#{@state.selected.id}-#{index}"}
                class="draft-inspector"
                phx-mounted={JS.ignore_attributes("open")}
              >
                <summary>
                  <Brando.HTML.Icon.icon name="chevron-right" class="draft-icon" />{gettext("Recover this block’s content")}
                </summary>
                <pre class="draft-payload" tabindex="0">{Jason.encode!(issue.content, pretty: true)}</pre>
              </details>
            </article>

            <p class="draft-retention-note">
              <Brando.HTML.Icon.icon name="shield-check" class="draft-icon" />
              {gettext("Your original recovery copy stays available if restoring fails or you start fresh.")}
            </p>
          </div>
        </div>

        <footer class="draft-panel-footer">
          <button
            :if={@state.selected}
            type="button"
            class="draft-button draft-button-danger"
            phx-click="draft_discard"
            phx-value-id={@state.selected.id}
            phx-target={@target}
            data-confirm={gettext("Discard this recovery copy?")}
          >
            {gettext("Discard copy")}
          </button>
          <div class="draft-actions">
            <button type="button" class="draft-button" phx-click="draft_clean" phx-target={@target}>
              {if @entry_id, do: gettext("Open saved version"), else: gettext("Start fresh")}
            </button>
            <button
              :if={@state.selected && @state.compatible?}
              type="button"
              class="draft-button"
              phx-click="draft_restore_compatible"
              phx-value-id={@state.selected.id}
              phx-target={@target}
            >
              {gettext("Restore compatible content")}
            </button>
            <button
              :if={@state.selected}
              type="button"
              class="draft-button draft-button-primary"
              phx-click="draft_restore"
              phx-value-id={@state.selected.id}
              phx-target={@target}
              phx-disable-with={gettext("Checking copy…")}
            >
              {gettext("Restore recovery copy")}
            </button>
          </div>
        </footer>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :source, :string, required: true
  attr :label, :string, required: true

  defp copy_button(assigns) do
    ~H"""
    <button id={@id} type="button" class="draft-button draft-copy-content" data-draft-copy={@source} aria-label={@label}>
      <Brando.HTML.Icon.icon name="copy" class="draft-icon" />
      <span class="draft-copy-label">{@label}</span>
      <span class="draft-copy-success" role="status">{gettext("Copied")}</span>
      <span class="draft-copy-failure" role="status">{gettext("Select and copy manually")}</span>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :sections, :list, required: true

  defp content_preview(assigns) do
    ~H"""
    <div
      id={@id}
      class="draft-content-preview"
      data-show-unchanged="false"
      tabindex="0"
      aria-label={gettext("Recovery content preview")}
    >
      <label
        id={"#{@id}-toggle"}
        class="draft-preview-toggle"
        for={"#{@id}-show-unchanged"}
        phx-update="ignore"
      >
        <input
          id={"#{@id}-show-unchanged"}
          type="checkbox"
          aria-controls={"#{@id}-sections"}
          phx-click={JS.toggle_attribute({"data-show-unchanged", "true", "false"}, to: "##{@id}")}
        />
        {gettext("Show unchanged content")}
      </label>
      <p
        :if={@sections != [] && Enum.all?(@sections, &(&1[:kind] != :order && &1.before == &1.after))}
        class="draft-preview-unchanged"
      >
        {gettext("No content changes in this preview.")}
      </p>
      <div id={"#{@id}-sections"} class="draft-preview-sections">
        <%= for {section, index} <- Enum.with_index(@sections) do %>
          <.order_diff :if={section[:kind] == :order} id={"#{@id}-order-#{index}"} section={section} />
          <TextDiff.diff
            :if={section[:kind] != :order}
            id={"#{@id}-section-#{index}"}
            label={section.title}
            before={section.before}
            after={section.after}
            description={gettext("Saved entry") <> " → " <> gettext("Recovery copy")}
          />
        <% end %>
      </div>
      <p :if={@sections == []} class="draft-preview-empty">
        {gettext("No readable fields in this copy. View or download the full recovery data below.")}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :section, :map, required: true

  defp order_diff(assigns) do
    ~H"""
    <section id={@id} class="draft-order-diff" aria-labelledby={@id <> "-title"}>
      <header>
        <h4 id={@id <> "-title"}>{@section.title}</h4>
        <span class="draft-order-badge">{gettext("Order changed")}</span>
      </header>
      <div class="draft-order-columns" aria-hidden="true">
        <span>{gettext("Content")}</span>
        <span>{gettext("Position")}</span>
      </div>
      <ol>
        <li :for={move <- @section.moves}>
          <div class="draft-order-item">
            <img :if={move.thumbnail} src={move.thumbnail} alt="" loading="lazy" />
            <span :if={!move.thumbnail} class="draft-order-icon" aria-hidden="true">
              <Brando.HTML.Icon.icon name="arrow-up-down" />
            </span>
            <span>{move.title}</span>
          </div>
          <span
            class="draft-order-positions"
            aria-label={gettext("Moved from position %{from} to %{to}", from: move.from, to: move.to)}
          >
            <span title={gettext("Saved entry")}>{move.from}</span>
            <span aria-hidden="true">→</span>
            <span title={gettext("Recovery copy")}>{move.to}</span>
          </span>
        </li>
      </ol>
    </section>
    """
  end

  defp selected?(state, copy), do: !is_nil(state.selected) && state.selected.id == copy.id

  defp content_summary(payload) do
    count =
      case payload["blocks"] do
        blocks when is_map(blocks) ->
          blocks |> Map.values() |> Enum.filter(&is_list/1) |> Enum.map(&length/1) |> Enum.sum()

        _ ->
          0
      end

    if count == 0, do: gettext("Entry fields"), else: ngettext("%{count} block", "%{count} blocks", count)
  end

  defp actionable(candidates), do: Enum.filter(candidates, &is_nil(&1.dismissed_at))

  defp history_label(candidates) do
    case length(actionable(candidates)) do
      0 -> gettext("Recovery copies")
      count -> gettext("Recovery copies (%{count})", count: count)
    end
  end

  attr :state, :any, required: true
  attr :saved_at, :any, required: true
  attr :target, :any, required: true

  # The visible label is short ("Saved 23:20", "Unsaved changes"); the
  # recovery storage's own status is read out to screen readers and shown on
  # hover, and an error is shown in full.
  defp save_status(assigns) do
    ~H"""
    <span class="draft-save-dot" aria-hidden="true"></span>
    <span class="draft-save-label draft-online-status" aria-hidden="true">{save_label(@state, @saved_at)}</span>
    <span class="draft-save-detail" role="status" data-testid="draft-status">{status(@state)}</span>
    <span class="draft-offline-status">{gettext("Offline — recent edits have not reached recovery storage")}</span>
    <%!-- Counts only copies still waiting for a decision: a dismissed copy
          doesn't call for attention, but the button stays so it can still
          be reopened (e.g. content left out of a partial restore). --%>
    <button
      :if={@state && (@state.candidates != [] or @state.open?)}
      type="button"
      class="draft-save-history"
      phx-click="draft_open"
      phx-target={@target}
      aria-expanded={to_string(@state.open?)}
    >
      <Brando.HTML.Icon.icon name="rotate-ccw-clock" class="draft-icon" />
      {history_label(@state.candidates)}
    </button>
    """
  end

  # "new" is clean, but not saved yet.
  defp save_state(state, saved_at) do
    case save_state(state) do
      "clean" when is_nil(saved_at) -> "new"
      key -> key
    end
  end

  @doc false
  def save_state(%{status: :error}), do: "error"
  def save_state(%{status: :saving}), do: "dirty"
  def save_state(%{checksum: checksum, baseline: checksum}), do: "clean"
  def save_state(%{}), do: "dirty"
  def save_state(nil), do: "clean"

  @doc false
  def save_label(%{status: :error} = state, _saved_at), do: status(state)

  def save_label(state, saved_at) do
    if save_state(state) == "clean",
      do: saved_label(saved_at),
      else: gettext("Unsaved changes")
  end

  defp saved_label(nil), do: gettext("Not saved yet")
  defp saved_label(at), do: gettext("Saved %{time}", time: BrandoAdmin.Dates.clock(at))

  defp status(nil), do: gettext("Recovery storage is unavailable")
  defp status(%{status: :error}), do: gettext("Recovery copy could not be saved — keep this editor open")
  defp status(%{status: :saving}), do: gettext("Saving recovery copy…")

  defp status(%{checksum: checksum, baseline: checksum}),
    do: gettext("No unsaved changes in this editor")

  defp status(%{saved_at: %DateTime{} = at}),
    do: gettext("Recovery copy saved at %{time}", time: BrandoAdmin.Dates.short(at))

  defp status(_), do: gettext("Recovery copies are saved automatically")

  defp copy_title(%{payload: %{"main" => %{"title" => title}}}) when is_binary(title), do: title
  defp copy_title(_), do: gettext("Untitled entry")
end
