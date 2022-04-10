defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext

  alias Brando.Blueprint.Villain.Blocks
  alias Brando.Blueprint.Villain.Blocks.GalleryBlock
  alias Brando.Utils
  alias Brando.Villain

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks

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
  # data available_images, :list
  # data images, :list
  # data has_images?, :boolean
  # data image, :any
  # data selected_images_paths, :list
  # data display, :atom
  # data show_only_selected?, :boolean
  # data upload_formats, :string

  def v(form, field), do: input_value(form, field)

  def mount(socket) do
    {:ok, assign(socket, available_images: [], show_only_selected?: false)}
  end

  def update(assigns, socket) do
    block_data =
      assigns.block
      |> inputs_for(:data)
      |> List.first()

    images = input_value(block_data, :images)
    selected_images_paths = Enum.map(images, & &1.path)

    upload_formats =
      case v(block_data, :formats) do
        nil -> ""
        formats -> Enum.join(formats, ",")
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:images, images)
     |> assign(:indexed_images, Enum.with_index(images))
     |> assign(:upload_formats, upload_formats)
     |> assign(:display, v(block_data, :display))
     |> assign(:selected_images_paths, selected_images_paths)
     |> assign(:has_images?, !Enum.empty?(images))
     |> assign(:uid, v(assigns.block, :uid))}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="gallery-block"
      phx-hook="Brando.LegacyImageUpload"
      data-upload-multi="true"
      data-text-uploading={gettext("Uploading...")}
      data-block-index={@index}
      data-block-uid={@uid}>

      <Blocks.block
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
          <%= input_value(@block_data, :type) %>
          <%= if @ref_description do %>
            — <%= @ref_description %>
          <% end %>
        </:description>

        <div
          id={"block-#{@uid}-base-f-in"}
          phx-update="ignore">
          <input
            name={"block-#{@uid}-f-in"}
            class="file-input"
            type="file"
            multiple>
        </div>

        <%= for image <- inputs_for(@block_data, :images) do %>
          <Input.input type={:hidden} form={image} field={:placeholder} />
          <Input.input type={:hidden} form={image} field={:cdn} />
          <Input.input type={:hidden} form={image} field={:dominant_color} />
          <Input.input type={:hidden} form={image} field={:height} />
          <Input.input type={:hidden} form={image} field={:width} />
          <Input.input type={:hidden} form={image} field={:path} />

          <Form.inputs
            form={image}
            for={:focal}
            let={%{form: focal_form}}>
            <Input.input type={:hidden} form={focal_form} field={:x} />
            <Input.input type={:hidden} form={focal_form} field={:y} />
          </Form.inputs>

          <Form.map_inputs
            let={%{value: value, name: name}}
            form={image}
            for={:sizes}>
            <input type="hidden" name={"#{name}"} value={"#{value}"} />
          </Form.map_inputs>

          <Form.array_inputs
            let={%{value: array_value, name: array_name}}
            form={image}
            for={:formats}>
            <input type="hidden" name={array_name} value={array_value} />
          </Form.array_inputs>
        <% end %>

        <%= if @has_images? do %>
          <span
            id={"block-#{@uid}-base-file-upload-btn"}
            phx-update="ignore">
            <button type="button" class="tiny file-upload" id={"block-#{@uid}-up-btn"}><%= gettext "Upload images" %></button>
          </span>
          <button type="button" class="tiny" phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}><%= gettext "Select images" %></button>
          <button type="button" class="tiny" phx-click={JS.push("show_captions", target: @myself) |> show_modal("#block-#{@uid}_captions")}><%= gettext "Edit captions" %></button>
          <div
            id={"sortable-#{@block_data.id}-images"}
            class={render_classes([
              "images",
              @display == :grid && "images-grid" || "images-list"
            ])}
            phx-hook="Brando.Sortable"
            data-target={@myself}
            data-sortable-id={"sortable-#{@block_data.id}-images"}
            data-sortable-handle=".sort-handle"
            data-sortable-selector=".preview">
            <%= if @display == :grid do %>
              <%= for {img, idx} <- @indexed_images do %>
                <div
                  class={render_classes([
                    "preview",
                    "sort-handle",
                    "draggable"
                  ])}
                  data-id={idx}>
                  <Content.image image={img} size={:thumb} />
                  <figcaption phx-click={JS.push("show_captions", target: @myself) |> show_modal("#block-#{@uid}_captions")}>
                    <div>
                      <span><%= gettext("Caption") %></span>
                      <%= raw(img.title || "{ #{gettext"No caption"} }") %>
                    </div>
                    <div>
                      <span><%= gettext("Alt. text") %></span>
                      <%= img.alt || "{ #{gettext"No alt text"} }" %>
                    </div>
                  </figcaption>
                </div>
              <% end %>
            <% else %>
              <%= for img <- @images do %>
                <div class="preview">
                  <figure>
                    <Content.image image={img} size={:smallest} />
                  </figure>
                  <figcaption phx-click={show_modal("#block-#{@uid}_config")}>
                    <div>
                      <span><%= gettext("Caption") %></span>
                      <%= raw(img.title || "{ #{gettext"No caption"} }") %>
                    </div>
                    <div>
                      <span><%= gettext("Alt. text") %></span>
                      <%= img.alt || "{ #{gettext"No alt text"} }" %>
                    </div>
                    <div>
                      <span><%= gettext("Dimensions") %></span>
                      <%= img.width %>&times;<%= img.height %>
                    </div>
                  </figcaption>
                </div>
              <% end %>
            <% end %>
          </div>
        <% else %>
          <div class={render_classes([
            "upload-canvas",
            "empty",
            hidden: @has_images?
          ])}>
            <figure>
              <svg class="icon-add-gallery" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                <path fill="none" d="M0 0h24v24H0z"/><path d="M8 1v4H4v14h16V3h1.008c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3H6V1h2zm4 7l4 4h-3v4h-2v-4H8l4-4zm6-7v4h-8V3h6V1h2z"/>
              </svg>
            </figure>
            <div class="instructions">
              <span><%= gettext("Click or drag images here &uarr; to upload") |> raw() %></span><br>
              <button type="button" class="tiny" phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}>pick existing images</button>
            </div>
          </div>
        <% end %>

        <Content.modal
          title="Edit captions"
          id={"block-#{@uid}_captions"}>
          <div class="caption-editor">
            <%= for image <- inputs_for(@block_data, :images) do %>
              <div class="caption-row">
                <figure>
                  <Content.image image={image.data} size={:thumb} />
                </figure>
                <div>
                  <Input.rich_text form={image} field={:title} label={gettext "Title"} />
                  <Input.text form={image} field={:credits} label={gettext "Credits"} />
                  <Input.text form={image} field={:alt} label={gettext "Alt. text"} />
                </div>
              </div>
            <% end %>
          </div>
        </Content.modal>

        <:config>
          <Input.input type={:hidden} form={@block_data} field={:type} />
          <Input.radios
            form={@block_data}
            field={:display}
            label={gettext("Display")}
            opts={[options: [
              %{label: "Grid", value: :grid},
              %{label: "List", value: :list},
            ]]} />
          <Input.text form={@block_data} field={:class} label={gettext "Class"} />
          <Input.text form={@block_data} field={:series_slug} label={gettext "Series slug"} />
          <Input.toggle form={@block_data} field={:lightbox} label={gettext "Lightbox"} />

          <Input.radios
            form={@block_data}
            field={:placeholder}
            label={gettext "Placeholder"}
            opts={[options: [
              %{label: "SVG", value: :svg},
              %{label: "Dominant Color", value: :dominant_color},
              %{label: "Micro", value: :micro},
              %{label: "None", value: :none}
            ]]} />

          <Form.array_inputs
            let={%{value: array_value, name: array_name}}
            form={@block_data}
            for={:formats}>
            <input type="hidden" name={array_name} value={array_value} />
          </Form.array_inputs>

          <input type="hidden" data-upload-formats={@upload_formats} />
        </:config>
      </Blocks.block>
    </div>
    """
  end

  def handle_event("toggle_only_selected", _, socket) do
    {:noreply, assign(socket, :show_only_selected?, !socket.assigns.show_only_selected?)}
  end

  def handle_event(
        "sequenced",
        %{"ids" => order_indices},
        %{
          assigns: %{
            base_form: form,
            block_data: block_data,
            data_field: data_field,
            uid: uid
          }
        } = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    images = input_value(block_data, :images)
    sorted_images = Enum.map(order_indices, &Enum.at(images, &1))

    updated_changeset =
      Villain.update_block_in_changeset(changeset, data_field, uid, %{
        data: %{images: sorted_images}
      })

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "image_uploaded",
        %{"id" => id},
        %{
          assigns: %{
            block_data: block_data,
            base_form: base_form,
            uid: uid,
            data_field: data_field
          }
        } = socket
      ) do
    {:ok, image} = Brando.Images.get_image(id)
    picture_data_tpl = struct(Blocks.PictureBlock.Data, Map.from_struct(image))

    images = input_value(block_data, :images) ++ [picture_data_tpl]

    changeset = base_form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_changeset =
      Villain.update_block_in_changeset(changeset, data_field, uid, %{data: %{images: images}})

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

    empty_block = %GalleryBlock{
      uid: Utils.generate_uid(),
      data: %GalleryBlock.Data{}
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
        %{"id" => id, "selected" => "false"},
        %{
          assigns: %{
            base_form: base_form,
            uid: uid,
            block_data: block_data,
            data_field: data_field
          }
        } = socket
      ) do
    {:ok, image} = Brando.Images.get_image(id)
    picture_data_tpl = struct(Blocks.PictureBlock.Data, Map.from_struct(image))

    images = input_value(block_data, :images) ++ [picture_data_tpl]

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      selected_images: Enum.map(images, & &1.path)
    )

    changeset = base_form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_changeset =
      Villain.update_block_in_changeset(changeset, data_field, uid, %{data: %{images: images}})

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "select_image",
        %{"id" => id, "selected" => "true"},
        %{
          assigns: %{
            base_form: base_form,
            uid: uid,
            block_data: block_data,
            data_field: data_field
          }
        } = socket
      ) do
    {:ok, image} = Brando.Images.get_image(id)
    images = Enum.reject(input_value(block_data, :images), &(&1.path == image.path))

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      selected_images: Enum.map(images, & &1.path)
    )

    changeset = base_form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_changeset =
      Villain.update_block_in_changeset(changeset, data_field, uid, %{data: %{images: images}})

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "set_target",
        _,
        %{assigns: %{myself: myself, images: images}} = socket
      ) do
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
