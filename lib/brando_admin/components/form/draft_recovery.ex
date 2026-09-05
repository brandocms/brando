defmodule BrandoAdmin.Components.Form.DraftRecovery do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  attr :state, :any, required: true
  attr :target, :any, required: true
  attr :entry_id, :any, default: nil

  def render(assigns) do
    ~H"""
    <section class="draft-recovery" aria-label={gettext("Recovery copies")} data-testid="draft-recovery">
      <div class="draft-recovery-status">
        <div class="draft-storage-status" role="status">
          <.recovery_icon name="history" />
          <span class="draft-online-status" data-testid="draft-status">{status(@state)}</span>
          <span class="draft-offline-status">{gettext("Offline — recent edits have not reached recovery storage")}</span>
        </div>
        <button
          :if={@state && @state.candidates != []}
          type="button"
          class="draft-button draft-button-quiet"
          phx-click="draft_open"
          phx-target={@target}
          aria-expanded={to_string(@state.open?)}
        >
          {gettext("Recovery copies (%{count})", count: length(@state.candidates))}
          <.recovery_icon name="chevron" />
        </button>
      </div>

      <div
        :if={@state && !@state.open? && Enum.any?(@state.candidates, &is_nil(&1.dismissed_at))}
        class="draft-recovery-notice"
        data-testid="draft-notice"
      >
        <div class="draft-notice-content">
          <span class="draft-heading-icon"><.recovery_icon name="history" /></span>
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
          <span class="draft-heading-icon"><.recovery_icon name="history" /></span>
          <div class="draft-heading">
            <p class="draft-eyebrow">{gettext("Your work, kept safe")}</p>
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
            <.recovery_icon name="close" />
          </button>
        </header>

        <div class="draft-panel-body">
          <div class="draft-copy-section">
            <h3 class="draft-section-label">{gettext("Choose a recovery copy")}</h3>
            <div class="draft-copy-list">
              <button
                :for={copy <- @state.candidates}
                type="button"
                class="draft-copy"
                aria-pressed={to_string(!is_nil(@state.selected) && @state.selected.id == copy.id)}
                phx-click="draft_review"
                phx-value-id={copy.id}
                phx-target={@target}
              >
                <span class="draft-copy-indicator"><.recovery_icon name="check" /></span>
                <span class="draft-copy-description">
                  <span class="draft-copy-title">{copy_title(copy)}</span>
                  <time datetime={DateTime.to_iso8601(copy.updated_at)}>
                    {Calendar.strftime(copy.updated_at, "%d %b %Y · %H:%M UTC")}
                  </time>
                  <span :if={copy.attempted_at} class="draft-copy-reviewed">{gettext("Previously reviewed")}</span>
                </span>
              </button>
            </div>
          </div>

          <div :if={@state.error} class="draft-error" role="alert">
            <.recovery_icon name="warning" />
            <div>
              <h3>{gettext("This copy needs attention")}</h3>
              <p>{@state.error}</p>
            </div>
          </div>

          <div :if={@state.selected} class="draft-selected-content">
            <div :if={@state.comparison != []} class="draft-comparison-heading">
              <h3>{gettext("Changes to review")}</h3>
              <span class="draft-change-count">
                {ngettext("%{count} field", "%{count} fields", length(@state.comparison))}
              </span>
            </div>
            <div :if={@state.comparison != []} class="draft-comparison-frame">
              <table class="draft-comparison" role="table" aria-label={gettext("Changes in this recovery copy")}>
                <thead>
                  <tr>
                    <th scope="col">{gettext("Field")}</th>
                    <th scope="col">{gettext("Saved entry")}</th>
                    <th scope="col"><.recovery_icon name="history" />{gettext("Recovery copy")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @state.comparison}>
                    <th scope="row">{row.field}</th>
                    <td data-label={gettext("Saved entry")}>
                      <span class={row.saved in [nil, ""] && "draft-empty-value"}>{display(row.saved)}</span>
                    </td>
                    <td data-label={gettext("Recovery copy")}>
                      <span class={row.recovered in [nil, ""] && "draft-empty-value"}>{display(row.recovered)}</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="draft-content-tools">
              <details class="draft-inspector">
                <summary><.recovery_icon name="chevron" />{gettext("Inspect / copy recovery content")}</summary>
                <pre class="draft-payload" tabindex="0">{Jason.encode!(@state.selected.payload, pretty: true)}</pre>
              </details>
              <a
                class="draft-button draft-button-quiet draft-export"
                download="entry-recovery.json"
                href={"data:application/json;charset=utf-8," <> URI.encode(Jason.encode!(@state.selected.payload, pretty: true))}
              >
                <.recovery_icon name="download" />{gettext("Download recovery copy")}
              </a>
            </div>

            <article :for={issue <- @state.issues} class="draft-block-issue">
              <h3><.recovery_icon name="warning" />{gettext("Block needs review")}</h3>
              <p :for={reason <- issue.reasons}>{reason}</p>
              <details class="draft-inspector">
                <summary><.recovery_icon name="chevron" />{gettext("Recover this block’s content")}</summary>
                <pre class="draft-payload" tabindex="0">{Jason.encode!(issue.content, pretty: true)}</pre>
              </details>
            </article>

            <p class="draft-retention-note">
              <.recovery_icon name="shield" />
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

  attr :name, :string, required: true

  defp recovery_icon(assigns) do
    path =
      case assigns.name do
        "history" -> "M3 4v5h5 M3.5 9a9 9 0 1 1 1 9 M12 7v5l3 2"
        "check" -> "m5 12 4 4L19 6"
        "chevron" -> "m9 5 7 7-7 7"
        "close" -> "m6 6 12 12 M6 18 18 6"
        "download" -> "M12 3v12 m-5-5 5 5 5-5 M5 16v4h14v-4"
        "warning" -> "m12 3 10 18H2L12 3Z M12 9v4 m0 3v.5"
        "shield" -> "M12 3 4 6v6c0 5 8 9 8 9s8-4 8-9V6l-8-3Z m-4 9 3 3 5-6"
      end

    assigns = assign(assigns, :path, path)

    ~H"""
    <svg
      class="draft-icon"
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d={@path} />
    </svg>
    """
  end

  defp status(nil), do: gettext("Recovery storage is unavailable")
  defp status(%{status: :error}), do: gettext("Recovery copy could not be saved — keep this editor open")
  defp status(%{status: :saving}), do: gettext("Saving recovery copy…")

  defp status(%{saved_at: %DateTime{} = at}),
    do: gettext("Recovery copy saved at %{time}", time: Calendar.strftime(at, "%H:%M:%S UTC"))

  defp status(_), do: gettext("Recovery copies are saved automatically")

  defp copy_title(%{payload: %{"main" => %{"title" => title}}}) when is_binary(title), do: title
  defp copy_title(_), do: gettext("Untitled entry")

  defp display(value) when value in [nil, ""], do: gettext("No value")
  defp display(true), do: gettext("Yes")
  defp display(false), do: gettext("No")
  defp display(value), do: to_string(value)
end
