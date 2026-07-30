defmodule BrandoAdmin.Components.Form.Input.Gallery do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Brando.Utils, only: [loaded_assoc?: 2]
  import Ecto.Changeset

  alias Brando.Galleries.GalleryObject
  alias Brando.Utils
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Gallery.ImageConfig
  alias BrandoAdmin.Components.Form.Input.Gallery.VideoConfig
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.VideoPicker

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean

  # data gallery, :any
  # data preview_layout, :atom
  # data selected_images, :list

  def update(%{event: "update_object_config", gallery_object_index: index, config: config}, socket) do
    %{field: field, gallery_objects: gallery_objects} = socket.assigns

    changeset = field.form.source
    field_name = field.field
    gallery = get_field(changeset, field_name)

    slimmed_objects =
      gallery.gallery_objects
      |> Enum.with_index()
      |> Enum.map(fn {obj, i} ->
        obj_map = Brando.Galleries.slim_gallery_object(obj)
        if i == index, do: Map.put(obj_map, :config, config), else: obj_map
      end)

    new_gallery = %{
      id: gallery.id,
      config_target: gallery.config_target,
      gallery_objects: slimmed_objects
    }

    updated_gallery_objects =
      gallery_objects
      |> Enum.with_index()
      |> Enum.map(fn {obj, i} ->
        if i == index, do: Map.put(obj, :config, config), else: obj
      end)

    update_form_changeset(changeset, field_name, new_gallery)

    {:ok,
     socket
     |> assign(:gallery_objects, updated_gallery_objects)
     |> assign(:config_modal, nil)}
  end

  def update(%{event: "close_config_modal"}, socket) do
    {:ok, assign(socket, :config_modal, nil)}
  end

  def update(
        %{new_image: new_image, selected_images: selected_images},
        %{assigns: %{gallery_objects: gallery_objects}} = socket
      ) do
    {:ok,
     socket
     |> assign(:gallery_objects, gallery_objects ++ [new_image])
     |> assign(:selected_images, selected_images)}
  end

  def update(
        %{action: :update_image, updated_image: updated_image, force_validation: true},
        %{assigns: %{gallery_objects: gallery_objects}} = socket
      ) do
    updated_image_id = updated_image.id

    updated_gallery_objects =
      Enum.map(gallery_objects, fn
        %{image_id: ^updated_image_id} = obj -> Map.put(obj, :image, updated_image)
        other -> other
      end)

    {:ok, assign(socket, :gallery_objects, updated_gallery_objects)}
  end

  def update(%{event: "video_created_from_url", video_data: %{id: video_id}}, socket) do
    # Skip notify_picker since the VideoPicker already knows about this video
    {:ok, add_gallery_media(socket, :video, to_string(video_id), notify_picker: false)}
  end

  def update(
        %{new_video: new_video, selected_videos: selected_videos},
        %{assigns: %{gallery_objects: gallery_objects}} = socket
      ) do
    {:ok,
     socket
     |> assign(:gallery_objects, gallery_objects ++ [new_video])
     |> assign(:selected_videos, selected_videos)}
  end

  def update(assigns, socket) do
    schema = assigns.field.form.data.__struct__
    path = Brando.Utils.get_path_from_field_name(assigns.field.form.name)
    config_target = Brando.Assets.ConfigTarget.serialize({"gallery", schema, assigns.field.field})
    {video_config, _resolved_target} = Brando.Uploads.resolve_video_config(config_target)

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(:preview_layout, assigns.opts[:layout] || :grid)
     |> assign(:schema, schema)
     |> assign(:path, path)
     |> assign(:config_target, config_target)
     |> assign_new(:config_modal, fn -> nil end)
     |> assign(:video_upload_enabled?, Brando.Uploads.video_upload_available?(video_config))
     |> assign_value()}
  end

  defp get_gallery_objects(%{gallery_objects: nil}), do: []
  defp get_gallery_objects(%{gallery_objects: []}), do: []
  defp get_gallery_objects(%{gallery_objects: %Ecto.Association.NotLoaded{}}), do: []
  defp get_gallery_objects(%{gallery_objects: gallery_objects}), do: gallery_objects
  defp get_gallery_objects(_), do: []

  defp assign_value(%{assigns: %{field: field}} = socket) do
    changeset = field.form.source
    gallery = Ecto.Changeset.get_field(changeset, field.field)
    gallery_objects = get_gallery_objects(gallery)

    socket
    |> assign(:gallery, gallery)
    |> assign_new(:selected_images, fn ->
      gallery_objects |> Enum.filter(&Map.get(&1, :image_id)) |> Enum.map(&Map.get(&1, :image_id))
    end)
    |> assign_new(:selected_videos, fn ->
      gallery_objects |> Enum.filter(&Map.get(&1, :video_id)) |> Enum.map(&Map.get(&1, :video_id))
    end)
    |> assign_new(:gallery_objects, fn -> gallery_objects end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base field={@field} label={@label} instructions={@instructions} class={@class} compact={@compact}>
        <div class="asset-field gallery-input">
          <div
            id={"#{@field.id}-gallery-upload-trigger"}
            class={["gallery-upload-wrapper", @gallery_objects == [] && "asset-field--single"]}
            phx-hook="Brando.UploadTrigger"
            data-kind="entry_field_gallery"
            data-component-id={@id}
            data-asset-type="image"
            data-field={@field.field}
            data-path={Jason.encode!(@path)}
            data-config-target={@config_target}
            data-folder-browser="true"
            data-click-mode="trigger"
            data-accept=".jpg,.jpeg,.png,.gif,.webp,.svg"
          >
            <input type="file" class="file-input" multiple />

            <%= if @gallery_objects == [] do %>
              <div class="img-placeholder">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z" />
                </svg>
              </div>
              <div class="gallery-info">
                <span>{gettext("No associated gallery")}</span>
                <.gallery_actions
                  field={@field}
                  id={@id}
                  path={@path}
                  config_target={@config_target}
                  video_upload_enabled?={@video_upload_enabled?}
                  myself={@myself}
                />
              </div>
            <% else %>
              <.gallery_actions
                field={@field}
                id={@id}
                path={@path}
                config_target={@config_target}
                video_upload_enabled?={@video_upload_enabled?}
                myself={@myself}
              />
            <% end %>
          </div>

          <%= if @gallery_objects != [] do %>
            <div
              id={"#{@field.id}-sortable-gallery-objects"}
              phx-hook="Brando.SortableAssocs"
              data-target={@myself}
              data-sortable-id={"#{@field.id}-sortable-gallery"}
              data-sortable-handle=".sort-handle"
              data-sortable-selector=".gallery-object"
              class={"gallery-objects gallery-objects--#{@preview_layout}"}
            >
              <.inputs_for :let={gallery_form} field={@field}>
                <Input.input type={:hidden} field={gallery_form[:config_target]} />

                <.inputs_for :let={gallery_object} field={gallery_form[:gallery_objects]}>
                  <figure
                    class="gallery-object sort-handle draggable"
                    data-id={gallery_object[:image_id].value || gallery_object[:video_id].value}
                  >
                    <.gallery_object
                      gallery_objects={@gallery_objects}
                      gallery_object_field={gallery_object}
                      parent_form_name={gallery_form.name}
                      preview_layout={@preview_layout}
                      myself={@myself}
                    />
                    <input
                      type="hidden"
                      name={"#{gallery_form.name}[sort_gallery_object_ids][]"}
                      value={gallery_object.index}
                    />
                  </figure>
                  <Input.input type={:hidden} field={gallery_object[:image_id]} />
                  <Input.input type={:hidden} field={gallery_object[:video_id]} />
                  <Input.input type={:hidden} field={gallery_object[:gallery_id]} />
                  <.config_hidden_fields field={gallery_object[:config]} />
                </.inputs_for>
              </.inputs_for>
            </div>
          <% end %>

          <Content.modal
            id="gallery-object-config-modal"
            title={
              if(@config_modal && @config_modal.type == :video,
                do: gettext("Video configuration"),
                else: gettext("Image configuration")
              )
            }
            narrow
            close={hide_modal("#gallery-object-config-modal") |> JS.push("close_config_modal", target: @myself)}
          >
            <%= if @config_modal do %>
              <%= case @config_modal.type do %>
                <% :image -> %>
                  <.live_component
                    module={ImageConfig}
                    id={"gallery-image-config-#{@config_modal.index}"}
                    image={@config_modal.media}
                    config={@config_modal.config}
                    gallery_object_index={@config_modal.index}
                    gallery_component={__MODULE__}
                    gallery_component_id={@id}
                  />
                <% :video -> %>
                  <.live_component
                    module={VideoConfig}
                    id={"gallery-video-config-#{@config_modal.index}"}
                    video={@config_modal.media}
                    config={@config_modal.config}
                    gallery_object_index={@config_modal.index}
                    gallery_component={__MODULE__}
                    gallery_component_id={@id}
                  />
              <% end %>
            <% end %>
          </Content.modal>
        </div>
      </Form.field_base>
    </div>
    """
  end

  attr :field, :any, required: true
  attr :id, :any, required: true
  attr :path, :any, required: true
  attr :config_target, :any, required: true
  attr :video_upload_enabled?, :boolean, required: true
  attr :myself, :any, required: true

  defp gallery_actions(assigns) do
    ~H"""
    <div class="actions">
      <div class="segmented-buttons">
        <button type="button" class="tiny upload-trigger">
          {gettext("Upload images")}
        </button>
        <div
          :if={@video_upload_enabled?}
          id={"#{@field.id}-gallery-video-upload-trigger"}
          phx-hook="Brando.UploadTrigger"
          data-kind="entry_field_gallery"
          data-component-id={@id}
          data-asset-type="video"
          data-field={@field.field}
          data-path={Jason.encode!(@path)}
          data-config-target={@config_target}
          data-click-mode="trigger"
          data-accept=".mp4,.webm,.mov,.avi,.ogv"
        >
          <button type="button" class="tiny upload-trigger">
            {gettext("Upload videos")}
          </button>
          <input type="file" class="file-input" multiple />
        </div>
      </div>
      <div class="segmented-buttons">
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
    </div>
    """
  end

  attr :field, :any, required: true

  defp config_hidden_fields(assigns) do
    config = assigns.field.value || %{}
    assigns = assign(assigns, :config, config)

    ~H"""
    <%= for {key, value} <- @config do %>
      <input type="hidden" name={"#{@field.name}[#{key}]"} value={to_string(value)} />
    <% end %>
    """
  end

  def gallery_object(%{preview_layout: :list} = assigns) do
    gallery_object = find_gallery_object(assigns)

    assigns =
      assigns
      |> assign(:gallery_object, gallery_object)
      |> assign_list_object_data(gallery_object)

    ~H"""
    <div :if={@gallery_object} class="gallery-object-list-row">
      <div class="gallery-object-list-thumb">
        <%= if @thumb_url do %>
          <img src={@thumb_url} />
        <% else %>
          <div class="img-placeholder">
            <.icon name={if @media_type == :video, do: "hero-video-camera", else: "hero-photo"} />
          </div>
        <% end %>
      </div>
      <div class="gallery-object-list-info">
        <div class="gallery-object-list-name">
          <div class="gallery-object-list-filename">{@display_filename}</div>
          <div :if={@display_dir} class="gallery-object-list-dir">{@display_dir}</div>
        </div>
        <div class="gallery-object-list-detail">
          <span :if={@display_title} class="gallery-object-list-title">{@display_title}</span>
          <%= if @display_alt do %>
            <span class="gallery-object-list-alt" title={@display_alt}>
              <.icon name="hero-chat-bubble-bottom-center-text-mini" /> {truncate_text(@display_alt, 40)}
            </span>
          <% else %>
            <span :if={@media_type == :image} class="gallery-object-list-alt missing">
              <.icon name="hero-chat-bubble-bottom-center-text-mini" /> {gettext("No alt text")}
            </span>
          <% end %>
        </div>
        <div class="gallery-object-list-meta">{@display_dimensions}</div>
        <div class="gallery-object-list-meta">{@display_formats}</div>
        <div class={"gallery-object-list-status gallery-object-list-status--#{@display_status_key}"}>{@display_status}</div>
        <div class="gallery-object-list-actions" data-sortable-filter>
          <button
            type="button"
            class="gallery-object-action-button"
            aria-label={gettext("Actions")}
            phx-click={toggle_dropdown("##{@menu_id}")}
            phx-click-away={hide_dropdown("##{@menu_id}")}
          >
            <.icon name="hero-ellipsis-horizontal-circle" />
          </button>
          <ul id={@menu_id} class="gallery-object-action-dropdown hidden">
            <li :if={@media_type == :image}>
              <button
                type="button"
                phx-click={
                  JS.push("open_image_editor", target: @myself, value: %{image_id: @gallery_object.image_id})
                  |> hide_dropdown("##{@menu_id}")
                  |> toggle_drawer("#image-editor-drawer")
                }
              >
                <.icon name="hero-pencil-square" />
                {gettext("Edit image")}
              </button>
            </li>
            <li>
              <button
                type="button"
                phx-click={
                  JS.push("open_config_modal",
                    target: @myself,
                    value: %{index: @gallery_object_field.index}
                  )
                  |> hide_dropdown("##{@menu_id}")
                  |> show_modal("#gallery-object-config-modal")
                }
              >
                <.icon name="hero-cog-6-tooth" />
                {gettext("Configure")}
              </button>
            </li>
            <li>
              <button
                type="button"
                class="delete-action"
                name={"#{@parent_form_name}[drop_gallery_object_ids][]"}
                value={@gallery_object_field.index}
                phx-click={JS.dispatch("change")}
              >
                <.icon name="hero-trash" />
                {gettext("Remove from gallery")}
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  def gallery_object(assigns) do
    gallery_object = find_gallery_object(assigns)
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
        name={"#{@parent_form_name}[drop_gallery_object_ids][]"}
        value={@gallery_object_field.index}
        data-sortable-filter
        phx-click={JS.dispatch("change")}
      >
        <.icon name="hero-x-mark" />
      </button>
    </div>
    """
  end

  defp find_gallery_object(assigns) do
    image_id = assigns.gallery_object_field[:image_id].value
    video_id = assigns.gallery_object_field[:video_id].value

    Enum.find(assigns.gallery_objects, fn obj ->
      (present?(image_id) && to_string(Map.get(obj, :image_id)) == to_string(image_id)) ||
        (present?(video_id) && to_string(Map.get(obj, :video_id)) == to_string(video_id))
    end)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp assign_list_object_data(assigns, nil), do: assigns

  defp assign_list_object_data(assigns, obj) when is_map_key(obj, :image_id) and not is_nil(obj.image_id) do
    if loaded_assoc?(obj, :image) do
      image = obj.image

      assigns
      |> assign(:media_type, :image)
      |> assign(:menu_id, "gallery-obj-menu-img-#{image.id}")
      |> assign(:thumb_url, thumb_url_for_image(image))
      |> assign(:display_filename, Path.basename(image.path))
      |> assign(:display_dir, Path.dirname(image.path))
      |> assign(:display_title, image.title)
      |> assign(:display_alt, image.alt)
      |> assign(:display_dimensions, "#{image.width}\u00d7#{image.height}")
      |> assign(:display_formats, format_image_formats(image.formats))
      |> assign(:display_status, format_status(image.status))
      |> assign(:display_status_key, image.status)
    else
      assign_list_object_defaults(assigns, :image, obj.image_id)
    end
  end

  defp assign_list_object_data(assigns, obj) do
    if Map.get(obj, :video_id) && loaded_assoc?(obj, :video) do
      video = obj.video

      assigns
      |> assign(:media_type, :video)
      |> assign(:menu_id, "gallery-obj-menu-vid-#{video.id}")
      |> assign(:thumb_url, Brando.Videos.Helpers.thumbnail_url(video))
      |> assign(:display_filename, video.title || video.remote_id || "-")
      |> assign(:display_dir, video.source_url)
      |> assign(:display_title, nil)
      |> assign(:display_alt, nil)
      |> assign(:display_dimensions, gettext("Video"))
      |> assign(:display_formats, "")
      |> assign(:display_status, format_status(video.status))
      |> assign(:display_status_key, video.status)
    else
      assign_list_object_defaults(assigns, :video, Map.get(obj, :video_id))
    end
  end

  defp assign_list_object_defaults(assigns, type, id) do
    assigns
    |> assign(:media_type, type)
    |> assign(:menu_id, "gallery-obj-menu-#{type}-#{id}")
    |> assign(:thumb_url, nil)
    |> assign(:display_filename, "-")
    |> assign(:display_dir, nil)
    |> assign(:display_title, nil)
    |> assign(:display_alt, nil)
    |> assign(:display_dimensions, "-")
    |> assign(:display_formats, "")
    |> assign(:display_status, "-")
    |> assign(:display_status_key, :unknown)
  end

  defp thumb_url_for_image(%{status: :processed} = image) do
    Utils.img_url(image, :thumb, prefix: Utils.media_url())
  end

  defp thumb_url_for_image(_image), do: nil

  defp format_image_formats(formats) when is_list(formats) do
    formats
    |> Enum.reject(&(&1 == :original))
    |> Enum.map_join(", ", &to_string/1)
    |> case do
      "" -> "-"
      str -> str
    end
  end

  defp format_image_formats(_), do: "-"

  defp format_status(status) when is_atom(status) do
    status |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp format_status(status) when is_binary(status), do: status
  defp format_status(_), do: "-"

  defp truncate_text(text, max_length) when byte_size(text) > max_length do
    String.slice(text, 0, max_length) <> "..."
  end

  defp truncate_text(text, _max_length), do: text

  defp build_crop_groups_for(image) do
    case Brando.Images.get_config_for(image) do
      {:ok, config} -> Form.build_crop_groups(config.sizes)
      _ -> []
    end
  end

  defp sequence(gallery_objects) do
    gallery_objects
    |> Enum.with_index()
    |> Enum.map(fn {gi, idx} -> Map.put(gi, :sequence, idx) end)
  end

  def handle_event("open_config_modal", %{"index" => index}, socket) do
    gallery_objects = socket.assigns.gallery_objects
    obj = Enum.at(gallery_objects, index)

    config_modal =
      cond do
        obj && Map.get(obj, :image_id) && loaded_assoc?(obj, :image) ->
          %{type: :image, media: obj.image, config: Map.get(obj, :config) || %{}, index: index}

        obj && Map.get(obj, :video_id) && loaded_assoc?(obj, :video) ->
          %{type: :video, media: obj.video, config: Map.get(obj, :config) || %{}, index: index}

        true ->
          nil
      end

    {:noreply, assign(socket, :config_modal, config_modal)}
  end

  def handle_event("close_config_modal", _, socket) do
    {:noreply, assign(socket, :config_modal, nil)}
  end

  def handle_event("open_image_editor", %{"image_id" => image_id}, socket) do
    {:ok, image} = Brando.Images.get_image(image_id)

    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :set_edit_image_from_block,
      image: image,
      block_target: {__MODULE__, socket.assigns.id},
      old_image_id: image.id
    )

    crop_groups = build_crop_groups_for(image)

    {:noreply,
     push_event(socket, "b:image_editor:init", %{
       image_src: Utils.img_url(image, :original, prefix: Utils.media_url()),
       image_width: image.width,
       image_height: image.height,
       image_id: image.id,
       crop_groups: crop_groups
     })}
  end

  def handle_event("reposition", _, socket) do
    {:noreply, socket}
  end

  def handle_event("set_target", _, socket) do
    myself = socket.assigns.myself
    selected_images = socket.assigns.selected_images
    schema = socket.assigns.schema
    field = socket.assigns.field
    field_name = field.field

    send_update(ImagePicker,
      id: "image-picker",
      config_target: Brando.Assets.ConfigTarget.serialize({"gallery", schema, field_name}),
      event_target: myself,
      multi: true,
      selected_images: selected_images
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
    {_video_config, video_config_target} =
      Brando.Uploads.resolve_video_config(socket.assigns.config_target)

    send_update(VideoPicker,
      id: "video-picker",
      config_target: video_config_target,
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

  def handle_event("delete_selected", %{"ids" => ids_json}, socket) do
    rejected_indices =
      ids_json
      |> Jason.decode!()
      |> MapSet.new()

    field_name = socket.assigns.input.name
    changeset = socket.assigns.field.form.source
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
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, assign(socket, :selected_images, [])}
  end

  defp add_gallery_media(socket, media_type, media_id_str, opts \\ []) do
    %{field: field, gallery_objects: gallery_objects, current_user: current_user} = socket.assigns

    changeset = field.form.source
    field_name = field.field
    schema = field.form.data.__struct__
    gallery = Ecto.Changeset.get_field(changeset, field_name)

    {:ok, media} = fetch_media(media_type, media_id_str)
    media_id = String.to_integer(media_id_str)
    id_field = media_id_field(media_type)
    assoc_field = media_assoc_field(media_type)

    current_gallery_objects =
      if gallery do
        Enum.map(
          gallery.gallery_objects || [],
          &Brando.Galleries.slim_gallery_object/1
        )
      else
        []
      end

    new_gallery_object_slim = %{id_field => media_id, creator_id: current_user.id}
    slimmed_objects = current_gallery_objects ++ [new_gallery_object_slim]

    new_gallery =
      if gallery do
        %{id: gallery.id, config_target: gallery.config_target, gallery_objects: sequence(slimmed_objects)}
      else
        %{
          config_target: Brando.Assets.ConfigTarget.serialize({"gallery", schema, field_name}),
          gallery_objects: sequence(slimmed_objects)
        }
      end

    new_gallery_object = %GalleryObject{creator_id: current_user.id}
    new_gallery_object = Map.put(new_gallery_object, id_field, media.id)
    new_gallery_object = Map.put(new_gallery_object, assoc_field, media)
    updated_gallery_objects = gallery_objects ++ [new_gallery_object]

    selected_ids = extract_selected_ids(updated_gallery_objects, id_field)
    if Keyword.get(opts, :notify_picker, true), do: notify_picker(media_type, selected_ids)
    update_form_changeset(changeset, field_name, new_gallery)

    selection_assign = selection_assign_key(media_type)
    assign(socket, [{:gallery_objects, updated_gallery_objects}, {selection_assign, selected_ids}])
  end

  defp remove_gallery_media(socket, media_type, media_id_str) do
    %{field: field, gallery_objects: gallery_objects} = socket.assigns

    changeset = field.form.source
    gallery = Ecto.Changeset.get_field(changeset, field.field)
    field_name = field.field
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

    new_gallery = %{
      id: gallery.id,
      config_target: gallery.config_target,
      gallery_objects: sequence(slimmed_objects)
    }

    update_form_changeset(changeset, field_name, new_gallery)

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

  defp update_form_changeset(changeset, field_name, new_gallery) do
    updated_changeset = put_assoc(changeset, field_name, new_gallery)
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )
  end

  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
  defp parse_id(id), do: id
end
