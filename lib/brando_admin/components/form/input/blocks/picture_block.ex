defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias Surface.Components.Form.TextInput
  alias Surface.Components.Form.Inputs
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.MapInputs
  alias BrandoAdmin.Components.Modal

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

  def mount(socket) do
    {:ok, assign(socket, images: [])}
  end

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
     |> assign(:extracted_path, extracted_path)
     |> assign(:uid, v(assigns.block, :uid))}
  end

  def render(assigns) do
    ~F"""
    <div
      class="picture-block"
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
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>
          {#if @ref_description}
            {@ref_description}
          {#else}
            {@extracted_path}
          {/if}
        </:description>
        {#if @extracted_path}
          <div class="preview">
            <img src={@extracted_path} />
          </div>
        {#else}
          <div class="empty">
            <figure>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M21 15v3h3v2h-3v3h-2v-3h-3v-2h3v-3h2zm.008-12c.548 0 .992.445.992.993V13h-2V5H4v13.999L14 9l3 3v2.829l-3-3L6.827 19H14v2H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016zM8 7a2 2 0 1 1 0 4 2 2 0 0 1 0-4z"/></svg>
            </figure>
            <div class="instructions">
              Click or drag an image to upload or
              <button type="button" class="tiny" :on-click="show_image_picker">pick an existing image</button>
            </div>
          </div>
        {/if}

        <Modal
          title="Pick image"
          center_header={true}
          id={"#{@uid}-image-picker"}>
          <div class="image-picker-images">
            {#for image <- @images}
              <div class="image-picker-image" :on-click="select_image" phx-value-id={image.id}>
                <img src={"/media/#{image.image.sizes["thumb"]}"} />
              </div>
            {/for}
          </div>
        </Modal>

        <Modal
          title="Image info"
          center_header={true}
          id={"#{@uid}-image-info"}>
          Info about the image here :)
        </Modal>

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

  def handle_event("select_image", %{"id" => id}, %{assigns: %{uid: uid}} = socket) do
    image_picker_modal_id = "#{uid}-image-picker"
    image_info_modal_id = "#{uid}-image-info"
    Modal.hide(image_picker_modal_id)
    Modal.show(image_info_modal_id)
    {:noreply, socket}
  end

  def handle_event("show_image_picker", _, %{assigns: %{uid: uid}} = socket) do
    modal_id = "#{uid}-image-picker"
    {:ok, image_series} = Brando.Images.get_series_by_slug("post", "post")
    Modal.show(modal_id)

    {:noreply, assign(socket, :images, image_series.images)}
  end
end
