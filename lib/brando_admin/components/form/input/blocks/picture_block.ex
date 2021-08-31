defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias Surface.Components.Form.TextInput
  alias Surface.Components.Form.Inputs
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.MapInputs

  prop base_form, :any
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop is_ref?, :boolean, default: false
  prop ref_name, :string
  prop ref_description, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data extracted_path, :any

  # def v(form, field), do: input_value(form, field)
  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def update(assigns, socket) do
    extracted_path = v(assigns.block, :data).path

    block_data =
      assigns.block
      |> inputs_for(:data)
      |> List.first()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:extracted_path, extracted_path)}
  end

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
        <:description>
          {#if @ref_description}
            {@ref_description}
          {#else}
            {@extracted_path}
          {/if}
        </:description>
        <div class="picture-block">
          <img src={@extracted_path} />
          <TextInput form={@block_data} field={:class} />
        </div>
        <:config>
          {#for block_data <- inputs_for(@block, :data)}
            <TextInput class="text" form={block_data} field={:alt} />
            <HiddenInput form={block_data} field={:cdn} />
            <TextInput class="text" form={block_data} field={:credits} />
            <HiddenInput class="text" form={block_data} field={:dominant_color} />
            <TextInput class="text" form={block_data} field={:height} />
            {#if is_nil(v(@block, :data).path) and !is_nil(v(@block, :data).sizes)}
              <HiddenInput class="text" form={block_data} field={:path} value={@extracted_path} />
            {#else}
              <HiddenInput class="text" form={block_data} field={:path} />
            {/if}
            <TextInput class="text" form={block_data} field={:title} />
            <HiddenInput class="text" form={block_data} field={:webp} />
            <TextInput class="text" form={block_data} field={:width} />

            <Inputs
              form={block_data}
              for={:focal}>
              <HiddenInput field={:x} />
              <HiddenInput field={:y} />
            </Inputs>

            <MapInputs
              :let={value: value, name: name}
              form={block_data}
              for={:sizes}>
              <input type="hidden" name={"#{name}"} value={"#{value}"} />
            </MapInputs>
          {/for}
        </:config>
      </Block>
    </div>
    """
  end
end
