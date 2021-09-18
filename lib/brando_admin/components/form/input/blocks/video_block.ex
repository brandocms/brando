defmodule BrandoAdmin.Components.Form.Input.Blocks.VideoBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.Input.Blocks.Block

  prop base_form, :any
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop is_ref?, :boolean, default: false
  prop belongs_to, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def render(assigns) do
    ~F"""
    <div
      id={"#{v(@block, :uid)}-wrapper"}
      data-block-index={@index}
      data-block-uid={v(@block, :uid)}>
      <Block
        id={"#{v(@block, :uid)}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>{v(@block, :data).url}</:description>
        <:config>
          {#for block_data <- inputs_for(@block, :data)}
            {text_input block_data, :url, class: "text"}
            {text_input block_data, :source, class: "text"}
            {text_input block_data, :remote_id, class: "text"}
            {text_input block_data, :width, class: "text"}
            {text_input block_data, :height, class: "text"}
            {text_input block_data, :thumbnail_url, class: "text"}
          {/for}
        </:config>
        {#for _block_data <- inputs_for(@block, :data)}
          <div class="picture-block">
            Vid!
          </div>
        {/for}
      </Block>
    </div>
    """
  end
end
