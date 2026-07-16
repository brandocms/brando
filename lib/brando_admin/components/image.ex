defmodule BrandoAdmin.Components.Image do
  @moduledoc """
  Focused image renderer shared by admin fields and Blueprint listing covers.

  This component deliberately avoids the general admin content component so
  low-level listing rows do not inherit unrelated modal, drawer, and layout
  dependencies.
  """
  use Phoenix.Component

  alias Brando.Images.Metadata
  alias Brando.Images.URL
  alias Brando.RuntimeConfig

  attr :image, :any
  attr :size, :atom
  slot :inner_block

  @doc "Renders an image or its processing/empty placeholder."
  def image(assigns) do
    path =
      if assigns.image && assigns.image.status == :processed do
        type = Metadata.type(assigns.image.path)

        URL.url(
          assigns.image,
          (type == :svg && :original) || assigns.size,
          prefix: RuntimeConfig.get(:media_url),
          cache: Map.get(assigns.image, :updated_at)
        )
      end

    focal = (assigns.image && assigns.image.focal) || %{x: 50, y: 50}
    orientation = Metadata.orientation(assigns.image)

    assigns =
      assigns
      |> assign(:path, path)
      |> assign(:focal, focal)
      |> assign(:orientation, orientation)

    ~H"""
    <%= if @image do %>
      <%= if @image.status == :processed do %>
        <div class="image-content" data-orientation={@orientation}>
          <img
            width={@image.width}
            height={@image.height}
            src={@path}
            data-focal-x={@focal.x}
            data-focal-y={@focal.y}
            style={"object-position: #{@focal.x}% #{@focal.y}%;"}
          />
          {render_slot(@inner_block)}
        </div>
      <% else %>
        <div class="img-placeholder">
          <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
            <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
          </svg>
          {render_slot(@inner_block)}
        </div>
      <% end %>
    <% else %>
      <div class="img-placeholder">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
          <path fill="none" d="M0 0h24v24H0z" /><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z" />
        </svg>
        {render_slot(@inner_block)}
      </div>
    <% end %>
    """
  end
end
