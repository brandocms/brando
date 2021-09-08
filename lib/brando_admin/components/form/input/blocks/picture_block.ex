defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext

  alias Surface.Components.Form.Inputs
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.MapInputs
  alias BrandoAdmin.Components.Modal

  prop uploads, :any
  prop base_form, :any
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop is_ref?, :boolean, default: false
  prop ref_name, :string
  prop ref_description, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data extracted_path, :string
  data uid, :string
  data block_data, :form
  data images, :list

  def v(form, field), do: input_value(form, field) |> IO.inspect(label: "v #{field}")

  def mount(socket) do
    {:ok,
     socket
     |> assign(images: [])}
  end

  def update(assigns, socket) do
    extracted_path = v(assigns.block, :data).path

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:block_data, fn ->
       assigns.block
       |> inputs_for(:data)
       |> List.first()
     end)
     |> assign_new(:extracted_path, fn -> extracted_path end)
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

      {inspect @block, pretty: true}

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
              <span>{gettext("Caption")}</span> {v(@block_data, :caption) || gettext("<empty>")}<br>
              <span>{gettext("Alt. text")}</span> {v(@block_data, :alt) || gettext("<empty>")}
            </figcaption>
          </div>
        {/if}

        <div class={"empty upload-canvas", hidden: @extracted_path}>
          <figure>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M21 15v3h3v2h-3v3h-2v-3h-3v-2h3v-3h2zm.008-12c.548 0 .992.445.992.993V13h-2V5H4v13.999L14 9l3 3v2.829l-3-3L6.827 19H14v2H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016zM8 7a2 2 0 1 1 0 4 2 2 0 0 1 0-4z"/></svg>
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
          <Input.Text form={@block_data} field={:alt} />
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
        %{assigns: %{block: block, base_form: base_form}} = socket
      ) do
    require Logger
    Logger.error("==> got image uploaded! #{id}")
    {:ok, image} = Brando.Images.get_image(id)
    require Logger
    Logger.error(inspect(image, pretty: true))
    Logger.error("stick it in the form herre!")

    changeset = block.source
    block_data = input_value(block, :data)

    Logger.error("changeset was #{inspect(changeset, pretty: true)}")

    updated_data_map =
      block_data
      |> Map.merge(image.image)
      |> Map.from_struct()
      |> IO.inspect(label: "updated_data_map")

    updated_data_struct =
      struct(Brando.Blueprint.Villain.Blocks.PictureBlock.Data, updated_data_map)

    require Logger
    Logger.error(inspect(updated_data_struct, pretty: true))

    updated_changeset = Ecto.Changeset.put_change(changeset, :data, updated_data_struct)
    Logger.error(inspect(updated_changeset, pretty: true))

    new_block = Map.put(block, :source, updated_changeset)
    new_block_data = inputs_for(new_block, :data) |> List.first()

    {:noreply,
     socket
     |> assign(:block_data, new_block_data)
     |> assign(:extracted_path, updated_data_struct.path)
     |> push_event("b:validate", %{})}
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
