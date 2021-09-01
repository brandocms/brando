defmodule BrandoAdmin.Components.Form.Input.Blocks.ModulePicker do
  use Surface.LiveComponent
  use Phoenix.HTML

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def render(assigns) do
    ~F"""

    """
  end
end
