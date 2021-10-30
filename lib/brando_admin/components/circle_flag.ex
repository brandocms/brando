defmodule BrandoAdmin.Components.CircleFlag do
  use Surface.Component

  prop language, :string, required: true
  data uid, :string

  def render(assigns) do
    assigns = assign_new(assigns, :uid, fn -> Brando.Utils.generate_uid() end)

    ~F"""
    <div class="circle circle-flag">
      {@language}
    </div>
    """
  end
end
