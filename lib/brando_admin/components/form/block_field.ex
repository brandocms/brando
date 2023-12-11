defmodule BrandoAdmin.Components.Form.BlockField do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Block
  # import Brando.Gettext

  def update(assigns, socket) do
    entry_blocks_forms =
      Enum.map(assigns.entry.entry_blocks, &to_change_form(&1, %{}, assigns.current_user))

    socket =
      socket
      |> assign(assigns)
      |> stream(:entry_blocks_forms, entry_blocks_forms)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div
      id="blocks"
      phx-update="stream"
      phx-hook="Brando.SortableInputsFor"
      data-sortable-id="sortable-blocks"
      data-sortable-handle=".sort-handle"
      data-sortable-selector=".block"
    >
      <button type="button">
        Add block
      </button>
      <div
        :for={{id, entry_block_form} <- @streams.entry_blocks_forms}
        id={id}
        data-id={entry_block_form.data.id}
        data-parent_id={entry_block_form.data.block.parent_id}
        class="block draggable"
      >
        <.live_component
          module={Block}
          id={"#{@id}-blocks-#{id}"}
          uid={entry_block_form.data.block.uid}
          type={entry_block_form.data.block.type}
          multi={entry_block_form.data.block.multi}
          children={entry_block_form.data.block.children}
          parent_id={entry_block_form.data.block.parent_id}
          form={entry_block_form}
        >
          BLOCK CONTENT: <%= entry_block_form.data.block.uid %> -- <%= entry_block_form.data.block.type %> [multi:<%= entry_block_form.data.block.multi %>]
        </.live_component>
      </div>
    </div>
    """
  end

  defp to_change_form(entry_block_or_cs, params, user, action \\ nil) do
    changeset =
      entry_block_or_cs
      |> Brando.Pages.Page.Blocks.changeset(params, user)
      |> Map.put(:action, action)

    to_form(changeset,
      as: "entry_block",
      id: "entry_block_form-#{changeset.data.id}"
    )
  end
end
