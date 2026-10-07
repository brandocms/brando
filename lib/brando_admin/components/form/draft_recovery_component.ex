defmodule BrandoAdmin.Components.Form.DraftRecoveryComponent do
  @moduledoc """
  The form's recovery-copy status and panel, in a component of its own.

  The state changes on every autosave. Rendered in the form's own template,
  each change put the form in the diff, and LiveView then patched the whole
  form: tens of thousands of elements on a case with blocks, 70-100 ms per
  edit. Here only this component is patched. The form hands the state over
  with `send_update/2` from `Drafts.put_draft/2`; `seed` is the state at the
  form's first render, before the component existed to receive it.
  """
  use Phoenix.LiveComponent

  alias BrandoAdmin.Components.Form.DraftRecovery

  @doc "The component id for the form with `form_id`."
  def id(form_id), do: "#{form_id}-draft-recovery-component"

  @doc "The id of the form's save state (`part={:status}`) beside its Save."
  def status_id(form_id), do: "#{form_id}-save-state-component"

  def mount(socket), do: {:ok, socket |> assign(:state, nil) |> assign(:part, :all) |> assign(:saved_at, nil)}

  def update(%{state: state}, socket), do: {:ok, assign(socket, :state, state)}

  # From the form's render. The seed only fills an empty state: a re-render of
  # the form passes the same, older seed, which must not undo a newer state.
  def update(assigns, socket) do
    {seed, assigns} = Map.pop(assigns, :seed)

    socket = assign(socket, assigns)
    socket = if is_nil(socket.assigns.state), do: assign(socket, :state, seed), else: socket

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <%!-- A stateful component needs a static root tag; `display: contents`
          keeps the form's layout as it was without it. --%>
    <div class="draft-recovery-host" style="display: contents">
      <DraftRecovery.render
        id={@dom_id}
        part={@part}
        state={@state}
        saved_at={@saved_at}
        target={@target}
        entry_id={@entry_id}
      />
    </div>
    """
  end
end
