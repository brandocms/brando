defmodule BrandoAdmin.Components.Form.Input.Blocks.PictureBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext

  alias Brando.Blueprint.Villain.Blocks.PictureBlock
  alias Brando.Utils
  alias Brando.Villain

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Modal

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

  # prop insert_block, :event, required: true
  # prop duplicate_block, :event, required: true

  # data extracted_path, :string
  # data uid, :string
  # data block_data, :form
  # data images, :list
  # data image, :any
  # data upload_formats, :string

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

    upload_formats =
      case v(block_data, :formats) do
        nil -> ""
        formats -> Enum.join(formats, ",")
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:image, v(assigns.block, :data))
     |> assign(:upload_formats, upload_formats)
     |> assign(:extracted_path, extracted_path)
     |> assign(:uid, v(assigns.block, :uid))}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="picture-block"
      phx-hook="Brando.LegacyImageUpload"
      data-text-uploading={gettext("Uploading...")}
      data-block-index={@index}
      data-block-uid={@uid}>

      <.live_component
        module={Block}
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>
          <%= if @ref_description do %>
            <%= @ref_description %>
          <% else %>
            <%= @extracted_path %>
          <% end %>
        </:description>
        <input class="file-input" type="file" />
        <%= if @extracted_path do %>
          <div class="preview" phx-click={show_modal("#block-#{@uid}_config")}>
            <img src={"/media/#{@extracted_path}"} />
            <figcaption phx-click={show_modal("#block-#{@uid}_config")}>
              <div id={"block-#{@uid}-figcaption-title"}>
                <span><%= gettext("Caption") %></span> <%= v(@block_data, :title) |> raw %><br>
              </div>
              <div id={"block-#{@uid}-figcaption-alt"}>
                <span><%= gettext("Alt. text") %></span> <%= v(@block_data, :alt) %>
              </div>
            </figcaption>
          </div>
        <% end %>

        <div class={render_classes(["empty", "upload-canvas", hidden: @extracted_path])}>
          <figure>
            <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none"/>
              <polygon class="plus" points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"/>
              <path d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z" transform="translate(0 0)"/>
              <circle cx="8" cy="9" r="2"/>
            </svg>
          </figure>
          <div class="instructions">
            <span><%= gettext("Click or drag an image &uarr; to upload") |> raw() %></span><br>
            <button type="button" class="tiny" phx-click={JS.push("show_image_picker", target: @myself) |> show_modal("#block-#{@uid}-image-picker")}>
              <%= gettext "Pick an existing image" %>
            </button>
          </div>
        </div>

        <.live_component module={Modal}
          title="Pick image"
          center_header={true}
          id={"block-#{@uid}-image-picker"}>
          <div class="image-picker-images">
            <%= for image <- @images do %>
              <div class="image-picker-image" phx-click={JS.push("select_image", target: @myself) |> hide_modal("#block-#{@uid}-image-picker")} phx-value-id={image.id}>
                <img src={"/media/#{image.sizes["thumb"]}"} />
              </div>
            <% end %>
          </div>
        </.live_component>

        <:config>
          <div class="panels">
            <div class="panel">
              <%= if @extracted_path do %>
                <img
                  width={"#{@image.width}"}
                  height={"#{@image.height}"}
                  src={"#{Utils.img_url(@image, :original, prefix: Utils.media_url())}"} />

                <div class="image-info">
                  Path: <%= @image.path %><br>
                  Dimensions: <%= @image.width %>&times;<%= @image.height %><br>
                </div>
              <% end %>
              <%= if !@extracted_path do %>
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
                    <span><%= gettext("Click or drag an image &uarr; to upload") |> raw() %></span>
                  </div>
                </div>
              <% end %>
            </div>
            <div class="panel">
              <Input.RichText.render form={@block_data} field={:title} label={gettext "Title"} />
              <Input.Text.render form={@block_data} field={:alt} label={gettext "Alt"} />

              <div class="button-group-vertical">
                <button type="button" class="secondary" phx-click={JS.push("show_image_picker", target: @myself) |> show_modal("#block-#{@uid}-image-picker")}>
                  <%= gettext("Select image") %>
                </button>

                <button type="button" class="danger" phx-click={JS.push("reset_image", target: @myself)}>
                  <%= gettext("Reset image") %>
                </button>
              </div>
            </div>
          </div>

          <%= hidden_input @block_data, :placeholder %>
          <%= hidden_input @block_data, :cdn %>
          <%= hidden_input @block_data, :moonwalk %>
          <%= hidden_input @block_data, :lazyload %>
          <%= hidden_input @block_data, :credits %>
          <%= hidden_input @block_data, :dominant_color %>
          <%= hidden_input @block_data, :height %>
          <%= hidden_input @block_data, :width %>

          <%= if is_nil(v(@block_data, :path)) and !is_nil(v(@block_data, :sizes)) do %>
            <%= hidden_input @block_data, :path, value: @extracted_path %>
            <% else %>
            <%= hidden_input @block_data, :path %>
          <% end %>

          <Form.inputs
            form={@block_data}
            for={:focal}
            let={%{form: focal_form}}>
            <%= hidden_input focal_form, :x %>
            <%= hidden_input focal_form, :y %>
          </Form.inputs>

          <Form.map_inputs
            let={%{value: value, name: name}}
            form={@block_data}
            for={:sizes}>
            <input type="hidden" name={"#{name}"} value={"#{value}"} />
          </Form.map_inputs>

          <Form.array_inputs
            let={%{value: array_value, name: array_name}}
            form={@block_data}
            for={:formats}>
            <input type="hidden" name={array_name} value={array_value} />
          </Form.array_inputs>

          <input type="hidden" data-upload-formats={@upload_formats} />
        </:config>
      </.live_component>
    </div>
    """
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
      |> Map.merge(image)
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
      updated_changeset: updated_changeset,
      force_validation: true
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
      updated_changeset: updated_changeset,
      force_validation: true
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
    {:ok, image} = Brando.Images.get_image(id)

    updated_data_map =
      block_data.data
      |> Map.merge(image)
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
      updated_changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end

  def handle_event("show_image_picker", _, socket) do
    {:ok, images} = Brando.Images.list_images()
    {:noreply, assign(socket, :images, images)}
  end
end
