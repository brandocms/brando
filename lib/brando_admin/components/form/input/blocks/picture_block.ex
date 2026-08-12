defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Villain.Blocks.PictureBlock
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias Ecto.Changeset

  # prop base_form, :any
  # prop block, :any
  # prop block_count, :integer
  # prop index, :any
  # prop data_field, :atom
  # prop ref_form, :any
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
    |> assign(:form_id, nil)
    |> then(&{:ok, &1})
  end

  def update(%{event: "image_processed", image: image}, socket) do
    {:ok, handle_image_complete(socket, image)}
  end

  def update(%{event: "image_editor_new_copy", new_image: new_image}, socket) do
    socket
    |> Block.commit_ref_data(
      ref_data: Block.current_block_data_map(socket.assigns.block, @override_fields),
      image_id: new_image.id,
      force_render: true
    )
    |> assign(:image, new_image)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    block_data_cs = Block.get_block_data_changeset(assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)
    uid = assigns.ref_form[:uid].value
    form_id = assigns[:form_id] || socket.assigns[:form_id] || BrandoAdmin.Utils.derive_form_id(assigns.ref_form.name)

    socket =
      socket
      |> assign(assigns)
      |> assign(:uid, uid)
      |> assign(:block_data, block_data)
      |> assign(:form_id, form_id)
      |> assign_new(:compact, fn -> true end)
      |> assign_new(:image, fn ->
        Block.resolve_ref_association(assigns[:ref_form], :image, :image_id, &Brando.Images.get_image/1)
      end)

    {:ok, assign(socket, image_display_assigns(socket.assigns.image))}
  end

  defp handle_image_complete(socket, image) do
    socket
    |> Block.commit_ref_data(
      ref_data: Block.current_block_data_map(socket.assigns.block, @override_fields),
      image_id: image.id,
      force_render: true
    )
    |> assign(:image, image)
    |> assign(image_display_assigns(image))
  end

  defp image_display_assigns(nil) do
    %{extracted_path: nil, extracted_filename: nil, file_name: nil, upload_formats: ""}
  end

  defp image_display_assigns(image) do
    extracted_path = Map.get(image, :path)
    extracted_filename = extracted_path && Path.basename(extracted_path)

    upload_formats =
      case Map.get(image, :formats) do
        formats when is_list(formats) -> Enum.join(formats, ",")
        _ -> ""
      end

    %{
      extracted_path: extracted_path,
      extracted_filename: extracted_filename,
      file_name: extracted_filename,
      upload_formats: upload_formats
    }
  end

  def render(assigns) do
    ~H"""
    <div>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <div
          id={"block-#{@uid}-wrapper"}
          class="picture-block"
        >
          <Block.block
            id={"block-#{@uid}-base"}
            block={@block}
            is_ref?={true}
            multi={false}
            target={@target}
            ref_form={@ref_form}
            config_open={@config_open}
          >
            <:description>
              <%= if @ref_description not in ["", nil] do %>
                {@ref_description}
              <% else %>
                {@extracted_filename}
              <% end %>
            </:description>
            <div
              :if={@extracted_path}
              class={["preview", (@compact && "compact") || "classic"]}
              phx-click={!@compact && "open_block_config"}
              phx-value-uid={@uid}
              phx-target={@target}
            >
              <div class="image-wrapper">
                <Content.image image={@image} size={:largest} />
                <button
                  class="edit-image-btn"
                  type="button"
                  phx-click={
                    JS.push("open_image_editor", target: @myself)
                    |> toggle_drawer("#image-editor-drawer")
                  }
                >
                  <.icon name="hero-pencil-square" />
                </button>
              </div>
              <div class="image-info">
                <figcaption
                  phx-click={!@compact && "open_block_config"}
                  phx-value-uid={@uid}
                  phx-target={@target}
                >
                  <div class="info-wrapper">
                    <div class="filename">{@file_name}</div>
                    <div class="title-and-alt">
                      <div class="dims">{@image.width}&times;{@image.height}</div>
                      <div id={"block-#{@uid}-figcaption-title"}>
                        <span>{gettext("Caption")}</span>
                        <%= if @block_data.title in [nil, ""] do %>
                          {gettext("<no caption>")}
                        <% else %>
                          {@block_data.title |> HtmlSanitizeEx.basic_html() |> raw()}
                        <% end %>
                      </div>
                      <div id={"block-#{@uid}-figcaption-alt"}>
                        <span>{gettext("Alt. text")}</span> {@block_data.alt ||
                          gettext("<no alt.text>")}
                      </div>
                    </div>
                  </div>
                  <button class="tiny" type="button" phx-click="open_block_config" phx-value-uid={@uid} phx-target={@target}>
                    {gettext("Edit image")}
                  </button>
                </figcaption>
              </div>
            </div>

            <div
              id={"block-#{@uid}-upload"}
              phx-hook="Brando.UploadTrigger"
              data-kind="block_ref_picture"
              data-component-id={"#{@uid}-picture"}
              data-asset-type="image"
              data-config-target={@block_data.config_target || "default"}
              data-folder-browser="true"
              data-accept=".jpg,.jpeg,.png,.gif,.webp,.svg"
              class={["empty", "upload-canvas", @extracted_path && "hidden"]}
            >
              <input type="file" class="file-input" accept=".jpg,.jpeg,.png,.gif,.webp,.svg" />
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
                <button type="button" class="tiny" phx-click="open_block_config" phx-value-uid={@uid} phx-target={@target}>
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
                  <div
                    :if={!@extracted_path}
                    id={"block-#{@uid}-modal-upload"}
                    phx-hook="Brando.UploadTrigger"
                    data-kind="block_ref_picture"
                    data-component-id={"#{@uid}-picture"}
                    data-asset-type="image"
                    data-config-target={@block_data.config_target || "default"}
                    data-folder-browser="true"
                    data-accept=".jpg,.jpeg,.png,.gif,.webp,.svg"
                    class="img-placeholder empty upload-canvas"
                  >
                    <input type="file" class="file-input" accept=".jpg,.jpeg,.png,.gif,.webp,.svg" />
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

                    <button
                      :if={@image}
                      type="button"
                      class="secondary"
                      phx-click={
                        JS.push("close_block_config", target: @target)
                        |> JS.push("open_image_editor", target: @myself)
                        |> toggle_drawer("#image-editor-drawer")
                      }
                    >
                      {gettext("Edit/Crop")}
                    </button>

                    <button type="button" class="danger" phx-click={JS.push("reset_image", target: @myself)}>
                      {gettext("Reset image")}
                    </button>
                  </div>
                  <Input.input type={:hidden} field={block_data[:config_target]} />
                  <Input.rich_text
                    field={block_data[:title]}
                    label={gettext("Caption")}
                    default_value={@image && @image.title}
                    reset
                    opts={[]}
                  />
                  <Input.override_text
                    field={block_data[:alt]}
                    label={gettext("Alt")}
                    default_value={@image && @image.alt}
                    target={@myself}
                  />
                  <Input.override_text
                    field={block_data[:credits]}
                    label={gettext("Credits")}
                    default_value={@image && @image.credits}
                    target={@myself}
                  />
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
              <Input.input type={:hidden} field={block_data[:moonwalk]} />
              <Input.input type={:hidden} field={block_data[:lazyload]} />

              <input type="hidden" data-upload-formats={@upload_formats} />
            </:config>
          </Block.block>
        </div>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("focus", _, socket), do: {:noreply, socket}

  def handle_event("set_target", _, socket) do
    config_target = Map.get(socket.assigns.block_data, :config_target, "default") || "default"

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: config_target,
      event_target: socket.assigns.myself,
      multi: false,
      selected_images: if(socket.assigns.image, do: [socket.assigns.image.id], else: [])
    )

    {:noreply, socket}
  end

  def handle_event("reset_image", _, socket) do
    # Reset to empty picture block data with no image association
    new_data =
      %PictureBlock.Data{}
      |> Map.from_struct()
      |> Map.take(@override_fields)

    socket
    |> Block.commit_ref_data(ref_data: new_data, image_id: nil, force_render: true)
    |> assign(:image, nil)
    |> assign(image_display_assigns(nil))
    |> then(&{:noreply, &1})
  end

  def handle_event("select_image", %{"id" => id}, socket) do
    {:ok, image} = Brando.Images.get_image(id)

    socket
    |> Block.commit_ref_data(
      # Only keep override fields in block data, image data goes to association
      ref_data: Block.current_block_data_map(socket.assigns.block, @override_fields),
      image_id: image.id
    )
    |> assign(:image, image)
    |> assign(image_display_assigns(image))
    |> then(&{:noreply, &1})
  end

  def handle_event("open_image_editor", _, socket) do
    image = socket.assigns.image

    {:noreply, Block.push_image_editor_init(socket, image, block_target: {__MODULE__, socket.assigns.id})}
  end

  def handle_event("show_image_picker", _, socket) do
    {:ok, images} = Brando.Images.list_images()
    {:noreply, assign(socket, :images, images)}
  end
end
