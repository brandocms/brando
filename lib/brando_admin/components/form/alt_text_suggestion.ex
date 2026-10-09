defmodule BrandoAdmin.Components.Form.AltTextSuggestion do
  @moduledoc """
  Alt text that AI suggested for an image, waiting for review under the alt
  field: one text per language, which the editor can change, accept or
  discard, as a field's AI action suggests (`Form.FieldActions`). Nothing
  reaches the alt field until Accept.

  Whoever asks for the alt text (the entry form for the image's own form and
  the image drawer, a picture block for its own alt text) hands the reply
  here with `send_update(AltTextSuggestion, id: id, values: %{"en" => …})`.
  Accept sends `%{event: "accept_alt_suggestion", scope: scope, values: values}`
  to `owner` (a component's CID, or `{module, id}`), which writes the texts
  into its form as unsaved input; empty ones are left out.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.AIAction

  @doc "The panel's id for an alt field with DOM id `field_id`."
  def id(field_id), do: "#{field_id}-alt-suggestion"

  @doc "Whether `id` names an alt suggestion panel, for checking an id a browser sent."
  def id?(id) when is_binary(id), do: String.ends_with?(id, "-alt-suggestion") and byte_size(id) < 300
  def id?(_id), do: false

  @impl true
  def mount(socket), do: {:ok, assign(socket, values: nil, request: 0)}

  @impl true
  def update(%{values: values}, socket) when is_map(values) do
    {:ok, assign(socket, values: values, request: socket.assigns.request + 1)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :owner, :scope, :retry_event, :retry_target]))
     |> assign(:languages, assigns[:languages] || [])}
  end

  # The text as the editor changed it, sent as they leave it: before the
  # Accept click that follows.
  @impl true
  def handle_event("edit", %{"language" => language, "value" => text}, %{assigns: %{values: values}} = socket)
      when is_map_key(values, language) do
    {:noreply, assign(socket, :values, Map.put(values, language, text))}
  end

  def handle_event("edit", _params, socket), do: {:noreply, socket}

  def handle_event("accept", _params, %{assigns: %{values: values}} = socket) when is_map(values) do
    accepted = Map.reject(values, fn {_language, text} -> String.trim(text) == "" end)
    message = %{event: "accept_alt_suggestion", scope: socket.assigns.scope, values: accepted}

    case socket.assigns.owner do
      {module, id} -> send_update(module, Map.put(message, :id, id))
      cid -> send_update(cid, message)
    end

    {:noreply, assign(socket, :values, nil)}
  end

  def handle_event("accept", _params, socket), do: {:noreply, socket}

  def handle_event("discard", _params, socket), do: {:noreply, assign(socket, :values, nil)}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :rows, rows(assigns.values, assigns.languages))

    ~H"""
    <div id={@id} class="field-ai-actions alt-text-suggestion" data-testid="alt-suggestion" role="status" aria-live="polite">
      <div :if={@values} class="ai-proposal" data-status="ready">
        <p class="ai-proposal-label">
          <.icon name="sparkles" />
          <span>{gettext("AI suggestion")}</span>
          <span class="field-ai-action-name">{gettext("Alternative text")}</span>
        </p>
        <div :for={{language, name, text} <- @rows} class="alt-suggestion-language">
          <label :if={length(@rows) > 1} for={"#{@id}-#{language}-#{@request}"}>{name}</label>
          <%!-- Outside the entry form (`form` names no form), so editing it
                is not editing the field. --%>
          <textarea
            id={"#{@id}-#{language}-#{@request}"}
            class="ai-proposal-field"
            form={"#{@id}-detached"}
            rows="2"
            lang={language}
            aria-label={"#{gettext("Suggested text")} (#{name})"}
            phx-blur="edit"
            phx-value-language={language}
            phx-target={@myself}
          >{text}</textarea>
        </div>
        <div class="ai-proposal-actions">
          <button type="button" class="field-ai-button primary" phx-click="accept" phx-target={@myself}>
            {gettext("Accept")}
          </button>
          <button type="button" class="field-ai-button" phx-click="discard" phx-target={@myself}>
            {gettext("Discard")}
          </button>
          <AIAction.button :if={@retry_event} phx-click={@retry_event} phx-target={@retry_target} phx-value-panel={@id}>
            {gettext("Try again")}
          </AIAction.button>
        </div>
      </div>
    </div>
    """
  end

  # The suggested languages in the field's order, then any others.
  defp rows(nil, _languages), do: []

  defp rows(values, languages) do
    named = for {language, name} <- languages, Map.has_key?(values, language), do: {language, name, values[language]}
    known = Enum.map(named, &elem(&1, 0))
    rest = for {language, text} <- Enum.sort(values), language not in known, do: {language, language, text}
    named ++ rest
  end
end
