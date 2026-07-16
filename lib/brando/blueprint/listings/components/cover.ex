defmodule Brando.Blueprint.Listings.Components.Cover do
  @moduledoc """
  Opt-in cover-image component for custom Blueprint listing rows.
  """
  use Phoenix.Component

  alias BrandoAdmin.Components.Image

  attr :class, :any, default: nil
  attr :padded, :boolean, default: false
  attr :circular, :boolean, default: false
  attr :image, :map, required: true
  attr :columns, :integer, required: true
  attr :size, :atom, default: :thumb
  attr :offset, :integer, default: nil
  attr :top, :boolean, default: false

  @doc "Renders an image cover cell."
  def cover(assigns) do
    ~H"""
    <div class={[
      "cover",
      @class,
      @padded && "padded",
      @circular && "circular",
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}",
      @top && "top"
    ]}>
      <Image.image image={@image} size={@size} />
    </div>
    """
  end
end
