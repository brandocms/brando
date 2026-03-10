defmodule BrandoAdmin.Components.Form.Input.Image.FocalPoint do
  @moduledoc false
  use BrandoAdmin, :live_component

  def update(%{image: %{image: image}, form_id: form_id, form_name: form_name}, socket) do
    image_identifier = image_identifier(image)
    {incoming_x, incoming_y} = focal_coords(image)

    socket =
      socket
      |> assign(:form_id, form_id)
      |> assign(:form_name, form_name)
      |> maybe_assign_image_state(image_identifier, incoming_x, incoming_y)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"#{@form_id}-#{@image_identifier}-image-focal-point"}
      class="focus-point"
      phx-hook="Brando.FocalPoint"
      data-x={"#{@x}"}
      data-y={"#{@y}"}
    >
      <input type="hidden" name={"#{@form_name}[focal][x]"} value={@x} />
      <input type="hidden" name={"#{@form_name}[focal][y]"} value={@y} />

      <div phx-update="ignore" id={"#{@form_id}-#{@image_identifier}-image-focal-point-pin"}>
        <div class="focus-point-pin"></div>
      </div>
    </div>
    """
  end

  def handle_event("update_focal_point", %{"x" => x, "y" => y}, socket) do
    {:noreply, assign(socket, x: x, y: y)}
  end

  defp maybe_assign_image_state(socket, image_identifier, incoming_x, incoming_y) do
    previous_identifier = socket.assigns[:image_identifier]

    socket =
      if previous_identifier != image_identifier do
        socket
        |> assign(:x, incoming_x)
        |> assign(:y, incoming_y)
      else
        socket
      end

    assign(socket, :image_identifier, image_identifier)
  end

  defp focal_coords(%{focal: %{x: x, y: y}}), do: {x, y}
  defp focal_coords(_), do: {50, 50}

  defp image_identifier(%{id: id}) when not is_nil(id), do: to_string(id)
  defp image_identifier(%{path: path}) when is_binary(path) and path != "", do: path
  defp image_identifier(_), do: "image"
end
