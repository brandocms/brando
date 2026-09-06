defmodule BrandoAdmin.Components.Form.UnusedNotes do
  @moduledoc "Field-local controls for notes stored in a separate block field."
  use BrandoAdmin, :live_component

  alias BrandoAdmin.Components.Form.Block.Render

  def mount(socket), do: {:ok, assign(socket, :items, [])}

  def update(%{event: "notes", items: items}, socket), do: {:ok, assign(socket, :items, items)}

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    send_update(socket.assigns.form_target,
      event: "inspect_field_notes",
      field: socket.assigns.field,
      reply_to: socket.assigns.myself
    )

    {:ok, socket}
  end

  def handle_event(action, %{"uid" => uid}, socket)
      when action in ["open_unused_collection", "restore_note_reference", "delete_unused_collection"] do
    send_update(socket.assigns.form_target,
      event: "field_note_action",
      field: socket.assigns.field,
      uid: uid,
      action: action
    )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <Render.unused_collections id={"#{@id}-list"} items={@items} target={@myself} />
    </div>
    """
  end
end
