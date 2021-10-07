defmodule BrandoAdmin.Components.Form.Input.Blocks.Plus do
  use Surface.Component

  prop index, :integer
  prop click, :event

  def render(assigns) do
    ~F"""
    <button
      class="block-plus"
      type="button"
      phx-value-index={@index}
      :on-click={@click}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 300 300">
        <circle
          cx="150"
          cy="150"
          r="142.7"
          stroke="#FFF"
          stroke-miterlimit="10" />
        <path
          fill="#FFF"
          d="M224.3 133.3v31.3H166v58.3h-31.3v-58.3H76.4v-31.3h58.3V75H166v58.3h58.3z" />
      </svg>
    </button>
    """
  end
end
