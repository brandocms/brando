defmodule BrandoAdmin.Components.Form.Input.Blocks.ContainerBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.Blocks.Block

  prop block, :any
  prop base_form, :any
  prop index, :any
  # prop block_count, :integer

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data class, :string
  data blocks, :list
  data block_count, :integer
  data insert_index, :integer

  def v(form, field) do
    Ecto.Changeset.get_field(form.source, field)
  end

  def mount(socket) do
    {:ok, assign(socket, block_count: 0, insert_index: 0)}
  end

  def update(%{block: block} = assigns, socket) do
    block_data =
      block
      |> inputs_for(:data)
      |> List.first()

    blocks = v(block_data, :blocks)
    block_count = Enum.count(blocks)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(block, :uid))
     |> assign(:class, v(block_data, :class))
     |> assign(:blocks, blocks)
     |> assign(:block_count, block_count)}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-wrapper"}
      class="container-block"
      data-block-index={@index}
      data-block-uid={@uid}>
      <Block
        id={"#{@uid}-base"}
        index={@index}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>Container</:description>
        <:config></:config>
        {#if @class}

        {#else}
          Choose a section template here
        {/if}

        <Blocks.BlockRenderer
          id={"#{@block.id}-container-blocks"}
          base_form={@base_form}
          blocks={@blocks}
          block_count={@block_count}
          insert_index={@insert_index}
          insert_block="insert_block"
          insert_section="insert_section"
          show_module_picker="show_module_picker"
          duplicate_block="duplicate_block" />
      </Block>
    </div>
    """
  end
end
