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
      <.icon name="circle-check" class="chip-icon" />
      <span class="grid-icon"><.icon name="check" /></span>
      <span class="content">
        {render_slot(@inner_block)}
      </span>
    </div>
    <div :if={!@cond} class="checklist-item false">
      <.icon name="circle-x" class="chip-icon" />
      <span class="grid-icon"><.icon name="x" /></span>
      <span class="content">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  attr :count, :integer, required: true
  slot :inner_block, required: true

  @doc """
  A line of a `grid` checklist with a number where the ✓/✗ goes, for a count
  of something: `<.checklist_count count={3}>images</.checklist_count>`.
  """
  def checklist_count(assigns) do
    ~H"""
    <div class={["checklist-item", "count", @count == 0 && "zero"]}>
      <span class="grid-icon">{@count}</span>
      <span class="content">{render_slot(@inner_block)}</span>
    </div>
    """
  end
end
