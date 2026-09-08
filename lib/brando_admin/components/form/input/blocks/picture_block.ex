defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Assets.MediaField
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
    :config_target,
    :formats,
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

  def update(%{event: "image_uploaded", expected_asset_id: expected} = assigns, socket) do
    current_id = socket.assigns[:image] && socket.assigns.image.id

    if Brando.Uploads.AssetIntent.current_selection?(expected, current_id) do
      update(Map.delete(assigns, :expected_asset_id), socket)
    else
      {:ok, socket}
    end
  end

  def update(%{event: "image_uploaded", image: image}, socket) do
    {:ok, handle_image_complete(socket, image)}
  end

  def update(%{event: "image_processed", image: image}, socket) do
    if socket.assigns.image && socket.assigns.image.id == image.id do
      {:ok, assign(socket, :image, image) |> assign(image_display_assigns(image))}
    else
      {:ok, socket}
    end
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
            config_layout="editor"
            config_title={gettext("Configure image")}
            config_subtitle={@ref_description || gettext("Settings for this use of the image")}
            config_icon="hero-photo"
          >
            <:description>
              <%= if @ref_description not in ["", nil] do %>
                {@ref_description}
              <% else %>
                {@extracted_filename}
              <% end %>
            </:description>
            <MediaField.field
              id={"block-#{@uid}-upload"}
              type={:image}
              asset={@image}
              kind="block_ref_picture"
              component_id={"#{@uid}-picture"}
              config_target={@block_data.config_target || "default"}
              browse={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
              remove={JS.push("reset_image", target: @myself)}
              presentation={:block}
              label={@ref_description}
              configure={JS.push("open_block_config", target: @target, value: %{uid: @uid})}
            >
              <:actions :if={@image}>
                <button
                  class="media-button edit-image-btn"
                  type="button"
                  phx-click={JS.push("open_image_editor", target: @myself) |> toggle_drawer("#image-editor-drawer")}
                >
                  <.icon name="hero-scissors" />{gettext("Edit/Crop")}
                </button>
              </:actions>
            </MediaField.field>

            <:config>
              <Content.modal_sections id={"image-#{@uid}-config-sections"}>
                <:section id="content" label={gettext("Text & link")} icon="hero-document-text">
                  <div class="media-section-heading">
                    <h3 class="modal-section-title">{gettext("Text & link")}</h3>
                    <p class="modal-muted">
                      {gettext("Customize this use of the image. Empty text overrides use the library values.")}
                    </p>
                  </div>
                  <Input.rich_text
                    field={block_data[:title]}
                    label={gettext("Caption")}
                    default_value={@image && @image.title}
                    reset
                    opts={[]}
                  />
                  <Input.override_text
                    field={block_data[:alt]}
                    label={gettext("Alternative text")}
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
                </:section>
                <:section id="image" label={gettext("Image")} icon="hero-photo">
                  <div class="media-section-heading">
                    <h3 class="modal-section-title">{gettext("Selected image")}</h3>
                    <p class="modal-muted">{gettext("Replace the image while keeping this reference’s settings.")}</p>
                  </div>
                  <MediaField.field
                    id={"block-#{@uid}-modal-upload"}
                    type={:image}
                    asset={@image}
                    kind="block_ref_picture"
                    component_id={"#{@uid}-picture"}
                    config_target={@block_data.config_target || "default"}
                    browse={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
                    remove={JS.push("reset_image", target: @myself)}
                    presentation={:block}
                  >
                    <:actions>
                      <button
                        :if={@image}
                        type="button"
                        class="media-button"
                        phx-click={
                          JS.push("close_block_config", target: @target)
                          |> JS.push("open_image_editor", target: @myself)
                          |> toggle_drawer("#image-editor-drawer")
                        }
                      >
                        <.icon name="hero-scissors" />{gettext("Edit/Crop")}
                      </button>
                    </:actions>
                  </MediaField.field>
                </:section>
                <:section id="display" label={gettext("Display")} icon="hero-adjustments-horizontal">
                  <div class="media-section-heading">
                    <h3 class="modal-section-title">{gettext("Display")}</h3>
                    <p class="modal-muted">{gettext("Control how the image loads in this reference.")}</p>
                  </div>
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
                  <Input.text field={block_data[:img_class]} label={gettext("Image CSS classes")} />
                  <Input.text field={block_data[:picture_class]} label={gettext("Wrapper CSS classes")} />
                </:section>
              </Content.modal_sections>
              <Input.input type={:hidden} field={block_data[:config_target]} />

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
    new_data = Block.current_block_data_map(socket.assigns.block, @override_fields)

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
