defmodule BrandoAdmin.Components.Form.Input.Image.FocalPoint do
  use Surface.LiveComponent
  use Phoenix.HTML

  prop form, :form
  prop field_name, :atom
  prop focal, :any

  data x, :number
  data y, :number

  def update(%{focal: %{x: x, y: y}} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:x, fn -> x end)
      |> assign_new(:y, fn -> y end)

    {:ok, socket}
  end

  def update(%{focal: nil} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:x, fn -> 50 end)
      |> assign_new(:y, fn -> 50 end)

    {:ok, socket}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@form.id}-#{@field_name}-image-focal-point"}
      class="focus-point"
      phx-hook="Brando.FocalPoint"
      data-field={"#{@field_name}"}
      data-x={"#{@x}"}
      data-y={"#{@y}"}>
      <input type="text" name={"#{@form.name}[#{@field_name}][focal][x]"} value={@x} />
      <input type="text" name={"#{@form.name}[#{@field_name}][focal][y]"} value={@y} />

      <div phx-update="ignore">
        <div class="focus-point-pin"></div>
      </div>
    </div>
    """
  end

  def handle_event("update_focal_point", %{"x" => x, "y" => y}, socket) do
    {:noreply, assign(socket, x: x, y: y)}
  end
end
