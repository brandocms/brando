defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock do
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  alias Ecto.Changeset
  alias Brando.Villain.Blocks.PictureBlock

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input

  # prop uploads, :any
  # prop base_form, :any
  # prop block, :any
  # prop block_count, :integer
  # prop index, :any
  # prop data_field, :atom
  # prop is_ref?, :boolean, default: false
  # prop ref_name, :string
  # prop ref_description, :string
  # prop belongs_to, :string

  # prop insert_module, :event, required: true
  # prop duplicate_block, :event, required: true

  # data extracted_path, :string
  # data uid, :string
  # data block_data, :form
  # data available_images, :list
  # data images, :list
  # data has_images?, :boolean
  # data image, :any
  # data selected_images_paths, :list
  # data display, :atom
  # data show_only_selected?, :boolean
  # data upload_formats, :string

  def mount(socket) do
    {:ok, assign(socket, available_images: [], show_only_selected?: false)}
  end

  def update(assigns, socket) do
    block_data_cs = Block.get_block_data_changeset(assigns.block)
    images = Changeset.get_embed(block_data_cs, :images, :struct)
    selected_images_paths = Enum.map(images, & &1.path)

    upload_formats =
      case Changeset.get_field(block_data_cs, :formats) do
        nil -> ""
        formats -> Enum.join(formats, ",")
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:images, images)
     |> assign(:indexed_images, Enum.with_index(images))
     |> assign(:upload_formats, upload_formats)
     |> assign(:display, Changeset.get_field(block_data_cs, :display))
     |> assign(:selected_images_paths, selected_images_paths)
     |> assign(:has_images?, !Enum.empty?(images))
     |> assign(:uid, assigns.block[:uid].value)}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="gallery-block"
      phx-hook="Brando.LegacyImageUpload"
      data-upload-multi="true"
      data-text-uploading={gettext("Uploading...")}
      data-block-uid={@uid}
    >
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Block.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          multi={false}
          target={@target}
        >
          <:description>
            {block_data[:type].value}
            <%= if @ref_description not in ["", nil] do %>
              — {@ref_description}
            <% end %>
          </:description>

          <div id={"block-#{@uid}-base-f-in"} phx-update="ignore">
            <input name={"block-#{@uid}-f-in"} class="file-input" type="file" multiple />
          </div>

          <span id={"block-#{@uid}-base-file-upload-btn-with-images"} phx-update="ignore">
            <button type="button" class="tiny file-upload" id={"block-#{@uid}-up-btn-with-images"}>
              {gettext("Upload images")}
            </button>
          </span>
          <button
            type="button"
            class="tiny"
            phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
          >
            {gettext("Select images")}
          </button>
          <button
            type="button"
            class="tiny"
            phx-click={
              JS.push("show_captions", target: @myself) |> show_modal("#block-#{@uid}_captions")
            }
          >
            {gettext("Edit captions")}
          </button>
          <div
            id={"sortable-#{block_data.id}-images"}
            class={[
              "images",
              (@display == :grid && "images-grid") || "images-list"
            ]}
            phx-hook="Brando.SortableEmbeds"
            data-target={@myself}
            data-sortable-id={"sortable-#{block_data.id}-images"}
            data-sortable-handle=".sort-handle"
            data-sortable-selector=".preview"
          >
            <.inputs_for :let={image} field={block_data[:images]} skip_hidden>
              <.gallery_image
                image={image}
                uid={@uid}
                parent_form_name={block_data.name}
                target={@myself}
              />
            </.inputs_for>
          </div>

          <div :if={!@has_images?} class="alert">
            {gettext("No images currently in block. Click one of the buttons above to get started.")}
          </div>

          <Content.modal title={gettext("Edit captions")} id={"block-#{@uid}_captions"}>
            <div class="caption-editor">
              <.inputs_for :let={image} field={block_data[:images]}>
                <div class="caption-row">
                  <figure>
                    <Content.image image={image.data} size={:thumb} />
                  </figure>
                  <div>
                    <Input.rich_text field={image[:title]} label={gettext("Title")} />
                    <Input.text field={image[:credits]} label={gettext("Credits")} />
                    <Input.text field={image[:alt]} label={gettext("Alt. text")} />
                  </div>
                </div>
              </.inputs_for>
            </div>
          </Content.modal>

          <:config>
            <Input.input type={:hidden} field={block_data[:type]} />
            <Input.radios
              field={block_data[:display]}
              label={gettext("Display")}
              opts={[
                options: [
                  %{label: "Grid", value: :grid},
                  %{label: "List", value: :list}
                ]
              ]}
            />
            <Input.text field={block_data[:class]} label={gettext("Class")} />
            <Input.text field={block_data[:series_slug]} label={gettext("Series slug")} />
            <Input.toggle field={block_data[:lightbox]} label={gettext("Lightbox")} />

            <Input.radios
              field={block_data[:placeholder]}
              label={gettext("Placeholder")}
              opts={[
                options: [
                  %{label: "SVG", value: :svg},
                  %{label: "Dominant Color", value: :dominant_color},
                  %{label: "Dominant Color faded", value: :dominant_color_faded},
                  %{label: "Micro", value: :micro},
                  %{label: "None", value: :none}
                ]
              ]}
            />

            <Form.array_inputs
              :let={%{value: array_value, name: array_name}}
              field={block_data[:formats]}
            >
              <input type="hidden" name={array_name} value={array_value} />
            </Form.array_inputs>

            <input type="hidden" data-upload-formats={@upload_formats} />
          </:config>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def gallery_image(assigns) do
    img = assigns.image.data
    assigns = assign(assigns, :img, img)

    ~H"""
    <div class="preview sort-handle draggable" data-id={@image.index}>
      <input type="hidden" name={@image[:_persistent_id].name} value={@image.index} />
      <input type="hidden" name={"#{@parent_form_name}[sort_images][]"} value={@image.index} />
      <Input.input type={:hidden} field={@image[:placeholder]} />
      <Input.input type={:hidden} field={@image[:cdn]} />
      <Input.input type={:hidden} field={@image[:dominant_color]} />
      <Input.input type={:hidden} field={@image[:height]} />
      <Input.input type={:hidden} field={@image[:width]} />
      <Input.input type={:hidden} field={@image[:path]} />

      <.inputs_for :let={focal_form} field={@image[:focal]}>
        <Input.input type={:hidden} field={focal_form[:x]} />
        <Input.input type={:hidden} field={focal_form[:y]} />
      </.inputs_for>

      <Form.map_inputs :let={%{value: value, name: name}} field={@image[:sizes]}>
        <input type="hidden" name={"#{name}"} value={"#{value}"} />
      </Form.map_inputs>

      <Form.array_inputs :let={%{value: array_value, name: array_name}} field={@image[:formats]}>
        <input type="hidden" name={array_name} value={array_value} />
      </Form.array_inputs>
      <Content.image image={@img} size={:thumb} />
      <button
        class="delete-x"
        type="button"
        phx-click={JS.push("remove_image", target: @target)}
        phx-value-path={@img.path}
      >
        <.icon name="hero-x-mark" />
        <div class="text">{gettext("Delete")}</div>
      </button>
      <figcaption phx-click={
        JS.push("show_captions", target: @target) |> show_modal("#block-#{@uid}_captions")
      }>
        <div>
          <span>{gettext("Caption")}</span>
          {raw(@img.title || "{ #{gettext("No caption")} }")}
        </div>
        <div>
          <span>{gettext("Alt. text")}</span>
          {@img.alt || "{ #{gettext("No alt text")} }"}
        </div>
        <div>
          <span>{gettext("Credits")}</span>
          {@img.credits || "{ #{gettext("No credits")} }"}
        </div>
      </figcaption>
    </div>
    """
  end

  def handle_event("toggle_only_selected", _, socket) do
    {:noreply, assign(socket, :show_only_selected?, !socket.assigns.show_only_selected?)}
  end

  def handle_event("reposition", _, socket) do
    {:noreply, socket}
  end

  def handle_event("image_uploaded", %{"id" => id}, socket) do
    block = socket.assigns.block
    block_data_cs = Block.get_block_data_changeset(block)
    block_data = Changeset.apply_changes(block_data_cs)
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    {:ok, image} = Brando.Images.get_image(id)
    picture_data_tpl = struct(PictureBlock.Data, Map.from_struct(image))

    images = block_data.images ++ [picture_data_tpl]
    updated_block_data = Map.put(block_data, :images, images)
    block_data = Map.from_struct(updated_block_data)

    send_update(target, %{event: "update_ref_data", ref_data: block_data, ref_name: ref_name})

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id, "selected" => "false"}, socket) do
    block = socket.assigns.block
    block_data_cs = Block.get_block_data_changeset(block)
    block_data = Changeset.apply_changes(block_data_cs)
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    {:ok, image} = Brando.Images.get_image(id)
    picture_data_tpl = struct(PictureBlock.Data, Map.from_struct(image))

    images = block_data.images ++ [picture_data_tpl]
    updated_block_data = Map.put(block_data, :images, images)
    block_data = Map.from_struct(updated_block_data)

    send_update(target, %{event: "update_ref_data", ref_data: block_data, ref_name: ref_name})

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id, "selected" => "true"}, socket) do
    block = socket.assigns.block
    block_data_cs = Block.get_block_data_changeset(block)
    block_data = Changeset.apply_changes(block_data_cs)
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    {:ok, image} = Brando.Images.get_image(id)

    images = Enum.reject(block_data.images, &(&1.path == image.path))
    updated_block_data = Map.put(block_data, :images, images)

    block_data = Map.from_struct(updated_block_data)
    send_update(target, %{event: "update_ref_data", ref_data: block_data, ref_name: ref_name})

    {:noreply, socket}
  end

  def handle_event("remove_image", %{"path" => path}, socket) do
    block = socket.assigns.block
    block_data_cs = Block.get_block_data_changeset(block)
    block_data = Changeset.apply_changes(block_data_cs)
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    images = Enum.reject(block_data.images, &(&1.path == path))
    updated_block_data = Map.put(block_data, :images, images)

    block_data =
      Map.from_struct(updated_block_data)

    send_update(target, %{event: "update_ref_data", ref_data: block_data, ref_name: ref_name})
    {:noreply, socket}
  end

  def handle_event("set_target", _, socket) do
    myself = socket.assigns.myself
    images = socket.assigns.images

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: "default",
      event_target: myself,
      multi: true,
      selected_images: Enum.map(images, & &1.path)
    )

    {:noreply, socket}
  end

  def handle_event("show_captions", _, socket) do
    {:noreply, socket}
  end
end
