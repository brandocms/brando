# TODO: DELETE
defmodule BrandoAdmin.Components.Form.Input.Blocks.Plus do
  use BrandoAdmin, :component

  # prop index, :integer
  # prop click, :event

  def render(assigns) do
    ~H"""
    <button class="block-plus" type="button" phx-value-index={@index} phx-click={@click}>
      <.icon name="hero-plus-circle-mini" />
    </button>
    """
  end
end
