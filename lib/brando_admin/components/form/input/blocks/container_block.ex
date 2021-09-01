defmodule BrandoAdmin.Components.Form.Input.Blocks.ContainerBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Form.MapInputs
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.Blocks.Ref
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  prop block, :any
  prop base_form, :any
  prop index, :any
  prop block_count, :integer

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data class, :string
  data blocks, :list

  def v(form, field) do
    Ecto.Changeset.get_field(form.source, field)
  end

  def update(%{block: block} = assigns, socket) do
    block_data =
      block
      |> inputs_for(:data)
      |> List.first()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(block, :uid))
     |> assign(:class, v(block_data, :class))
     |> assign(:blocks, v(block_data, :blocks))}
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

        {inspect @blocks, pretty: true}
      </Block>
    </div>
    """
  end
end
