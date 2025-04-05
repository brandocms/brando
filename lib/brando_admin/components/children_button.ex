defmodule BrandoAdmin.Components.ChildrenButton do
  # TODO: Can this be a function component with its event handled in the row instead?
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:text, fn -> nil end)
     |> assign(:active, false)}
  end

  def update(assigns, socket) do
    entry = assigns.entry
    fields = assigns.fields || []
    count = Enum.reduce(fields, 0, fn x, acc -> Enum.count(Map.get(entry, x) || []) + acc end)
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
    ~H"""
    <div class={["children-button", @count == 0 && "hidden"]}>
      <button
        phx-click={JS.push("toggle", target: @myself)}
        type="button"
        data-testid="children-button"
        class={[@active, @text]}
      >
        {(@active && gettext("Close")) || "+ #{@count}"}
        <%= if @text do %>
          {@text}
        <% end %>
      </button>
    </div>
    """
  end

  def handle_event("toggle", _, %{assigns: %{fields: child_fields, singular: singular, entry: %{id: id}}} = socket) do
    id = "list-row-#{singular}-#{id}"

    send_update(BrandoAdmin.Components.Content.List.Row,
      id: id,
      show_children: !socket.assigns.active,
      child_fields: child_fields
    )

    {:noreply, assign(socket, :active, !socket.assigns.active)}
  end
end
