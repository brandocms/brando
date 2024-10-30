defmodule BrandoAdmin.Components.Content.List.Checklist do
  use BrandoAdmin, :component

  slot :inner_block, required: true
  attr :tiny, :boolean, default: false

  def checklist(assigns) do
    ~H"""
    <div class={["checklist", @tiny && "tiny"]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :cond, :any, required: true
  slot :inner_block, required: true

  def checklist_item(assigns) do
    assigns = assign(assigns, :cond, !!assigns.cond)

    ~H"""
    <div :if={@cond} class="checklist-item true">
      <.icon name="hero-check-circle" />
      <span class="content">
        <%= render_slot(@inner_block) %>
      </span>
    </div>
    <div :if={!@cond} class="checklist-item false">
      <.icon name="hero-x-circle" /><span class="content"><%= render_slot(@inner_block) %></span>
    </div>
    """
  end
end
