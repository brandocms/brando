defmodule BrandoAdmin.Components.Form.Input.Image.FocalPoint do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  # prop form, :form
  # prop field_name, :atom
  # prop focal, :any

  # data x, :number
  # data y, :number

  def update(%{image: %{image: %{focal: %{x: x, y: y}}}} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:x, fn -> x end)
      |> assign_new(:y, fn -> y end)

    {:ok, socket}
  end

  def update(%{image: %{image: %{focal: nil}}} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:x, fn -> 50 end)
      |> assign_new(:y, fn -> 50 end)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"#{@form.id}-#{@image.image.id}-image-focal-point"}
      class="focus-point"
      phx-hook="Brando.FocalPoint"
      data-x={"#{@x}"}
      data-y={"#{@y}"}
    >
      <input type="hidden" name={"#{@form.name}[focal][x]"} value={@x} />
      <input type="hidden" name={"#{@form.name}[focal][y]"} value={@y} />

      <div phx-update="ignore" id={"#{@form.id}-#{@image.image.id}-image-focal-point-pin"}>
        <div class="focus-point-pin"></div>
      </div>
    </div>
    """
  end

  def handle_event("update_focal_point", %{"x" => x, "y" => y}, socket) do
    {:noreply, assign(socket, x: x, y: y)}
  end
end
