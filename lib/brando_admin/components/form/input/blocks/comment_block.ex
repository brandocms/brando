defmodule BrandoAdmin.Components.Form.Input.Blocks.CommentBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block

  prop block, :form
  prop base_form, :form
  prop index, :integer
  prop block_count, :integer
  prop is_ref?, :boolean, default: false
  prop ref_description, :string
  prop belongs_to, :string
  prop data_field, :atom

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data text_type, :string
  data initial_props, :map
  data block_data, :map

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    block_data = List.first(inputs_for(assigns.block, :data))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:uid, v(assigns.block, :uid))}
  end

  def render(assigns) do
    ~F"""
    <div
      class="comment-block"
      id={"#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Block
        id={"#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>
          {gettext("Not shown...")}
        </:description>
        <:config>
          <Input.Textarea form={@block_data} field={:text} />
        </:config>
        <div>
          {#if v(@block_data, :text)}
            {v(@block_data, :text) |> raw}
          {/if}
        </div>
      </Block>
    </div>
    """
  end
end
