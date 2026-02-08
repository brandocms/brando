defmodule BrandoAdmin.Components.Form.Input.GalleryObjects do
  @moduledoc """
  Custom `inputs_for` component for managing gallery objects directly
  on the Gallery schema's form. Supports adding images via ImagePicker,
  drag-and-drop reordering, and removal.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Galleries.GalleryObject
  alias Brando.Utils
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.ImagePicker

  def update(%{action: :update_image, updated_image: updated_image, force_validation: true}, socket) do
    updated_image_id = updated_image.id

    updated_gallery_objects =
      Enum.map(socket.assigns.gallery_objects, fn
        %{image_id: ^updated_image_id} = go -> %{go | image: updated_image}
        other -> other
      end)

    {:ok, assign(socket, :gallery_objects, updated_gallery_objects)}
  end

  def update(assigns, socket) do
    changeset = assigns.field.form.source
    gallery_objects = Ecto.Changeset.get_field(changeset, :gallery_objects) || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:gallery_objects, fn -> gallery_objects end)
     |> assign_new(:selected_images, fn -> Enum.map(gallery_objects, & &1.image_id) end)}
  end

  def render(assigns) do
    ~H"""
    <fieldset>
      <Form.field_base field={@field} label={@label} instructions={@instructions} class="subform">
        <div class="gallery-input">
          <div class="actions">
            <button
              phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
              type="button"
              class="tiny"
            >
              {gettext("Select images")}
            </button>
          </div>

          <%= if @gallery_objects == [] do %>
            <small>{gettext("No images in gallery")}</small>
          <% else %>
            <div
              id="sortable-gallery-objects-edit"
              phx-hook="Brando.SortableAssocs"
              data-target={@myself}
              data-sortable-id="sortable-gallery-edit"
              data-sortable-handle=".sort-handle"
              data-sortable-selector=".gallery-object"
              class="gallery-objects"
            >
              <.inputs_for :let={gallery_object} field={@field}>
                <figure class="gallery-object sort-handle draggable" data-id={gallery_object[:image_id].value}>
                  <.gallery_object_thumb
                    gallery_objects={@gallery_objects}
                    gallery_object_field={gallery_object}
                    form_name={@field.form.name}
                  />
                  <input
                    type="hidden"
                    name={"#{@field.form.name}[sort_gallery_object_ids][]"}
                    value={gallery_object.index}
                  />
                </figure>
                <Input.input type={:hidden} field={gallery_object[:image_id]} />
                <Input.input type={:hidden} field={gallery_object[:gallery_id]} />
                <Input.input type={:hidden} field={gallery_object[:creator_id]} />
              </.inputs_for>
            </div>
          <% end %>
        </div>
      </Form.field_base>
    </fieldset>
    """
  end

  defp gallery_object_thumb(assigns) do
    gallery_object =
      Enum.find(
        assigns.gallery_objects,
        &(to_string(&1.image_id) == to_string(assigns.gallery_object_field[:image_id].value))
      )

    assigns = assign(assigns, :gallery_object, gallery_object)

    ~H"""
    <div :if={@gallery_object && @gallery_object.image}>
      <%= if @gallery_object.image.status == :processed do %>
        <img
          width="25"
          height="25"
          src={"#{Utils.img_url(@gallery_object.image, :thumb, prefix: Utils.media_url())}"}
        />
        <button
          type="button"
          class="delete-object"
          name={"#{@form_name}[drop_gallery_object_ids][]"}
          value={@gallery_object_field.index}
          data-sortable-filter
          phx-click={JS.dispatch("change")}
        >
          <.icon name="hero-x-mark" />
        </button>
      <% else %>
        <div class="img-placeholder">
          <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
            <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
          </svg>
        </div>
      <% end %>
    </div>
    """
  end

  defp sequence(gallery_objects) do
    gallery_objects
    |> Enum.with_index()
    |> Enum.map(fn {gi, idx} -> Map.put(gi, :sequence, idx) end)
  end

  def handle_event("reposition", _, socket) do
    {:noreply, socket}
  end

  def handle_event("set_target", _, socket) do
    send_update(ImagePicker,
      id: "image-picker",
      config_target: {"gallery", Brando.Galleries.Gallery, :gallery_objects},
      event_target: socket.assigns.myself,
      multi: true,
      selected_images: socket.assigns.selected_images
    )

    {:noreply, socket}
  end

  def handle_event(
        "select_image",
        %{"id" => image_id, "selected" => "false"},
        %{assigns: %{field: field, gallery_objects: gallery_objects, current_user: current_user}} =
          socket
      ) do
    changeset = field.form.source
    {:ok, new_image} = Brando.Images.get_image(image_id)

    current_gallery_objects =
      Enum.map(
        gallery_objects,
        &Map.take(&1, [:id, :image_id, :video_id, :gallery_id, :sequence, :creator_id])
      )

    new_gallery_object = %{image_id: String.to_integer(image_id), creator_id: current_user.id}
    updated_gallery_objects = current_gallery_objects ++ [new_gallery_object]

    updated_changeset =
      Ecto.Changeset.put_assoc(changeset, :gallery_objects, sequence(updated_gallery_objects))

    new_gallery_objects =
      gallery_objects ++
        [
          %GalleryObject{
            image_id: new_image.id,
            image: new_image,
            creator_id: current_user.id
          }
        ]

    selected_objects = Enum.map(new_gallery_objects, & &1.image_id)

    send_update(ImagePicker,
      id: "image-picker",
      selected_images: selected_objects
    )

    form_id = "gallery_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, assign(socket, gallery_objects: new_gallery_objects, selected_images: selected_objects)}
  end

  def handle_event(
        "select_image",
        %{"id" => image_id, "selected" => "true"},
        %{assigns: %{field: field, gallery_objects: gallery_objects}} = socket
      ) do
    changeset = field.form.source
    image_id = (is_binary(image_id) && String.to_integer(image_id)) || image_id
    new_gallery_objects = Enum.filter(gallery_objects, &(&1.image_id != image_id))
    selected_objects = Enum.map(new_gallery_objects, & &1.image_id)

    send_update(ImagePicker,
      id: "image-picker",
      selected_images: selected_objects
    )

    slimmed_gallery_objects =
      Enum.map(
        new_gallery_objects,
        &Map.take(&1, [:id, :image_id, :video_id, :gallery_id, :sequence, :creator_id])
      )

    updated_changeset =
      Ecto.Changeset.put_assoc(changeset, :gallery_objects, sequence(slimmed_gallery_objects))

    form_id = "gallery_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, assign(socket, gallery_objects: new_gallery_objects, selected_images: selected_objects)}
  end

  def handle_event("edit_image", %{"id" => _id}, socket) do
    {:noreply, socket}
  end
end
