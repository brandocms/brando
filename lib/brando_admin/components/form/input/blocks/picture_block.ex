defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Villain.Blocks.PictureBlock
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
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
  # data images, :list
  # data image, :any
  # data upload_formats, :string

  # Only override fields that can be customized in the block data
  @override_fields [
    :title,
    :credits,
    :alt,
    :picture_class,
    :img_class,
    :link,
    :srcset,
    :media_queries,
    :lazyload,
    :moonwalk,
    :placeholder,
    :fetchpriority
  ]

  def mount(socket) do
    socket
    |> assign(:images, [])
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, assigns.block[:uid].value)
     |> assign_new(:compact, fn -> true end)
     |> assign_new(:image, fn ->
       block_data_cs = Block.get_block_data_changeset(assigns.block)
       
       if assigns.is_ref? do
         case Changeset.get_field(assigns.block.source, :image) do
           nil -> Changeset.apply_changes(block_data_cs)  # No image associated yet
           image -> image  # Get from image association
         end
       else
         Changeset.apply_changes(block_data_cs)  # Block data only contains override fields
       end
     end)
     |> assign_new(:extracted_path, fn %{is_ref?: is_ref?, image: image} ->
       if is_ref? && image do
         Map.get(image, :path)
       else
         nil
       end
     end)
     |> assign_new(:extracted_filename, fn %{extracted_path: extracted_path} ->
       if extracted_path do
         Path.basename(extracted_path)
       else
         nil
       end
     end)
     |> assign_new(:file_name, fn %{extracted_filename: extracted_filename} -> extracted_filename end)
     |> assign_new(:upload_formats, fn %{is_ref?: is_ref?, image: image} ->
       if is_ref? && image do
         case Map.get(image, :formats) do
           formats when is_list(formats) -> Enum.join(formats, ",")
           _ -> ""
         end
       else
         ""
       end
     end)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <div
          id={"block-#{@uid}-wrapper"}
          class="picture-block"
          phx-hook="Brando.LegacyImageUpload"
          data-text-uploading={gettext("Uploading...")}
          data-block-uid={@uid}
          data-upload-config-target={block_data[:config_target].value}
        >
          <Block.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
            <:description>
              <%= if @ref_description not in ["", nil] do %>
                {@ref_description}
              <% else %>
                {@extracted_filename}
              <% end %>
            </:description>
            <input class="file-input" type="file" />
            <div
              :if={@extracted_path}
              class={["preview", (@compact && "compact") || "classic"]}
              phx-click={!@compact && show_modal("#block-#{@uid}_config")}
            >
              <Content.image image={@image} size={:largest} />
              <div class="image-info">
                <figcaption phx-click={!@compact && show_modal("#block-#{@uid}_config")}>
                  <div class="info-wrapper">
                    <div class="filename">{@file_name}</div>
                    <div class="title-and-alt">
                      <div class="dims">{@image.width}&times;{@image.height}</div>
                      <div id={"block-#{@uid}-figcaption-title"}>
                        <span>{gettext("Caption")}</span>
                        <%= if @image.title in [nil, ""] do %>
                          {gettext("<no caption>")}
                        <% else %>
                          {raw(@image.title)}
                        <% end %>
                      </div>
                      <div id={"block-#{@uid}-figcaption-alt"}>
                        <span>{gettext("Alt. text")}</span> {@image.alt ||
                          gettext("<no alt.text>")}
                      </div>
                    </div>
                  </div>
                  <button class="tiny" type="button" phx-click={show_modal("#block-#{@uid}_config")}>
                    {gettext("Edit image")}
                  </button>
                </figcaption>
              </div>
            </div>

            <div class={["empty", "upload-canvas", @extracted_path && "hidden"]}>
              <figure>
                <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                  <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none" />
                  <polygon
                    class="plus"
                    points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"
                  />
                  <path
                    d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z"
                    transform="translate(0 0)"
                  />
                  <circle cx="8" cy="9" r="2" />
                </svg>
              </figure>
              <div class="instructions">
                <span>{gettext("Click or drag an image &uarr; to upload") |> raw()}</span>
                <br />
                <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}>
                  {gettext("Pick an existing image")}
                </button>
              </div>
            </div>

            <:config>
              <div class="panels">
                <div class="panel">
                  <%= if @extracted_path do %>
                    <Content.image image={@image} size={:largest} />
                    <div class="image-info">
                      Path: {@image.path}<br /> Dimensions: {@image.width}&times;{@image.height}<br />
                    </div>
                  <% end %>
                  <div :if={!@extracted_path} class="img-placeholder empty upload-canvas">
                    <div class="placeholder-wrapper">
                      <div class="svg-wrapper">
                        <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                          <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none" />
                          <polygon
                            class="plus"
                            points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"
                          />
                          <path
                            d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z"
                            transform="translate(0 0)"
                          />
                          <circle cx="8" cy="9" r="2" />
                        </svg>
                      </div>
                    </div>
                    <div class="instructions">
                      <span>{gettext("Click or drag an image &uarr; to upload") |> raw()}</span>
                    </div>
                  </div>
                </div>
                <div class="panel">
                  <div class="button-group-vertical">
                    <button
                      type="button"
                      class="secondary"
                      phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
                    >
                      {gettext("Select image")}
                    </button>

                    <button type="button" class="danger" phx-click={JS.push("reset_image", target: @myself)}>
                      {gettext("Reset image")}
                    </button>
                  </div>
                  <Input.input type={:hidden} field={block_data[:config_target]} />
                  <Input.rich_text field={block_data[:title]} label={gettext("Caption")} opts={[]} />
                  <Input.text field={block_data[:alt]} label={gettext("Alt")} />
                  <Input.text field={block_data[:link]} label={gettext("Link")} />
                  <Input.radios
                    field={block_data[:fetchpriority]}
                    label={gettext("Fetch priority")}
                    opts={[
                      options: [
                        %{label: gettext("Auto"), value: :auto},
                        %{label: gettext("High"), value: :high},
                        %{label: gettext("Low"), value: :low}
                      ]
                    ]}
                  />
                  <Input.text field={block_data[:dominant_color]} label={gettext("Dominant color")} />
                </div>
              </div>

              <Input.input type={:hidden} field={block_data[:placeholder]} />
              <%= if not @is_ref? do %>
                <Input.input type={:hidden} field={block_data[:cdn]} />
              <% end %>
              <Input.input type={:hidden} field={block_data[:moonwalk]} />
              <Input.input type={:hidden} field={block_data[:lazyload]} />
              <Input.input type={:hidden} field={block_data[:credits]} />
              <%= if not @is_ref? do %>
                <Input.input type={:hidden} field={block_data[:height]} />
                <Input.input type={:hidden} field={block_data[:width]} />
                <Input.input type={:hidden} field={block_data[:path]} />
              <% end %>

              <%= if not @is_ref? do %>
                <.inputs_for :let={focal_form} field={block_data[:focal]}>
                  <Input.input type={:hidden} field={focal_form[:x]} />
                  <Input.input type={:hidden} field={focal_form[:y]} />
                </.inputs_for>

                <Form.map_inputs :let={%{value: value, name: name}} field={block_data[:sizes]}>
                  <input type="hidden" name={name} value={value} />
                </Form.map_inputs>

                <Form.array_inputs :let={%{value: array_value, name: array_name}} field={block_data[:formats]}>
                  <input type="hidden" name={array_name} value={array_value} />
                </Form.array_inputs>
              <% end %>

              <input type="hidden" data-upload-formats={@upload_formats} />
            </:config>
          </Block.block>
        </div>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("focus", _, socket), do: {:noreply, socket}

  def handle_event("image_uploaded", %{"id" => id}, socket) do
    {:ok, image} = Brando.Images.get_image(id)
    
    # For refs, we need to update both the image association and the block data
    if socket.assigns.is_ref? do
      target = socket.assigns.target
      ref_name = socket.assigns.ref_name
      
      # Get current block data to preserve any existing overrides
      block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
      current_block_data = Changeset.apply_changes(block_data_cs)
      
      # Only keep override fields in block data, image data goes to association
      new_block_data = 
        current_block_data
        |> Map.from_struct()
        |> Map.take(@override_fields)
      
      send_update(target, %{
        event: "update_ref_data", 
        ref_data: new_block_data,
        ref_name: ref_name,
        image_id: image.id
      })
    else
      # For regular blocks, merge image data into block data (legacy behavior)
      block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
      block_data = Changeset.apply_changes(block_data_cs)
      
      new_data =
        block_data
        |> Map.merge(image)
        |> Map.from_struct()
        |> Map.take([:path, :width, :height, :formats, :sizes, :cdn, :dominant_color, :focal] ++ @override_fields)
      
      send_update(socket.assigns.target, %{event: "update_block_data", block_data: new_data})
    end

    {:noreply, socket}
  end

  def handle_event("set_target", _, socket) do
    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: "default",
      event_target: socket.assigns.myself,
      multi: false,
      selected_images: []
    )

    {:noreply, socket}
  end

  def handle_event("reset_image", _, socket) do
    if socket.assigns.is_ref? do
      target = socket.assigns.target
      ref_name = socket.assigns.ref_name

      # Reset to empty picture block data with no image association
      new_data =
        %PictureBlock.Data{}
        |> Map.from_struct()
        |> Map.take(@override_fields)

      uid = socket.assigns.uid
      send_update(target, %{
        event: "update_ref_data", 
        ref_data: new_data, 
        ref_name: ref_name,
        image_id: nil
      })

      {:noreply, push_event(socket, "b:picture_block:attach_listeners:#{uid}", %{})}
    else
      # For regular blocks, reset all data
      target = socket.assigns.target
      new_data =
        %PictureBlock.Data{}
        |> Map.from_struct()

      uid = socket.assigns.uid
      send_update(target, %{event: "update_block_data", block_data: new_data})

      {:noreply, push_event(socket, "b:picture_block:attach_listeners:#{uid}", %{})}
    end
  end

  def handle_event("select_image", %{"id" => id}, socket) do
    {:ok, image} = Brando.Images.get_image(id)
    
    if socket.assigns.is_ref? do
      target = socket.assigns.target
      ref_name = socket.assigns.ref_name
      
      # Get current block data to preserve any existing overrides
      block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
      current_block_data = Changeset.apply_changes(block_data_cs)
      
      # Only keep override fields in block data, image data goes to association
      new_block_data = 
        current_block_data
        |> Map.from_struct()
        |> Map.take(@override_fields)
      
      send_update(target, %{
        event: "update_ref_data", 
        ref_data: new_block_data,
        ref_name: ref_name,
        image_id: image.id
      })
    else
      # For regular blocks, merge image data into block data (legacy behavior)
      block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
      block_data = Changeset.apply_changes(block_data_cs)
      
      new_data =
        block_data
        |> Map.merge(image)
        |> Map.from_struct()
        |> Map.take([:path, :width, :height, :formats, :sizes, :cdn, :dominant_color, :focal] ++ @override_fields)
      
      send_update(socket.assigns.target, %{event: "update_block_data", block_data: new_data})
    end
    
    {:noreply, socket}
  end

  def handle_event("show_image_picker", _, socket) do
    {:ok, images} = Brando.Images.list_images()
    {:noreply, assign(socket, :images, images)}
  end
end
