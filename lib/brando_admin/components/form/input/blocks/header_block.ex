defmodule BrandoAdmin.Components.Form.Input.Blocks.HeaderBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.Radios

  prop block, :any
  prop base_form, :any
  prop index, :any
  prop block_count, :integer
  prop is_ref?, :boolean, default: false

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
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>(H{v(@block, :data).level})</:description>
        <:config>
          {#for block_data <- inputs_for(@block, :data)}
            <Radios
              form={block_data}
              field={:level}
              label="Level"
              options={[
                %{label: "H1", value: 1},
                %{label: "H2", value: 2},
                %{label: "H3", value: 3},
                %{label: "H4", value: 4},
                %{label: "H5", value: 5},
                %{label: "H6", value: 6},
              ]} />
          {/for}
        </:config>
        {#for block_data <- inputs_for(@block, :data)}
          <div class="header-block">
            {textarea block_data, :text,
              id: "#{v(@block, :uid)}-textarea",
              class: "h#{v(block_data, :level)}",
              data_autosize: true,
              phx_debounce: 750,
              rows: 1
            }
            {hidden_input block_data, :class}
            {hidden_input block_data, :placeholder}
          </div>
        {/for}
      </Block>
    </div>
    """
  end
end
