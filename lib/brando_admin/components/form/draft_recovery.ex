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
      <div class="draft-recovery-status" role="status">
        <span class="draft-online-status" data-testid="draft-status">{status(@state)}</span>
        <span class="draft-offline-status">{gettext("Offline — recent edits have not reached recovery storage")}</span>
        <button
          :if={@state && @state.candidates != []}
          type="button"
          class="tiny secondary"
          phx-click="draft_open"
          phx-target={@target}
        >
          {gettext("Recovery copies (%{count})", count: length(@state.candidates))}
        </button>
      </div>

      <div
        :if={@state && !@state.open? && Enum.any?(@state.candidates, &is_nil(&1.dismissed_at))}
        class="draft-recovery-notice"
        data-testid="draft-notice"
      >
        <p>{gettext("You have an unsaved recovery copy for this entry.")}</p>
        <div class="draft-actions">
          <button type="button" class="secondary" phx-click="draft_open" phx-target={@target}>{gettext("Review recovery copy")}</button>
          <button type="button" class="secondary" phx-click="draft_dismiss" phx-target={@target}>{gettext(
            "Continue without restoring"
          )}</button>
        </div>
      </div>

      <div :if={@state && @state.open?} class="draft-recovery-panel" data-testid="draft-panel">
        <h2>{gettext("Recover unsaved changes")}</h2>
        <p>
          {gettext(
            "Choose a copy to inspect. Restoring loads it into the editor; your saved entry is updated only when you save."
          )}
        </p>
        <div class="draft-copy-list">
          <button
            :for={copy <- @state.candidates}
            type="button"
            class="secondary"
            phx-click="draft_review"
            phx-value-id={copy.id}
            phx-target={@target}
          >
            {copy_title(copy)} · {Calendar.strftime(copy.updated_at, "%d %b %H:%M UTC")}
            <span :if={copy.attempted_at}> · {gettext("Previously reviewed")}</span>
          </button>
        </div>

        <p :if={@state.error} class="draft-error" role="alert">{@state.error}</p>

        <div :if={@state.selected}>
          <h3>{gettext("Saved recovery content")}</h3>
          <p>{gettext("The original copy is retained if restoration fails or you continue with a clean editor.")}</p>
          <table :if={@state.comparison != []} class="draft-comparison">
            <thead>
              <tr>
                <th>{gettext("Field")}</th><th>{gettext("Saved entry")}</th><th>{gettext("Recovery copy")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @state.comparison}>
                <th scope="row">{row.field}</th>
                <td>{display(row.saved)}</td>
                <td>{display(row.recovered)}</td>
              </tr>
            </tbody>
          </table>
          <details>
            <summary>{gettext("Inspect / copy recovery content")}</summary>
            <pre class="draft-payload" tabindex="0">{Jason.encode!(@state.selected.payload, pretty: true)}</pre>
          </details>
          <a
            class="draft-export"
            download="entry-recovery.json"
            href={"data:application/json;charset=utf-8," <> URI.encode(Jason.encode!(@state.selected.payload, pretty: true))}
          >
            {gettext("Download recovery copy")}
          </a>

          <article :for={issue <- @state.issues} class="draft-block-issue">
            <h3>{gettext("Block needs review")}</h3>
            <p :for={reason <- issue.reasons}>{reason}</p>
            <details>
              <summary>{gettext("Recover this block’s content")}</summary>
              <pre class="draft-payload" tabindex="0">{Jason.encode!(issue.content, pretty: true)}</pre>
            </details>
          </article>

          <div class="draft-actions">
            <button
              type="button"
              class="primary"
              phx-click="draft_restore"
              phx-value-id={@state.selected.id}
              phx-target={@target}
              phx-disable-with={gettext("Checking copy…")}
            >
              {gettext("Restore recovery copy")}
            </button>
            <button
              :if={@state.compatible?}
              type="button"
              class="secondary"
              phx-click="draft_restore_compatible"
              phx-value-id={@state.selected.id}
              phx-target={@target}
            >
              {gettext("Restore compatible content")}
            </button>
            <button
              type="button"
              class="secondary"
              phx-click="draft_discard"
              phx-value-id={@state.selected.id}
              phx-target={@target}
              data-confirm={gettext("Discard this recovery copy?")}
            >
              {gettext("Discard copy")}
            </button>
          </div>
        </div>

        <div class="draft-actions">
          <button type="button" class="secondary" phx-click="draft_clean" phx-target={@target}>
            {if @entry_id, do: gettext("Open saved version"), else: gettext("Start fresh")}
          </button>
          <button type="button" class="secondary" phx-click="draft_dismiss" phx-target={@target}>{gettext(
            "Close recovery panel"
          )}</button>
        </div>
      </div>
    </section>
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

  defp display(value) when value in [nil, ""], do: "—"
  defp display(value), do: to_string(value)
end
