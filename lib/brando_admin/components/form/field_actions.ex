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

  Both render only for top-level inputs in an entry form and the meta fields
  in its Meta drawer, when `Brando.AI` is configured for the action's model.
  The actions come from `Brando.AI.FieldAction.for_field/3`.
  """
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator
  use Gettext, backend: Brando.Gettext

  alias Brando.AI.FieldAction
  alias BrandoAdmin.Components.AIAction

  @doc """
  The input's actions that can run, with their labels translated: `[]` when
  there are none, when the input is not in an entry form, or when it is
  read-only or disabled.
  """
  def available(%{field: field} = assigns) do
    actions = assigns[:ai_actions] || []

    if (actions != [] and assigns[:target]) && assigns[:form_id] && !locked_input?(assigns) do
      schema = field.form.source.data.__struct__

      actions
      |> Enum.filter(&FieldAction.available?/1)
      |> Enum.map(&%{name: &1.name, label: label(schema, &1)})
    else
      []
    end
  end

  def available(_assigns), do: []

  # A read-only or disabled input: its options as `Fieldset.Field` resolved
  # them for this user, or the component's own assigns.
  defp locked_input?(assigns) do
    assigns[:disabled] == true or assigns[:readonly] == true or locked?(assigns[:opts], assigns[:current_user])
  end

  @doc """
  Whether an input's options make it read-only or disabled for `user`:
  `true`, or `:unless_superuser` for anyone else. Actions are neither offered
  nor run nor accepted on such an input.
  """
  def locked?(opts, user) do
    Enum.any?([:readonly, :disabled], fn key ->
      case Keyword.get(opts || [], key) do
        true -> true
        :unless_superuser -> not match?(%{role: :superuser}, user)
        _ -> false
      end
    end)
  end

  @doc """
  The panel's id for `field`; the form sends it the prompt. The Meta drawer's
  panel (`:meta`) has its own, so a meta field that is also an input in a tab
  has two panels, each with its own suggestion.
  """
  def id(field, scope \\ nil)
  def id(%Phoenix.HTML.FormField{id: id}, nil), do: "#{id}-ai-actions"
  def id(%Phoenix.HTML.FormField{id: id}, :meta), do: "#{id}-meta-ai-actions"

  @doc "The panel ids `field` can have, for checking the one an event names."
  def ids(field), do: [id(field), id(field, :meta)]

  @doc """
  An action's label from the Blueprint, translated in its domain, or its
  name when it has none (as an input without a label shows its field name).
  The `:generate` that a deprecated `ai:` or a site prompt gives a field is
  "Generate".
  """
  def label(_schema, %{label: nil, origin: origin}) when origin in [:ai, :site], do: gettext("Generate")
  def label(_schema, %{label: nil, name: name}), do: Brando.Utils.humanize(to_string(name))
  def label(schema, %{label: label}), do: schema |> g(label) |> Phoenix.HTML.safe_to_string()

  attr :field, Phoenix.HTML.FormField, required: true
  attr :actions, :list, required: true, doc: "from `available/1`"
  attr :target, :any, required: true, doc: "the entry form"
  attr :panel, :string, default: nil, doc: "the suggestion panel's id, `id/2` (default `id(field)`)"

  def menu(%{actions: [action]} = assigns) do
    assigns = assigns |> assign(:action, action) |> assign_panel()

    ~H"""
    <div class="field-ai-menu">
      <AIAction.button
        size={:compact}
        phx-click="run_field_action"
        phx-target={@target}
        phx-value-field={@field.field}
        phx-value-action={@action.name}
        phx-value-panel={@panel}
        data-testid="field-ai-action"
      >
        {@action.label}
      </AIAction.button>
    </div>
    """
  end

  def menu(assigns) do
    assigns = assign_panel(assigns)
    # `…-ai-menu`, or `…-meta-ai-menu` in the Meta drawer
    assigns = assign(assigns, :menu_id, String.replace_suffix(assigns.panel, "-actions", "-menu"))

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
          phx-value-panel={@panel}
        >
          <span>{action.label}</span><.icon name="sparkles" />
        </button>
      </div>
    </div>
    """
  end

  defp assign_panel(assigns), do: assign(assigns, :panel, assigns[:panel] || id(assigns.field))

  ## The suggestion

  @impl true
  def mount(socket) do
    {:ok, assign(socket, proposal: nil, request: 0)}
  end

  # From the form: an action an editor chose. Its prompt is built in the
  # request's task (`build`), since reading the block editor's content means
  # rendering it. Each request has its own key, so a cancelled or replaced
  # one cannot touch the suggestion when it ends.
  @impl true
  def update(%{run: run}, socket) do
    request = socket.assigns.request + 1

    proposal = %{
      action: run.action,
      label: run.label,
      max: run[:max],
      original: run[:original],
      warning: run[:warning],
      status: :running,
      text: nil,
      error: nil,
      conflict: false
    }

    %{build: build, ai_opts: ai_opts} = run

    task =
      Brando.Tenant.capture_context(fn ->
        with {:ok, prompt} <- build.(), do: Brando.AI.generate_text(prompt, ai_opts)
      end)

    {:ok,
     socket
     |> cancel_request()
     |> assign(request: request, proposal: proposal)
     |> start_async({:generate, request}, task)}
  end

  # From the form, after Accept: written, or the field changed since the
  # action ran and the editor is asked first.
  def update(%{accept_result: :written}, socket), do: {:ok, assign(socket, :proposal, nil)}

  def update(%{accept_result: :conflict}, %{assigns: %{proposal: %{status: :ready}}} = socket),
    do: {:ok, update(socket, :proposal, &%{&1 | conflict: true})}

  def update(%{accept_result: _}, socket), do: {:ok, socket}

  def update(assigns, socket) do
    {:ok, assign(socket, Map.take(assigns, [:id, :field, :form_target, :form_id, :type]))}
  end

  defp cancel_request(socket), do: cancel_async(socket, {:generate, socket.assigns.request})

  # Only the current request's result counts, and only while it runs.
  @impl true
  def handle_async({:generate, request}, result, %{assigns: %{request: request, proposal: %{status: :running}}} = socket) do
    {:noreply, finish(socket, result)}
  end

  def handle_async({:generate, _stale}, _result, socket), do: {:noreply, socket}

  defp finish(socket, {:ok, {:ok, %{text: text}}}) do
    case FieldAction.clean(text, socket.assigns[:type]) do
      "" -> fail(socket, :empty_response)
      text -> update(socket, :proposal, &%{&1 | status: :ready, text: text})
    end
  end

  defp finish(socket, {:ok, {:error, reason}}), do: fail(socket, reason)
  defp finish(socket, {:exit, _reason}), do: fail(socket, :failed)

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

  # The form writes it, unless the field changed since the action ran and
  # the editor has not said to replace it (`replace`).
  def handle_event("accept", params, %{assigns: %{proposal: %{status: :ready} = proposal}} = socket) do
    send_update(BrandoAdmin.Components.Form,
      id: socket.assigns.form_id,
      event: "accept_field_action",
      panel: socket.assigns.id,
      field_name: socket.assigns.field.name,
      field: socket.assigns.field.field,
      text: proposal.text,
      original: proposal.original,
      replace: params["replace"] == "true"
    )

    {:noreply, socket}
  end

  def handle_event("accept", _params, socket), do: {:noreply, socket}

  def handle_event("discard", _params, socket) do
    {:noreply, socket |> cancel_request() |> assign(request: socket.assigns.request + 1, proposal: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="field-ai-actions" data-testid="field-ai-suggestion" role="status" aria-live="polite">
      <div :if={@proposal} class="ai-proposal" data-status={@proposal.status}>
        <p class="ai-proposal-label">
          <.icon name="sparkles" />
          <span :if={@proposal.status == :running}>{gettext("Writing…")}</span>
          <span :if={@proposal.status == :ready}>{gettext("AI suggestion")}</span>
          <span class={@proposal.status != :failed && "field-ai-action-name"}>{@proposal.label}</span>
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
            {gettext("%{count} of %{max} characters", count: String.length(@proposal.text), max: @proposal.max)}
          </p>
        <% end %>

        <p :if={@proposal.status == :ready && @proposal.warning} class="field-ai-warning" data-testid="field-ai-warning">
          {@proposal.warning}
        </p>
        <p :if={@proposal.conflict} class="field-ai-error" role="alert" data-testid="field-ai-conflict">
          {gettext("The field has changed since the suggestion was asked for. Replace it?")}
        </p>
        <p :if={@proposal.status == :failed} class="field-ai-error" role="alert">{@proposal.error}</p>

        <div class="ai-proposal-actions">
          <button
            :if={@proposal.status == :ready}
            type="button"
            class="field-ai-button primary"
            phx-click="accept"
            phx-value-replace={to_string(@proposal.conflict)}
            phx-target={@myself}
          >
            {if @proposal.conflict, do: gettext("Replace"), else: gettext("Accept")}
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
            phx-value-panel={@id}
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

  defp count_breaks(text), do: length(String.split(text, "\n")) - 1
end
