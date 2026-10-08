defmodule BrandoAdmin.Components.Form.FieldActions do
  @moduledoc """
  The AI actions a Blueprint declares on an input (`ai_actions:`, see
  `Brando.Blueprint.Forms.AIAction`), in two parts:

    * `menu/1`, beside the field's label: one action is a compact AI action
      button, several open a menu of AI items (`Brando.FloatingDropdown`).
      Choosing one sends `run_field_action` to the entry form, which builds
      the prompt from the unsaved form and hands it here.
    * this LiveComponent, under the input: it asks the model and shows the
      reply as a suggestion (`.ai-proposal`) the editor can edit, accept,
      discard or ask for again. Accepting sends the text to the form, which
      writes it into the field as unsaved input (`accept_field_action`).
      Nothing is written to the field until then.

  Both render only for top-level inputs in an entry form, when `Brando.AI`
  is configured for the action's model.
  """
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator
  use Gettext, backend: Brando.Gettext

  alias Brando.AI.FieldAction
  alias BrandoAdmin.Components.AIAction

  @doc """
  The input's actions that can run, with their labels translated: `[]` when
  there are none, or when the input is not in an entry form.
  """
  def available(%{field: field} = assigns) do
    actions = assigns[:ai_actions] || []

    if (actions != [] and assigns[:target]) && assigns[:form_id] do
      schema = field.form.source.data.__struct__

      actions
      |> Enum.filter(&FieldAction.available?/1)
      |> Enum.map(&%{name: &1.name, label: label(schema, &1)})
    else
      []
    end
  end

  def available(_assigns), do: []

  @doc "The panel's id for `field`; the form sends it the prompt."
  def id(%Phoenix.HTML.FormField{id: id}), do: "#{id}-ai-actions"

  @doc """
  An action's label from the Blueprint, translated in its domain, or its
  name when it has none (as an input without a label shows its field name).
  """
  def label(_schema, %{label: nil, name: name}), do: Brando.Utils.humanize(to_string(name))
  def label(schema, %{label: label}), do: schema |> g(label) |> Phoenix.HTML.safe_to_string()

  attr :field, Phoenix.HTML.FormField, required: true
  attr :actions, :list, required: true, doc: "from `available/1`"
  attr :target, :any, required: true, doc: "the entry form"

  def menu(%{actions: [action]} = assigns) do
    assigns = assign(assigns, :action, action)

    ~H"""
    <div class="field-ai-menu">
      <AIAction.button
        size={:compact}
        phx-click="run_field_action"
        phx-target={@target}
        phx-value-field={@field.field}
        phx-value-action={@action.name}
        data-testid="field-ai-action"
      >
        {@action.label}
      </AIAction.button>
    </div>
    """
  end

  def menu(assigns) do
    assigns = assign(assigns, :menu_id, "#{assigns.field.id}-ai-menu")

    ~H"""
    <div id={@menu_id} class="field-ai-menu" phx-hook="Brando.FloatingDropdown" data-placement="bottom-end">
      <AIAction.button
        size={:compact}
        popovertarget={"#{@menu_id}-items"}
        aria-haspopup="true"
        aria-expanded="false"
        data-testid="field-ai-menu"
      >
        {gettext("Write with AI")}<.icon name="chevron-down" class="field-ai-chevron" />
      </AIAction.button>
      <div id={"#{@menu_id}-items"} class="field-ai-menu-items" popover="auto">
        <button
          :for={action <- @actions}
          type="button"
          phx-click="run_field_action"
          phx-target={@target}
          phx-value-field={@field.field}
          phx-value-action={action.name}
        >
          <span>{action.label}</span><.icon name="sparkles" />
        </button>
      </div>
    </div>
    """
  end

  ## The suggestion

  @impl true
  def mount(socket) do
    {:ok, assign(socket, proposal: nil, request: 0)}
  end

  # From the form: the prompt for an action an editor chose.
  @impl true
  def update(%{run: %{action: action, label: label} = run}, socket) do
    request = socket.assigns.request + 1
    proposal = %{action: action, label: label, max: run[:max], status: :running, text: nil, error: nil}

    socket =
      socket
      |> cancel_async(:generate)
      |> assign(request: request, proposal: proposal)

    case run do
      %{error: reason} ->
        {:ok, fail(socket, reason)}

      %{prompt: prompt, ai_opts: ai_opts} ->
        {:ok,
         start_async(
           socket,
           :generate,
           Brando.Tenant.capture_context(fn -> Brando.AI.generate_text(prompt, ai_opts) end)
         )}
    end
  end

  def update(assigns, socket) do
    {:ok, assign(socket, Map.take(assigns, [:id, :field, :form_target, :form_id, :type]))}
  end

  @impl true
  def handle_async(:generate, {:ok, {:ok, %{text: text}}}, socket) do
    text = FieldAction.clean(text)

    if text == "",
      do: {:noreply, fail(socket, :empty_response)},
      else: {:noreply, update(socket, :proposal, &%{&1 | status: :ready, text: text})}
  end

  def handle_async(:generate, {:ok, {:error, reason}}, socket), do: {:noreply, fail(socket, reason)}
  def handle_async(:generate, {:exit, _reason}, socket), do: {:noreply, fail(socket, :failed)}

  defp fail(socket, reason) do
    update(socket, :proposal, &%{&1 | status: :failed, error: Brando.AI.error_message(reason)})
  end

  # The suggestion as the editor changed it, sent as they leave it: before
  # the Accept click that follows.
  @impl true
  def handle_event("edit", %{"value" => text}, %{assigns: %{proposal: %{status: :ready}}} = socket) do
    {:noreply, update(socket, :proposal, &%{&1 | text: text})}
  end

  def handle_event("edit", _params, socket), do: {:noreply, socket}

  def handle_event("accept", _params, %{assigns: %{proposal: %{status: :ready, text: text}}} = socket) do
    send_update(BrandoAdmin.Components.Form,
      id: socket.assigns.form_id,
      event: "accept_field_action",
      field_name: socket.assigns.field.name,
      field: socket.assigns.field.field,
      text: text
    )

    {:noreply, assign(socket, :proposal, nil)}
  end

  def handle_event("accept", _params, socket), do: {:noreply, socket}

  def handle_event("discard", _params, socket) do
    {:noreply, socket |> cancel_async(:generate) |> assign(:proposal, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="field-ai-actions" data-testid="field-ai-suggestion" role="status" aria-live="polite">
      <div :if={@proposal} class="ai-proposal" data-status={@proposal.status}>
        <p class="ai-proposal-label">
          <.icon name="sparkles" />
          <span :if={@proposal.status == :running}>{gettext("Writing…")}</span>
          <span :if={@proposal.status != :running}>{gettext("AI suggestion")}</span>
          <span class="field-ai-action-name">{@proposal.label}</span>
        </p>

        <%= if @proposal.status == :ready do %>
          <%!-- Outside the entry form (`form` names no form), so editing it
                is not editing the field. A new suggestion is a new element. --%>
          <textarea
            id={"#{@id}-text-#{@request}"}
            class="ai-proposal-field"
            form={"#{@id}-detached"}
            rows={rows(@proposal.text, @type)}
            phx-blur="edit"
            phx-target={@myself}
            aria-label={gettext("Suggested text")}
          >{@proposal.text}</textarea>
          <p
            :if={@proposal.max}
            class="field-ai-count"
            data-over={to_string(String.length(@proposal.text) > @proposal.max)}
          >
            {gettext("%{count} of at most %{max} characters", count: String.length(@proposal.text), max: @proposal.max)}
          </p>
        <% end %>

        <p :if={@proposal.status == :failed} class="field-ai-error" role="alert">{@proposal.error}</p>

        <div class="ai-proposal-actions">
          <button
            :if={@proposal.status == :ready}
            type="button"
            class="field-ai-button primary"
            phx-click="accept"
            phx-target={@myself}
          >
            {gettext("Accept")}
          </button>
          <button type="button" class="field-ai-button" phx-click="discard" phx-target={@myself}>
            {if @proposal.status == :running, do: gettext("Cancel"), else: gettext("Discard")}
          </button>
          <AIAction.button
            :if={@proposal.status != :running}
            phx-click="run_field_action"
            phx-target={@form_target}
            phx-value-field={@field.field}
            phx-value-action={@proposal.action}
          >
            {gettext("Try again")}
          </AIAction.button>
        </div>
      </div>
    </div>
    """
  end

  defp rows(text, :text), do: min(max(div(String.length(text), 90) + 1, 2), 4)
  defp rows(text, _type), do: min(max(div(String.length(text), 80) + 1 + count_breaks(text), 3), 12)

  defp count_breaks(text), do: text |> String.graphemes() |> Enum.count(&(&1 == "\n"))
end
