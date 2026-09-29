defmodule BrandoAdmin.Components.Content.List.Checklist do
  @moduledoc false
  use BrandoAdmin, :component

  attr :tiny, :boolean, default: false

  attr :grid, :boolean,
    default: false,
    doc: "One bordered line per item, with a plain coloured ✓/✗ in its own column"

  slot :inner_block, required: true

  def checklist(assigns) do
    ~H"""
    <div class={["checklist", @tiny && "tiny", @grid && "grid"]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :cond, :any, required: true
  slot :inner_block, required: true

  def checklist_item(assigns) do
    assigns = assign(assigns, :cond, !!assigns.cond)

    ~H"""
    <%!-- Both icons: the chip style shows the circled one, a `grid` list the plain one. --%>
    <div :if={@cond} class="checklist-item true">
      <.icon name="hero-check-circle" class="chip-icon" />
      <span class="grid-icon"><.icon name="hero-check" /></span>
      <span class="content">
        {render_slot(@inner_block)}
      </span>
    </div>
    <div :if={!@cond} class="checklist-item false">
      <.icon name="hero-x-circle" class="chip-icon" />
      <span class="grid-icon"><.icon name="hero-x-mark" /></span>
      <span class="content">{render_slot(@inner_block)}</span>
    </div>
    """
  end
end
