defmodule BrandoAdmin.Components.Form.Input.Blocks.BlockRenderer do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input.Blocks

  prop blocks, :list, required: true
  prop block_count, :integer, required: true
  prop base_form, :form, required: true
  prop insert_index, :integer
  prop insert_block, :event, required: true
  prop insert_section, :event, required: true
  prop duplicate_block, :event, required: true
  prop show_module_picker, :event, required: true

  def render(assigns) do
    ~F"""
    <div class="blocks-wrapper">
      <Blocks.ModulePicker
        id={"#{@id}-module-picker"}
        insert_block={@insert_block}
        insert_section={@insert_section}
        insert_index={@insert_index} />

      {#if Enum.empty?(@blocks)}
        <div class="blocks-empty-instructions">
          Click the plus to start adding content blocks
        </div>
        <Blocks.Plus
          index={0}
          click={@show_module_picker} />
      {/if}

      {#for {block_form, index} <- Enum.with_index(@blocks)}
        <Blocks.DynamicBlock
          index={index}
          base_form={@base_form}
          block_count={@block_count}
          block={block_form}
          insert_block={@show_module_picker}
          duplicate_block={@duplicate_block} />
      {/for}
    </div>
    """
  end
end
