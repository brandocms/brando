defmodule BrandoAdmin.Components.Form.Tab do
  @moduledoc false
  use BrandoAdmin, :component
  alias Phoenix.LiveView.JS

  attr :active_tab, :string, required: true
  slot :buttons, required: true
  slot :tabs, required: true

  def tabs(assigns) do
    ~H"""
    <div class="tab-container">
      <div class="tab-header">
        {render_slot(@buttons)}
      </div>
      <div class="tab-content">
        {render_slot(@tabs)}
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :active_tab, :string, required: true
  attr :target, :any, required: true

  def tab_button(assigns) do
    ~H"""
    <button
      type="button"
      class={["tab-button", @active_tab == @id && "active"]}
      phx-click={JS.push("select_tab", value: %{tab: @id}, target: @target)}
    >
      {@label}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :active_tab, :string, required: true
  slot :inner_block, required: true

  def tab_content(assigns) do
    ~H"""
    <div :if={@active_tab == @id} class="tab-panel" id={"tab-panel-#{@id}"}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
