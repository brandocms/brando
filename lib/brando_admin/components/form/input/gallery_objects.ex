defmodule BrandoAdmin.Components.Form.Input.GalleryObjects do
  @moduledoc """
  Custom `inputs_for` component for managing gallery objects directly
  on the Gallery schema's form. Supports adding images via ImagePicker,
  drag-and-drop reordering, and removal.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Brando.Utils, only: [loaded_assoc?: 2]

  alias Brando.Galleries.GalleryObject
  alias Brando.Utils
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.VideoPicker

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
     |> assign_new(:selected_images, fn ->
       gallery_objects |> Enum.filter(&Map.get(&1, :image_id)) |> Enum.map(&Map.get(&1, :image_id))
     end)
     |> assign_new(:selected_videos, fn ->
       gallery_objects |> Enum.filter(&Map.get(&1, :video_id)) |> Enum.map(&Map.get(&1, :video_id))
     end)}
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
            <button
              phx-click={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
              type="button"
              class="tiny"
            >
              {gettext("Select videos")}
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
                <figure
                  class="gallery-object sort-handle draggable"
                  data-id={gallery_object[:image_id].value || gallery_object[:video_id].value}
                >
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
                <Input.input type={:hidden} field={gallery_object[:video_id]} />
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
    image_id = assigns.gallery_object_field[:image_id].value
    video_id = assigns.gallery_object_field[:video_id].value

    gallery_object =
      Enum.find(assigns.gallery_objects, fn obj ->
        (image_id && to_string(Map.get(obj, :image_id)) == to_string(image_id)) ||
          (video_id && to_string(Map.get(obj, :video_id)) == to_string(video_id))
      end)

    assigns = assign(assigns, :gallery_object, gallery_object)

    ~H"""
    <div :if={@gallery_object}>
      <%= if Map.get(@gallery_object, :image_id) && loaded_assoc?(@gallery_object, :image) do %>
        <%= if @gallery_object.image.status == :processed do %>
          <img
            width="25"
            height="25"
            src={"#{Utils.img_url(@gallery_object.image, :thumb, prefix: Utils.media_url())}"}
          />
        <% else %>
          <div class="img-placeholder">
            <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
              <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
            </svg>
          </div>
        <% end %>
      <% else %>
        <% thumb_url =
          if(loaded_assoc?(@gallery_object, :video), do: Brando.Videos.Helpers.thumbnail_url(@gallery_object.video)) %>
        <%= if thumb_url do %>
          <img width="25" height="25" src={thumb_url} />
        <% else %>
          <div class="img-placeholder">
            <.icon name="hero-video-camera" />
          </div>
        <% end %>
      <% end %>
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

  def handle_event("select_image", %{"id" => id}, socket) do
    image_id = if is_binary(id), do: String.to_integer(id), else: id

    if image_id in socket.assigns.selected_images do
      {:noreply, remove_gallery_media(socket, :image, id)}
    else
      {:noreply, add_gallery_media(socket, :image, id)}
    end
  end

  def handle_event("open_video_picker", _, socket) do
    send_update(VideoPicker,
      id: "video-picker",
      config_target: nil,
      event_target: socket.assigns.myself,
      multi: true,
      selected_videos: socket.assigns.selected_videos
    )

    {:noreply, socket}
  end

  def handle_event("select_video", %{"id" => id}, socket) do
    video_id = if is_binary(id), do: String.to_integer(id), else: id

    if video_id in socket.assigns.selected_videos do
      {:noreply, remove_gallery_media(socket, :video, id)}
    else
      {:noreply, add_gallery_media(socket, :video, id)}
    end
  end

  def handle_event("edit_image", %{"id" => _id}, socket) do
    {:noreply, socket}
  end

  defp add_gallery_media(socket, media_type, media_id_str) do
    %{field: field, gallery_objects: gallery_objects, current_user: current_user} = socket.assigns

    changeset = field.form.source
    {:ok, media} = fetch_media(media_type, media_id_str)
    media_id = String.to_integer(media_id_str)
    id_field = media_id_field(media_type)
    assoc_field = media_assoc_field(media_type)

    current_gallery_objects =
      Enum.map(
        gallery_objects,
        &Brando.Galleries.slim_gallery_object/1
      )

    new_gallery_object_slim = %{id_field => media_id, creator_id: current_user.id}
    slimmed_objects = current_gallery_objects ++ [new_gallery_object_slim]

    updated_changeset =
      Ecto.Changeset.put_assoc(changeset, :gallery_objects, sequence(slimmed_objects))

    new_gallery_object = %GalleryObject{creator_id: current_user.id}
    new_gallery_object = Map.put(new_gallery_object, id_field, media.id)
    new_gallery_object = Map.put(new_gallery_object, assoc_field, media)
    updated_gallery_objects = gallery_objects ++ [new_gallery_object]

    selected_ids = extract_selected_ids(updated_gallery_objects, id_field)
    notify_picker(media_type, selected_ids)
    update_gallery_form(updated_changeset)

    selection_assign = selection_assign_key(media_type)
    assign(socket, [{:gallery_objects, updated_gallery_objects}, {selection_assign, selected_ids}])
  end

  defp remove_gallery_media(socket, media_type, media_id_str) do
    %{field: field, gallery_objects: gallery_objects} = socket.assigns

    changeset = field.form.source
    id_field = media_id_field(media_type)
    media_id = parse_id(media_id_str)

    updated_gallery_objects = Enum.filter(gallery_objects, &(Map.get(&1, id_field) != media_id))
    selected_ids = extract_selected_ids(updated_gallery_objects, id_field)
    notify_picker(media_type, selected_ids)

    slimmed_objects =
      Enum.map(
        updated_gallery_objects,
        &Brando.Galleries.slim_gallery_object/1
      )

    updated_changeset =
      Ecto.Changeset.put_assoc(changeset, :gallery_objects, sequence(slimmed_objects))

    update_gallery_form(updated_changeset)

    selection_assign = selection_assign_key(media_type)
    assign(socket, [{:gallery_objects, updated_gallery_objects}, {selection_assign, selected_ids}])
  end

  defp fetch_media(:image, id), do: Brando.Images.get_image(id)
  defp fetch_media(:video, id), do: Brando.Videos.get_video(%{matches: %{id: id}, preload: [:thumbnail]})

  defp media_id_field(:image), do: :image_id
  defp media_id_field(:video), do: :video_id

  defp media_assoc_field(:image), do: :image
  defp media_assoc_field(:video), do: :video

  defp selection_assign_key(:image), do: :selected_images
  defp selection_assign_key(:video), do: :selected_videos

  defp extract_selected_ids(gallery_objects, id_field) do
    gallery_objects
    |> Enum.filter(&Map.get(&1, id_field))
    |> Enum.map(&Map.get(&1, id_field))
  end

  defp notify_picker(:image, selected_ids) do
    send_update(ImagePicker, id: "image-picker", selected_images: selected_ids)
  end

  defp notify_picker(:video, selected_ids) do
    send_update(VideoPicker, id: "video-picker", selected_videos: selected_ids)
  end

  defp update_gallery_form(updated_changeset) do
    send_update(BrandoAdmin.Components.Form,
      id: "gallery_form",
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )
  end

  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
  defp parse_id(id), do: id
end
