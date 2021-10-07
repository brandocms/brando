defmodule BrandoAdmin.Components.CircleFlag do
  use Surface.Component

  prop language, :string, required: true
  data uid, :string

  def mount(socket) do
    {:ok, assign(socket, :uid, Brando.Utils.generate_uid())}
  end

  def render(assigns) do
    ~F"""
    <div class="circle circle-flag">
      {@language}
    </div>
    """
  end
end
