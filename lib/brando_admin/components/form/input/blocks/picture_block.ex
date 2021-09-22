defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext
  alias Brando.Blueprint.Villain.Blocks.PictureBlock
  alias Brando.Utils
  alias Brando.Villain

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Inputs
  alias BrandoAdmin.Components.Form.MapInputs
  alias BrandoAdmin.Components.Modal

  prop uploads, :any
  prop base_form, :any
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop data_field, :atom
  prop is_ref?, :boolean, default: false
  prop ref_name, :string
  prop ref_description, :string
  prop belongs_to, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data extracted_path, :string
  data uid, :string
  data block_data, :form
  data images, :list
  data image, :any

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
     |> assign(:image, v(assigns.block, :data))
     |> assign(:extracted_path, extracted_path)
     |> assign(:uid, v(assigns.block, :uid))}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-wrapper"}
      class="picture-block"
      phx-hook="Brando.LegacyImageUpload"
      data-text-uploading={gettext("Uploading...")}
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
              <div id={"#{@uid}-figcaption-title"}>
                <span>{gettext("Caption")}</span> {v(@block_data, :title) |> raw}<br>
              </div>
              <div id={"#{@uid}-figcaption-alt"}>
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
            <span>{gettext("Click or drag an image &uarr; to upload") |> raw()}</span><br>
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

        <:config>
          <div class="panels">
            <div class="panel">
              {#if @extracted_path}
                <img
                  width={"#{@image.width}"}
                  height={"#{@image.height}"}
                  src={"#{Utils.img_url(@image, :original, prefix: Utils.media_url())}"} />

                <div class="image-info">
                  Path: {@image.path}<br>
                  Dimensions: {@image.width}&times;{@image.height}<br>
                </div>
              {/if}
              {#if !@extracted_path}
                <div class="img-placeholder empty upload-canvas">
                  <div class="placeholder-wrapper">
                    <div class="svg-wrapper">
                      <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                        <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none"/>
                        <polygon class="plus" points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"/>
                        <path d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z" transform="translate(0 0)"/>
                        <circle cx="8" cy="9" r="2"/>
                      </svg>
                    </div>
                  </div>
                  <div class="instructions">
                    <span>{gettext("Click or drag an image &uarr; to upload") |> raw()}</span>
                  </div>
                </div>
              {/if}
            </div>
            <div class="panel">
              <Input.RichText form={@block_data} field={:title} />
              <Input.Text form={@block_data} field={:alt} debounce={500} />

              <div class="button-group-vertical">
                <button type="button" class="secondary" :on-click="show_image_picker">
                  {gettext("Select image")}
                </button>

                <button type="button" class="danger" :on-click="reset_image">
                  {gettext("Reset image")}
                </button>
              </div>
            </div>
          </div>

          {hidden_input @block_data, :placeholder}
          {hidden_input @block_data, :cdn}
          {hidden_input @block_data, :credits}
          {hidden_input @block_data, :dominant_color}
          {hidden_input @block_data, :height}
          {hidden_input @block_data, :webp}
          {hidden_input @block_data, :width}

          {#if is_nil(v(@block_data, :path)) and !is_nil(v(@block_data, :sizes))}
            {hidden_input @block_data, :path, value: @extracted_path}
            {#else}
            {hidden_input @block_data, :path}
          {/if}

          <Inputs
            form={@block_data}
            for={:focal}
            :let={form: focal_form}>
            {hidden_input focal_form, :x}
            {hidden_input focal_form, :y}
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

  def handle_event("close_config", _, socket) do
    Modal.hide("#{socket.assigns.uid}_config")
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

    form_id = "#{schema.__naming__().singular}_form"

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
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "select_image",
        %{"id" => id},
        %{
          assigns: %{
            base_form: base_form,
            uid: uid,
            block: block,
            block_data: block_data,
            data_field: data_field
          }
        } = socket
      ) do
    image_picker_modal_id = "#{uid}-image-picker"
    Modal.hide(image_picker_modal_id)

    {:ok, image} = Brando.Images.get_image(id)

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

    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("show_image_picker", _, %{assigns: %{uid: uid}} = socket) do
    modal_id = "#{uid}-image-picker"
    {:ok, image_series} = Brando.Images.get_series_by_slug("post", "post")
    Modal.show(modal_id)

    {:noreply, assign(socket, :images, image_series.images)}
  end
end
