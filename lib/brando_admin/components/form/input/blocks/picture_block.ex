defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  import Brando.Gettext

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
  # data images, :list
  # data image, :any
  # data upload_formats, :string

  @fields_to_take [
    :picture_class,
    :img_class,
    :link,
    :srcset,
    :media_queries,
    :formats,
    :path,
    :width,
    :height,
    :sizes,
    :cdn,
    :lazyload,
    :moonwalk,
    :dominant_color,
    :placeholder,
    :focal,
    :fetchpriority
  ]

  def mount(socket) do
    socket
    |> assign(:images, [])
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    block_data_cs = Block.get_block_data_changeset(assigns.block)

    {extracted_path, extracted_filename} =
      case Changeset.get_field(block_data_cs, :path) do
        nil -> {nil, nil}
        path -> {path, Path.basename(path)}
      end

    upload_formats =
      case Changeset.get_field(block_data_cs, :formats) do
        nil -> ""
        formats -> Enum.join(formats, ",")
      end

    image = Changeset.apply_changes(block_data_cs)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:image, image)
     |> assign(:upload_formats, upload_formats)
     |> assign(:extracted_path, extracted_path)
     |> assign(:extracted_filename, extracted_filename)
     |> assign(:uid, assigns.block[:uid].value)}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="picture-block"
      phx-hook="Brando.LegacyImageUpload"
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
            <%= if @ref_description do %>
              <%= @ref_description %>
            <% else %>
              <%= @extracted_filename %>
            <% end %>
          </:description>
          <input class="file-input" type="file" />
          <div :if={@extracted_path} class="preview" phx-click={show_modal("#block-#{@uid}_config")}>
            <Content.image image={@image} size={:largest} />
            <figcaption phx-click={show_modal("#block-#{@uid}_config")}>
              <div id={"block-#{@uid}-figcaption-title"}>
                <span><%= gettext("Caption") %></span> <%= @image.title |> raw || "—" %><br />
              </div>
              <div id={"block-#{@uid}-figcaption-alt"}>
                <span><%= gettext("Alt. text") %></span> <%= @image.alt || "—" %>
              </div>
            </figcaption>
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
              <span><%= gettext("Click or drag an image &uarr; to upload") |> raw() %></span>
              <br />
              <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}>
                <%= gettext("Pick an existing image") %>
              </button>
            </div>
          </div>

          <:config>
            <div class="panels">
              <div class="panel">
                <%= if @extracted_path do %>
                  <Content.image image={@image} size={:largest} />
                  <div class="image-info">
                    Path: <%= @image.path %><br />
                    Dimensions: <%= @image.width %>&times;<%= @image.height %><br />
                  </div>
                <% end %>
                <div :if={!@extracted_path} class="img-placeholder empty upload-canvas">
                  <div class="placeholder-wrapper">
                    <div class="svg-wrapper">
                      <svg
                        class="icon-add-image"
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 24 24"
                      >
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
                    <span><%= gettext("Click or drag an image &uarr; to upload") |> raw() %></span>
                  </div>
                </div>
              </div>
              <div class="panel">
                <Input.rich_text field={block_data[:title]} label={gettext("Title")} />
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

                <div class="button-group-vertical">
                  <button
                    type="button"
                    class="secondary"
                    phx-click={
                      JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")
                    }
                  >
                    <%= gettext("Select image") %>
                  </button>

                  <button
                    type="button"
                    class="danger"
                    phx-click={JS.push("reset_image", target: @myself)}
                  >
                    <%= gettext("Reset image") %>
                  </button>
                </div>
              </div>
            </div>

            <Input.input type={:hidden} field={block_data[:placeholder]} />
            <Input.input type={:hidden} field={block_data[:cdn]} />
            <Input.input type={:hidden} field={block_data[:moonwalk]} />
            <Input.input type={:hidden} field={block_data[:lazyload]} />
            <Input.input type={:hidden} field={block_data[:credits]} />
            <Input.input type={:hidden} field={block_data[:dominant_color]} />
            <Input.input type={:hidden} field={block_data[:height]} />
            <Input.input type={:hidden} field={block_data[:width]} />

            <%= if is_nil(block_data[:path].value) and !is_nil(block_data[:sizes].value) do %>
              <Input.input type={:hidden} field={block_data[:path]} value={@extracted_path} />
            <% else %>
              <Input.input type={:hidden} field={block_data[:path]} />
            <% end %>

            <.inputs_for :let={focal_form} field={block_data[:focal]}>
              <Input.input type={:hidden} field={focal_form[:x]} />
              <Input.input type={:hidden} field={focal_form[:y]} />
            </.inputs_for>

            <Form.map_inputs :let={%{value: value, name: name}} field={block_data[:sizes]}>
              <input type="hidden" name={name} value={value} />
            </Form.map_inputs>

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

  def handle_event("image_uploaded", %{"id" => id}, socket) do
    block = socket.assigns.block
    block_data_cs = Block.get_block_data_changeset(block)
    block_data = Changeset.apply_changes(block_data_cs)

    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    {:ok, image} = Brando.Images.get_image(id)

    new_data =
      block_data
      |> Map.merge(image)
      |> Map.from_struct()
      |> Map.take(@fields_to_take)

    send_update(target, %{event: "update_ref_data", ref_data: new_data, ref_name: ref_name})

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
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    new_data =
      %PictureBlock.Data{}
      |> Map.from_struct()
      |> Map.take(@fields_to_take)

    uid = socket.assigns.uid
    send_update(target, %{event: "update_ref_data", ref_data: new_data, ref_name: ref_name})

    {:noreply, push_event(socket, "b:picture_block:attach_listeners:#{uid}", %{})}
  end

  def handle_event("select_image", %{"id" => id}, socket) do
    block = socket.assigns.block
    block_data_cs = Block.get_block_data_changeset(block)
    block_data = Changeset.apply_changes(block_data_cs)

    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    {:ok, image} = Brando.Images.get_image(id)

    new_data =
      block_data
      |> Map.merge(image)
      |> Map.from_struct()
      |> Map.take(@fields_to_take)

    send_update(target, %{event: "update_ref_data", ref_data: new_data, ref_name: ref_name})
    {:noreply, socket}
  end

  def handle_event("show_image_picker", _, socket) do
    {:ok, images} = Brando.Images.list_images()
    {:noreply, assign(socket, :images, images)}
  end
end
