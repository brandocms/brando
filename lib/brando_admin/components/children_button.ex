defmodule BrandoAdmin.Components.ChildrenButton do
  use Surface.LiveComponent

  prop entry, :any, required: true
  prop fields, :list, required: true

  data count, :integer
  data active, :boolean

  def mount(socket) do
    {:ok, assign(socket, :active, false)}
  end

  def update(assigns, socket) do
    entry = assigns.entry
    fields = assigns.fields
    count = Enum.reduce(fields, 0, fn x, acc -> Enum.count(Map.get(entry, x)) + acc end)
    singular = entry.__struct__.__naming__().singular

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       count: count,
       singular: singular
     )}
  end

  def render(assigns) do
    ~F"""
    <div class="children-button">
      <button
        :on-click="toggle"
        type="button"
        data-testid="children-button"
        class={active: @active}
        phx-page-loading>
        {#if @active}
          Close
        {#else}
          + {@count}
        {/if}
      </button>
    </div>
    """
  end

  def handle_event(
        "toggle",
        _,
        %{assigns: %{fields: child_fields, singular: singular, entry: %{id: id}}} = socket
      ) do
    id = "list-row-#{singular}-#{id}"

    send_update(BrandoAdmin.Components.Content.List.Row,
      id: id,
      show_children: !socket.assigns.active,
      child_fields: child_fields
    )

    {:noreply, assign(socket, :active, !socket.assigns.active)}
  end
end
