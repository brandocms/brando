defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext
  alias Brando.Blueprint.Villain.Blocks.PictureBlock
  alias Brando.Utils
  alias Brando.Villain

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.MapInputs
  alias BrandoAdmin.Components.Modal

  alias Surface.Components.Form.Inputs
  alias Surface.Components.Form.HiddenInput

  prop uploads, :any
  prop base_form, :any
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop data_field, :atom
  prop is_ref?, :boolean, default: false
  prop ref_name, :string
  prop ref_description, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data extracted_path, :string
  data uid, :string
  data block_data, :form
  data images, :list

  def v(form, field), do: input_value(form, field)

  def mount(socket) do
    {:ok,
     socket
     |> assign(images: [])}
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
      id={"#{@uid}-wrapper"}
      class="picture-block"
      phx-hook="Brando.LegacyImageUpload"
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
        <input class="file-input" type="file" />
        {#if @extracted_path}
          <div class="preview">
            <img src={"/media/#{@extracted_path}"} />
            <figcaption :on-click="show_config">
              <div>
                <span>{gettext("Caption")}</span> {v(@block_data, :title) |> raw}<br>
              </div>
              <div>
                <span>{gettext("Alt. text")}</span> {v(@block_data, :alt)}
              </div>
            </figcaption>
          </div>
        {/if}

        <div class={"empty upload-canvas", hidden: @extracted_path}>
          <figure>
            <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none"/>
              <polygon class="plus" points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"/>
              <path d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z" transform="translate(0 0)"/>
              <circle cx="8" cy="9" r="2"/>
            </svg>
          </figure>
          <div class="instructions">
            Click or drag an image to upload or
            <button type="button" class="tiny" :on-click="show_image_picker">pick an existing image</button>
          </div>
        </div>

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
          <Input.RichText form={@block_data} field={:title} />
          <Input.Text form={@block_data} field={:alt} debounce={500} />

          <button type="button" class="secondary small upload-image">
            {gettext("Upload new image")}
          </button>
          <button type="button" class="secondary small" :on-click="select_image">
            {gettext("Select image")}
          </button>
          <button type="button" class="danger small" :on-click="reset_image">
            {gettext("Reset image")}
          </button>

          <HiddenInput form={@block_data} field={:placeholder} />
          <HiddenInput form={@block_data} field={:cdn} />
          <HiddenInput form={@block_data} field={:credits} />
          <HiddenInput form={@block_data} field={:dominant_color} />
          <HiddenInput form={@block_data} field={:height} />
          <HiddenInput form={@block_data} field={:webp} />
          <HiddenInput form={@block_data} field={:width} />

          {#if is_nil(v(@block_data, :path)) and !is_nil(v(@block_data, :sizes))}
            <HiddenInput form={@block_data} field={:path} value={@extracted_path} />
          {#else}
            <HiddenInput form={@block_data} field={:path} />
          {/if}

          <Inputs
            form={@block_data}
            for={:focal}>
            <HiddenInput field={:x} />
            <HiddenInput field={:y} />
          </Inputs>

          <MapInputs
            :let={value: value, name: name}
            form={@block_data}
            for={:sizes}>
            <input type="hidden" name={"#{name}"} value={"#{value}"} />
          </MapInputs>
        </:config>
      </Block>
    </div>
    """
  end

  def handle_event("show_config", _, socket) do
    Modal.show("#{socket.assigns.uid}_config")
    {:noreply, socket}
  end

  def handle_event(
        "image_uploaded",
        %{"id" => id},
        %{
          assigns: %{
            block: block,
            base_form: base_form,
            uid: uid,
            data_field: data_field
          }
        } = socket
      ) do
    {:ok, image} = Brando.Images.get_image(id)

    block_data = input_value(block, :data)

    updated_data_map =
      block_data
      |> Map.merge(image.image)
      |> Map.from_struct()

    updated_data_struct = struct(PictureBlock.Data, updated_data_map)

    updated_picture_block = Map.put(block.data, :data, updated_data_struct)

    changeset = base_form.source
    schema = changeset.data.__struct__

    updated_changeset =
      Villain.replace_block_in_changeset(
        changeset,
        data_field,
        uid,
        updated_picture_block
      )

    form_id = "#{schema.__naming__.singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "reset_image",
        _,
        %{assigns: %{base_form: base_form, data_field: data_field, uid: uid}} = socket
      ) do
    changeset = base_form.source

    empty_block = %PictureBlock{
      uid: Utils.generate_uid(),
      data: %PictureBlock.Data{}
    }

    updated_changeset =
      Villain.replace_block_in_changeset(changeset, data_field, uid, empty_block)

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__.singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => _id}, %{assigns: %{uid: uid}} = socket) do
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
