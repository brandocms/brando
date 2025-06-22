defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Villain.Blocks.PictureBlock
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Image.FocalPoint
  alias Ecto.Changeset

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
    
    # For refs, we get gallery data from the gallery association
    {gallery, images} = if assigns.is_ref? do
      case Changeset.get_field(assigns.block.source, :gallery) do
        nil -> {nil, []}
        gallery -> 
          gallery_objects = Map.get(gallery, :gallery_objects, [])
          images = Enum.map(gallery_objects, & &1.image)
          {gallery, images}
      end
    else
      # For regular blocks, images are embedded (legacy)
      images = Changeset.get_embed(block_data_cs, :images, :struct)
      {nil, images}
    end
    
    selected_images_paths = Enum.map(images, & &1.path)

    upload_formats =
      case Changeset.get_field(block_data_cs, :formats) do
        nil -> ""
        formats -> Enum.join(formats, ",")
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:gallery, gallery)
     |> assign(:images, images)
     |> assign(:indexed_images, Enum.with_index(images))
     |> assign(:upload_formats, upload_formats)
     |> assign(:display, Changeset.get_field(block_data_cs, :display))
     |> assign(:selected_images_paths, selected_images_paths)
     |> assign(:has_images?, !Enum.empty?(images))
     |> assign(:uid, assigns.ref_form[:uid].value)}
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
        <Block.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
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
            phx-click={JS.push("show_captions", target: @myself) |> show_modal("#block-#{@uid}_captions")}
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
            <%= if @is_ref? do %>
              <!-- For refs, display images from gallery association -->
              <div :for={{image, index} <- @indexed_images} class="preview sort-handle draggable" data-id={index}>
                <Content.image image={image} size={(@display == :grid && :thumb) || :smallest} />
                <button class="delete-x" type="button" phx-click={JS.push("remove_image", target: @myself)} phx-value-path={image.path}>
                  <.icon name="hero-x-mark" />
                  <div class="text">{gettext("Delete")}</div>
                </button>
                <figcaption phx-click={JS.push("show_captions", target: @myself) |> show_modal("#block-#{@uid}_captions")}>
                  <div :if={image.title}>
                    <span>{gettext("Caption")}</span>
                    {raw(image.title || "{ #{gettext("No caption")} }")}
                  </div>
                  <div :if={image.alt}>
                    <span>{gettext("Alt. text")}</span>
                    {image.alt || "{ #{gettext("No alt text")} }"}
                  </div>
                  <div :if={image.credits}>
                    <span>{gettext("Credits")}</span>
                    {image.credits || "{ #{gettext("No credits")} }"}
                  </div>
                </figcaption>
              </div>
            <% else %>
              <!-- For regular blocks, use embedded images (legacy) -->
              <.inputs_for :let={image} field={block_data[:images]} skip_hidden>
                <.gallery_image image={image} uid={@uid} parent_form_name={block_data.name} display={@display} target={@myself} />
              </.inputs_for>
            <% end %>
          </div>

          <div :if={!@has_images?} class="upload-canvas empty">
            <div class="alert">
              {gettext(
                "No images currently in block. Click one of the buttons above to get started, or drag and drop images here."
              )}
            </div>
          </div>

          <Content.modal title={gettext("Edit captions")} id={"block-#{@uid}_captions"}>
            <div class="caption-editor">
              <%= if @is_ref? do %>
                <!-- For refs, captions are managed through the gallery association -->
                <div :for={{image, _index} <- @indexed_images} class="caption-row">
                  <figure>
                    <Content.image image={image} size={:smallest} />
                  </figure>
                  <div>
                    <p><strong>Note:</strong> Captions for gallery refs are managed through the gallery association.</p>
                    <p>Title: {image.title}</p>
                    <p>Credits: {image.credits}</p>
                    <p>Alt: {image.alt}</p>
                  </div>
                </div>
              <% else %>
                <!-- For regular blocks, use embedded image forms (legacy) -->
                <.inputs_for :let={image} field={block_data[:images]}>
                  <div class="caption-row">
                    <figure>
                      <Content.image image={image.data} size={:smallest}>
                        <.live_component
                          module={FocalPoint}
                          id={"image-drawer-focal-#{@uid}-#{image.index}"}
                          image={%{image: image.data}}
                          form={image}
                        />
                      </Content.image>
                    </figure>
                    <div>
                      <Input.rich_text field={image[:title]} label={gettext("Title")} opts={[]} />
                      <Input.text field={image[:credits]} label={gettext("Credits")} />
                      <Input.text field={image[:alt]} label={gettext("Alt. text")} />
                    </div>
                  </div>
                </.inputs_for>
              <% end %>
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

            <Form.array_inputs :let={%{value: array_value, name: array_name}} field={block_data[:formats]}>
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

      <Form.map_inputs :let={%{value: value, name: name}} field={@image[:sizes]}>
        <input type="hidden" name={"#{name}"} value={"#{value}"} />
      </Form.map_inputs>

      <Form.array_inputs :let={%{value: array_value, name: array_name}} field={@image[:formats]}>
        <input type="hidden" name={array_name} value={array_value} />
      </Form.array_inputs>
      <Content.image image={@img} size={(@display == :grid && :thumb) || :smallest} />
      <button class="delete-x" type="button" phx-click={JS.push("remove_image", target: @target)} phx-value-path={@img.path}>
        <.icon name="hero-x-mark" />
        <div class="text">{gettext("Delete")}</div>
      </button>
      <figcaption phx-click={JS.push("show_captions", target: @target) |> show_modal("#block-#{@uid}_captions")}>
        <div :if={@img.title}>
          <span>{gettext("Caption")}</span>
          {raw(@img.title || "{ #{gettext("No caption")} }")}
        </div>
        <div :if={@img.alt}>
          <span>{gettext("Alt. text")}</span>
          {@img.alt || "{ #{gettext("No alt text")} }"}
        </div>
        <div :if={@img.credits}>
          <span>{gettext("Credits")}</span>
          {@img.credits || "{ #{gettext("No credits")} }"}
        </div>
      </figcaption>
    </div>
    """
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_only_selected", _, socket) do
    {:noreply, assign(socket, :show_only_selected?, !socket.assigns.show_only_selected?)}
  end

  def handle_event("reposition", _, socket) do
    {:noreply, socket}
  end

  def handle_event("image_uploaded", %{"id" => id}, socket) do
    if socket.assigns.is_ref? do
      # For refs, add image to gallery association
      target = socket.assigns.target
      ref_name = socket.assigns.ref_name
      {:ok, image} = Brando.Images.get_image(id)
      
      # Get current block data for gallery settings
      block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
      block_data = Changeset.apply_changes(block_data_cs)
      
      # Only gallery configuration data goes to block data
      new_block_data = Map.from_struct(block_data)
      
      send_update(target, %{
        event: "update_ref_data", 
        ref_data: new_block_data,
        ref_name: ref_name,
        add_gallery_image_id: image.id
      })
    else
      # Legacy behavior for regular blocks
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
    end

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id, "selected" => "false"}, socket) do
    if socket.assigns.is_ref? do
      # For refs, add image to gallery association
      target = socket.assigns.target
      ref_name = socket.assigns.ref_name
      {:ok, image} = Brando.Images.get_image(id)
      
      # Get current block data for gallery settings
      block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
      block_data = Changeset.apply_changes(block_data_cs)
      
      # Only gallery configuration data goes to block data
      new_block_data = Map.from_struct(block_data)
      
      send_update(target, %{
        event: "update_ref_data", 
        ref_data: new_block_data,
        ref_name: ref_name,
        add_gallery_image_id: image.id
      })
    else
      # Legacy behavior for regular blocks
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
    end

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id, "selected" => "true"}, socket) do
    if socket.assigns.is_ref? do
      # For refs, remove image from gallery association
      target = socket.assigns.target
      ref_name = socket.assigns.ref_name
      {:ok, image} = Brando.Images.get_image(id)
      
      # Get current block data for gallery settings
      block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
      block_data = Changeset.apply_changes(block_data_cs)
      
      # Only gallery configuration data goes to block data
      new_block_data = Map.from_struct(block_data)
      
      send_update(target, %{
        event: "update_ref_data", 
        ref_data: new_block_data,
        ref_name: ref_name,
        remove_gallery_image_id: image.id
      })
    else
      # Legacy behavior for regular blocks
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
    end

    {:noreply, socket}
  end

  def handle_event("remove_image", %{"path" => path}, socket) do
    if socket.assigns.is_ref? do
      # For refs, remove image from gallery association by path
      target = socket.assigns.target
      ref_name = socket.assigns.ref_name
      
      # Get current block data for gallery settings
      block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
      block_data = Changeset.apply_changes(block_data_cs)
      
      # Only gallery configuration data goes to block data
      new_block_data = Map.from_struct(block_data)
      
      send_update(target, %{
        event: "update_ref_data", 
        ref_data: new_block_data,
        ref_name: ref_name,
        remove_gallery_image_path: path
      })
    else
      # Legacy behavior for regular blocks
      block = socket.assigns.block
      block_data_cs = Block.get_block_data_changeset(block)
      block_data = Changeset.apply_changes(block_data_cs)
      target = socket.assigns.target
      ref_name = socket.assigns.ref_name

      images = Enum.reject(block_data.images, &(&1.path == path))
      updated_block_data = Map.put(block_data, :images, images)

      block_data = Map.from_struct(updated_block_data)

      send_update(target, %{event: "update_ref_data", ref_data: block_data, ref_name: ref_name})
    end
    
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
