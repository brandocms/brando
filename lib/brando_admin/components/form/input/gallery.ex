defmodule BrandoAdmin.Components.Form.Input.Gallery do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Ecto.Changeset
  import Brando.Gettext

  alias Brando.Utils
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input

  alias Brando.Images.GalleryImage

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean

  # data gallery, :any
  # data preview_layout, :atom
  # data selected_images, :list

  def update(assigns, socket) do
    schema = assigns.form.data.__struct__

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(preview_layout: assigns.opts[:layout] || :grid)
     |> assign(:schema, schema)
     |> assign_value()}
  end

  defp get_gallery_images(%{gallery_images: nil}), do: []
  defp get_gallery_images(%{gallery_images: []}), do: []
  defp get_gallery_images(%{gallery_images: %Ecto.Association.NotLoaded{}}), do: []
  defp get_gallery_images(%{gallery_images: gallery_images}), do: gallery_images
  defp get_gallery_images(_), do: []

  defp assign_value(%{assigns: %{form: form, field: field}} = socket) do
    gallery = get_field(form.source, field)
    gallery_images = get_gallery_images(gallery)

    socket
    |> assign(:gallery, gallery)
    |> assign_new(:selected_images, fn -> Enum.map(gallery_images, & &1.image.path) end)
    |> assign_new(:gallery_images, fn -> gallery_images end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base
        form={@form}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}>
        <div class="gallery-input">
          <%= if @gallery_images != [] do %>
            <%= for gallery_form <- inputs_for(@form, @field) do %>
              <Input.input type={:hidden} form={gallery_form} field={:id} />
              <Input.input type={:hidden} form={gallery_form} field={:config_target} />

              <%= for gallery_image <- inputs_for(gallery_form, :gallery_images) do %>
                <%= if input_value(gallery_image, :id) do %>
                  <Input.input type={:hidden} form={gallery_image} field={:id} />
                <% end %>
                <Input.input type={:hidden} form={gallery_image} field={:image_id} />
                <Input.input type={:hidden} form={gallery_image} field={:gallery_id} />
                <Input.input type={:hidden} form={gallery_image} field={:creator_id} />
                <Input.input type={:hidden} form={gallery_image} field={:sequence} />
              <% end %>
            <% end %>
          <% else %>
            <Input.input type={:hidden} form={@form} field={@field} value={""} />
          <% end %>

          <div class="actions">
            <button type="button" class="tiny upload-button">
              <%= gettext "Upload images" %>
              <%= live_file_input @uploads[@field] %>
            </button>
            <button
              phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
              type="button"
              class="tiny">
              <%= gettext "Select images" %>
            </button>
          </div>
          <%= if @gallery_images == [] do %>
          <small>
            <%= gettext "No associated gallery" %>
          </small>
          <% else %>
            <div
              id={"sortable-gallery-images"}
              phx-hook="Brando.Sortable"
              data-target={@myself}
              data-sortable-id={"sortable-gallery"}
              data-sortable-handle=".sort-handle"
              data-sortable-selector=".gallery-image"
              class="gallery-images">
              <%= for gallery_image <- @gallery_images do %>
                <figure
                  class="gallery-image sort-handle draggable"
                  data-id={gallery_image.image_id}>
                  <img
                    width="25"
                    height="25"
                    src={"#{Utils.img_url(gallery_image.image, :thumb, prefix: Utils.media_url())}"} />
                </figure>
              <% end %>
            </div>
          <% end %>
        </div>
      </Form.field_base>
    </div>
    """
  end

  defp sequence(gallery_images) do
    gallery_images
    |> Enum.with_index()
    |> Enum.map(fn {gi, idx} -> Map.put(gi, :sequence, idx) end)
  end

  def handle_event(
        "set_target",
        _,
        %{
          assigns: %{
            myself: myself,
            selected_images: selected_images,
            schema: schema,
            field: field
          }
        } = socket
      ) do
    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: {"gallery", schema, field},
      event_target: myself,
      multi: true,
      selected_images: selected_images
    )

    {:noreply, socket}
  end

  def handle_event(
        "select_image",
        %{"id" => image_id, "selected" => "false"},
        %{
          assigns: %{
            form: form,
            field: field,
            gallery_images: gallery_images,
            current_user: current_user
          }
        } = socket
      ) do
    changeset = form.source
    schema = form.data.__struct__
    gallery = get_field(changeset, field)

    {:ok, new_image} = Brando.Images.get_image(image_id)

    current_gallery_images =
      if gallery do
        Enum.map(
          gallery.gallery_images || [],
          &Map.take(&1, [:id, :image_id, :gallery_id, :sequence, :creator_id])
        )
      else
        []
      end

    new_gallery_image = %{image_id: String.to_integer(image_id), creator_id: current_user.id}
    new_gallery_images = current_gallery_images ++ List.wrap(new_gallery_image)

    new_gallery =
      if gallery do
        %{
          id: gallery.id,
          config_target: gallery.config_target,
          gallery_images: sequence(new_gallery_images)
        }
      else
        %{
          config_target: "gallery:#{inspect(schema)}:#{field}",
          gallery_images: sequence(new_gallery_images)
        }
      end

    new_gallery_images =
      gallery_images ++ List.wrap(%GalleryImage{image_id: new_image.id, image: new_image})

    selected_images =
      new_gallery_images
      |> Enum.map(& &1.image.path)

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      selected_images: selected_images
    )

    updated_changeset = put_assoc(changeset, field, new_gallery)

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply,
     assign(socket, gallery_images: new_gallery_images, selected_images: selected_images)}
  end

  def handle_event(
        "select_image",
        %{"id" => image_id, "selected" => "true"},
        %{
          assigns: %{
            form: form,
            field: field,
            gallery_images: gallery_images
          }
        } = socket
      ) do
    changeset = form.source
    gallery = get_field(changeset, field)

    new_gallery_images =
      Enum.filter(gallery_images, &(&1.image_id != String.to_integer(image_id)))

    selected_images = Enum.map(new_gallery_images, & &1.image.path)

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      selected_images: selected_images
    )

    slimmed_gallery_images =
      Enum.map(
        new_gallery_images,
        &Map.take(&1, [:id, :image_id, :gallery_id, :sequence, :creator_id])
      )

    new_gallery = %{
      id: gallery.id,
      config_target: gallery.config_target,
      gallery_images: sequence(slimmed_gallery_images)
    }

    updated_changeset = put_assoc(changeset, field, new_gallery)

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply,
     assign(socket, gallery_images: new_gallery_images, selected_images: selected_images)}
  end

  def handle_event(
        "sequenced",
        %{"ids" => order_indices},
        %{
          assigns: %{
            form: form,
            field: field_name,
            gallery_images: gallery_images
          }
        } = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    gallery = Ecto.Changeset.get_field(changeset, field_name)

    entries =
      Enum.map(
        gallery.gallery_images,
        &Map.take(&1, [:id, :image_id, :gallery_id, :sequence, :creator_id])
      )

    sorted_entries =
      Enum.map(Enum.with_index(order_indices), fn {id, idx} ->
        Enum.find(entries, &(to_string(&1.image_id) == to_string(id))) |> Map.put(:sequence, idx)
      end)

    sorted_gallery_images =
      Enum.map(order_indices, fn id -> Enum.find(gallery_images, &(&1.image_id == id)) end)

    updated_gallery = %{
      id: gallery.id,
      config_target: gallery.config_target,
      gallery_images: sorted_entries
    }

    updated_changeset = Ecto.Changeset.put_assoc(changeset, field_name, updated_gallery)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, assign(socket, :gallery_images, sorted_gallery_images)}
  end

  def handle_event("edit_image", %{"id" => _id}, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_selected", %{"ids" => ids_json}, socket) do
    rejected_indices =
      ids_json
      |> Jason.decode!()
      |> MapSet.new()

    field_name = socket.assigns.input.name
    changeset = socket.assigns.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    entries = Ecto.Changeset.get_field(changeset, field_name)

    filtered_entries =
      entries
      |> Stream.with_index()
      |> Stream.reject(fn {_item, index} -> index in rejected_indices end)
      |> Enum.map(&elem(&1, 0))

    updated_changeset = Ecto.Changeset.put_embed(changeset, field_name, filtered_entries)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, assign(socket, :selected_images, [])}
  end

  def handle_gallery_progress(
        key,
        upload_entry,
        %{
          assigns: %{
            current_user: current_user,
            schema: schema
          }
        } = socket
      ) do
    if upload_entry.done? do
      %{cfg: cfg} = schema.__asset_opts__(key)
      config_target = "gallery:#{inspect(schema)}:#{key}"

      image =
        consume_uploaded_entry(
          socket,
          upload_entry,
          fn meta ->
            Brando.Upload.handle_upload(
              Map.put(meta, :config_target, config_target),
              upload_entry,
              cfg,
              current_user
            )
          end
        )

      # Subscribe parent live view to changes to this image
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:gallery_image:#{image.id}", link: true)
      Brando.Images.Processing.queue_processing(image, current_user)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end
end
