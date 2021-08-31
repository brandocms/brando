defmodule BrandoAdmin.Components.Form.Input.Blocks.DatasourceBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias Surface.Components.Form.TextInput
  alias Surface.Components.Form.Inputs
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.MapInputs
  import Brando.Gettext

  prop base_form, :any
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop is_ref?, :boolean, default: false

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  # def v(form, field), do: input_value(form, field)
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
        <:description>{v(@block, :data).description}</:description>
        <:config>
          {#for block_data <- inputs_for(@block, :data)}
            <TextInput class="text" form={block_data} field={:module} />
            <TextInput class="text" form={block_data} field={:type} />
            <TextInput class="text" form={block_data} field={:query} />
            <TextInput class="text" form={block_data} field={:code} />
            <TextInput class="text" form={block_data} field={:arg} />
            <TextInput class="text" form={block_data} field={:limit} />
            <TextInput class="text" form={block_data} field={:ids} />
            <TextInput class="text" form={block_data} field={:description} />
            <TextInput class="text" form={block_data} field={:module_id} />
          {/for}
        </:config>
        {#for block_data <- inputs_for(@block, :data)}
          <div class="datasource-block">
            <div class="villain-block-datasource-info">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="128"><path fill="none" d="M0 0h24v24H0z"/><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z"/></svg>

              <div class="inside">
                <p>{gettext("Datasource")} — {v(@block, :data).description}</p>
                <p>
                  <small>
                    <code>
                      {v(@block, :data).module}<br>
                      {v(@block, :data).type}|{v(@block, :data).query}
                    </code>
                  </small>
                </p>
              </div>
            </div>
          </div>
        {/for}
      </Block>
    </div>
    """
  end
end
