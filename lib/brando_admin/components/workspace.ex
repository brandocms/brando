defmodule BrandoAdmin.Components.Workspace do
  @moduledoc false
  use BrandoAdmin, :component

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :eyebrow, :string, default: nil, doc: "a short context label above the title, e.g. \"Configuration\""
  attr :icon, :string, default: nil, doc: "a Lucide icon name, usually the blueprint's (`@page_icon`)"
  slot :inner_block

  def header(assigns) do
    ~H"""
    <header class="workspace-heading">
      <div>
        <span :if={@eyebrow} class="workspace-eyebrow">{@eyebrow}</span>
        <h1><.icon :if={@icon} name={@icon} class="workspace-heading-icon" />{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
      <div :if={@inner_block != []} class="workspace-heading-actions">
        {render_slot(@inner_block)}
      </div>
    </header>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true

  def empty(assigns) do
    ~H"""
    <div class="workspace-empty">
      <h3>{@title}</h3>
      <p>{@description}</p>
    </div>
    """
  end
end
