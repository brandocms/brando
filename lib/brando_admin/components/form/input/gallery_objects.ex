defmodule BrandoAdmin.Components.Form.Input.GalleryObjects do
  @moduledoc """
  Custom `inputs_for` component for managing gallery objects directly
  on the Gallery schema's form. Supports adding images via ImagePicker,
  drag-and-drop reordering, and removal.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Gallery.Media
  alias BrandoAdmin.Components.Form.Input.Gallery.Thumb
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.VideoPicker

  def update(%{event: "upload_complete", asset: asset}, socket) do
    type = if is_struct(asset, Brando.Images.Image), do: :image, else: :video
    {:ok, add_gallery_media(socket, type, asset.id)}
  end

  def update(%{event: "image_processed", image: image}, socket) do
    update(%{action: :update_image, updated_image: image, force_validation: true}, socket)
  end

  def update(%{event: "video_created_from_url", video_data: %{id: id}}, socket) do
    {:ok, add_gallery_media(socket, :video, id)}
  end

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
    config_target = Brando.Assets.ConfigTarget.serialize(Ecto.Changeset.get_field(changeset, :config_target) || "default")
    {video_config, _} = Brando.Uploads.resolve_video_config(config_target)

    gallery_objects =
      changeset
      |> Ecto.Changeset.get_field(:gallery_objects)
      |> List.wrap()
      |> Brando.Galleries.merge_loaded_media(socket.assigns[:gallery_objects] || [])
      |> Media.load_missing()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:config_target, config_target)
     |> assign(:video_upload_enabled?, Brando.Uploads.video_upload_available?(video_config))
     |> assign(:gallery_objects, gallery_objects)
     |> assign(:selected_images, Media.selected_ids(gallery_objects, :image_id))
     |> assign(:selected_videos, Media.selected_ids(gallery_objects, :video_id))}
  end

  def render(assigns) do
    ~H"""
    <fieldset>
      <Primitives.field_base field={@field} label={@label} instructions={@instructions} class="subform">
        <div
          id={"#{@id}-upload"}
          class="gallery-input media-gallery"
          phx-hook="Brando.UploadTrigger"
          data-kind="resource_gallery"
          data-component-id={@id}
          data-asset-type="image"
          data-config-target={@config_target}
          data-video-config-target={@config_target}
          data-folder-browser="true"
          data-click-mode="trigger"
          data-upload-label={@label || gettext("Gallery")}
          data-allowed-types={if @video_upload_enabled?, do: "image,video", else: "image"}
          data-accept={if @video_upload_enabled?, do: "image/*,video/*", else: "image/*"}
        >
          <input type="file" class="file-input" multiple />
          <div id={"#{@id}-progress"} class="media-field-progress" phx-update="ignore" role="status" aria-live="polite"></div>
          <div class="media-field-drop" aria-hidden="true">{gettext("Drop to add to this gallery")}</div>
          <div class="actions">
            <button type="button" class="media-button primary upload-trigger">{gettext("Upload media")}</button>
            <button
              phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
              type="button"
              class="media-button"
            >
              {gettext("Browse images")}
            </button>
            <button
              phx-click={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
              type="button"
              class="media-button"
            >
              {gettext("Browse videos")}
            </button>
          </div>

          <%= if @gallery_objects == [] do %>
            <div class="media-gallery-empty">
              {if @video_upload_enabled?, do: gettext("Drop images or videos to add"), else: gettext("Drop images to add")}
            </div>
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
                  data-id={Thumb.media_id(gallery_object)}
                >
                  <Thumb.thumb
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
      </Primitives.field_base>
    </fieldset>
    """
  end

  def handle_event("reposition", _, socket) do
    {:noreply, socket}
  end

  def handle_event("set_target", _, socket) do
    send_update(ImagePicker,
      id: "image-picker",
      config_target: socket.assigns.config_target,
      event_target: socket.assigns.myself,
      multi: true,
      selected_images: socket.assigns.selected_images
    )

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id}, socket) do
    if Media.selected?(socket.assigns.selected_images, id) do
      {:noreply, remove_gallery_media(socket, :image, id)}
    else
      {:noreply, add_gallery_media(socket, :image, id)}
    end
  end

  def handle_event("open_video_picker", _, socket) do
    send_update(VideoPicker,
      id: "video-picker",
      config_target: socket.assigns.config_target,
      event_target: socket.assigns.myself,
      multi: true,
      selected_videos: socket.assigns.selected_videos
    )

    {:noreply, socket}
  end

  def handle_event("select_video", %{"id" => id}, socket) do
    if Media.selected?(socket.assigns.selected_videos, id) do
      {:noreply, remove_gallery_media(socket, :video, id)}
    else
      {:noreply, add_gallery_media(socket, :video, id)}
    end
  end

  def handle_event("edit_image", %{"id" => _id}, socket) do
    {:noreply, socket}
  end

  defp add_gallery_media(socket, media_type, media_id) do
    %{gallery_objects: gallery_objects, current_user: current_user} = socket.assigns

    {updated, selected_ids} = Media.add(gallery_objects, media_type, media_id, current_user)
    Media.notify_picker(media_type, selected_ids)

    commit_gallery_objects(socket, updated, media_type, selected_ids)
  end

  defp remove_gallery_media(socket, media_type, media_id) do
    {updated, selected_ids} = Media.remove(socket.assigns.gallery_objects, media_type, media_id)
    Media.notify_picker(media_type, selected_ids)

    commit_gallery_objects(socket, updated, media_type, selected_ids)
  end

  # Unlike `Input.Gallery`, the changeset this component edits IS the entry
  # changeset (see `update_gallery_form/2`), so the objects go straight onto it.
  defp commit_gallery_objects(socket, gallery_objects, media_type, selected_ids) do
    field = socket.assigns.field

    field.form.source
    |> Ecto.Changeset.put_assoc(:gallery_objects, Media.slim(gallery_objects))
    |> then(&update_gallery_form(field, &1))

    assign(socket, [
      {:gallery_objects, gallery_objects},
      {Media.selection_key(media_type), selected_ids}
    ])
  end

  defp update_gallery_form(field, updated_changeset) do
    root = field.form.name |> String.split("[", parts: 2) |> hd()

    send_update(BrandoAdmin.Components.Form,
      id: "#{root}_form",
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )
  end
end
