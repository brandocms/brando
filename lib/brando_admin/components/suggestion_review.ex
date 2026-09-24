defmodule BrandoAdmin.Components.SuggestionReview do
  @moduledoc """
  The review list for AI-written suggestions (`Brando.SEO.Suggestion`): each
  one queued, failed, or waiting to be edited, accepted or rejected, with an
  "Accept all" for the lot.

  The hosting LiveView handles `accept_suggestion` (params `suggestion_id`,
  and `text` — or `values`, language → text, for suggestions written in
  several languages), `reject_suggestion` (`id`) and `accept_all_suggestions`.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  attr :id, :string, required: true
  attr :heading, :string, required: true
  attr :suggestions, :list, required: true
  attr :accepting_all, :boolean, default: false
  attr :label, :any, required: true, doc: "fn suggestion -> textarea label"
  attr :subtitle, :any, default: nil, doc: "fn suggestion -> line under the title"
  attr :thumbnail, :any, default: nil, doc: "fn suggestion -> image URL, or nil"

  def review(assigns) do
    assigns = assign(assigns, :counts, Enum.frequencies_by(assigns.suggestions, & &1.status))

    ~H"""
    <section class="ai-suggestions" id={@id} aria-labelledby={"#{@id}-heading"}>
      <header class="ai-suggestions-heading">
        <div>
          <h3 id={"#{@id}-heading"}>{@heading}</h3>
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
      <ul class="ai-suggestion-list">
        <li
          :for={suggestion <- @suggestions}
          id={"suggestion-#{suggestion.id}"}
          class="ai-suggestion"
          data-status={suggestion.status}
          data-thumbnail={to_string(!!@thumbnail)}
        >
          <img
            :if={@thumbnail && @thumbnail.(suggestion)}
            class="ai-suggestion-thumbnail"
            src={@thumbnail.(suggestion)}
            alt=""
            loading="lazy"
          />
          <div class="ai-suggestion-entry">
            <strong>{suggestion.title}</strong>
            <small :if={@subtitle}>{@subtitle.(suggestion)}</small>
          </div>
          <p :if={suggestion.status == :queued} class="ai-suggestion-note">
            <span class="ai-spinner" aria-hidden="true"></span>{gettext("Writing…")}
          </p>
          <div :if={suggestion.status == :failed} class="ai-suggestion-failed">
            <p role="alert">{suggestion.error}</p>
            <button type="button" class="workspace-button" phx-click="reject_suggestion" phx-value-id={suggestion.id}>
              {gettext("Dismiss")}
            </button>
          </div>
          <form :if={suggestion.status == :pending} class="ai-suggestion-form" phx-submit="accept_suggestion">
            <input type="hidden" name="suggestion_id" value={suggestion.id} />
            <%!-- Ignored after mount so an edit survives other suggestions arriving. --%>
            <textarea
              :if={!is_map(suggestion.values)}
              id={"suggestion-text-#{suggestion.id}"}
              name="text"
              rows="3"
              phx-update="ignore"
              aria-label={@label.(suggestion)}
            >{suggestion.text}</textarea>
            <div :if={is_map(suggestion.values)} class="ai-suggestion-languages">
              <label :for={{language, text} <- Enum.sort_by(suggestion.values, &language_order/1)}>
                <span>{language}</span>
                <textarea
                  id={"suggestion-text-#{suggestion.id}-#{language}"}
                  name={"values[#{language}]"}
                  rows="2"
                  lang={language}
                  phx-update="ignore"
                  aria-label={"#{@label.(suggestion)} (#{Brando.AI.language_name(language)})"}
                >{text}</textarea>
              </label>
            </div>
            <div class="ai-suggestion-actions">
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

  # The default language first, then as configured.
  defp language_order({language, _text}) do
    languages = [Brando.config(:default_language) | Enum.map(Brando.config(:languages) || [], & &1[:value])]
    Enum.find_index(Enum.map(languages, &to_string/1), &(&1 == language)) || 99
  end
end
