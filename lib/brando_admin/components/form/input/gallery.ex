defmodule BrandoAdmin.Components.Form.Input.Gallery do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Brando.Utils, only: [loaded_assoc?: 2]
  import Ecto.Changeset

  alias Brando.Utils
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Gallery.ImageConfig
  alias BrandoAdmin.Components.Form.Input.Gallery.Media
  alias BrandoAdmin.Components.Form.Input.Gallery.Thumb
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
    gallery = get_field(changeset, field.field)

    slimmed_objects =
      gallery.gallery_objects
      |> Enum.with_index()
      |> Enum.map(fn {obj, i} ->
        obj_map = Brando.Galleries.slim_gallery_object(obj)
        if i == index, do: Map.put(obj_map, :config, config), else: obj_map
      end)

    new_gallery = %{config_target: gallery.config_target, gallery_objects: slimmed_objects}

    updated_gallery_objects =
      gallery_objects
      |> Enum.with_index()
      |> Enum.map(fn {obj, i} ->
        if i == index, do: Map.put(obj, :config, config), else: obj
      end)

    update_form_changeset(socket, new_gallery)

    {:ok,
     socket
     |> assign(:gallery_objects, updated_gallery_objects)
     |> assign(:config_modal, nil)}
  end

  def update(%{event: "close_config_modal"}, socket) do
    {:ok, assign(socket, :config_modal, nil)}
  end

  # Upload delivery writes this list directly AND updates the entry changeset,
  # which reaches this component again through `assign_value/1` — two writers,
  # one event, no guaranteed ordering. Appending unconditionally duplicated the
  # object whenever this clause ran second.
  def update(
        %{new_image: new_image, selected_images: selected_images},
        %{assigns: %{gallery_objects: gallery_objects}} = socket
      ) do
    {:ok,
     socket
     |> assign(:gallery_objects, Brando.Galleries.append_unique_media(gallery_objects, new_image))
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
     |> assign(:gallery_objects, Brando.Galleries.append_unique_media(gallery_objects, new_video))
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

    gallery_objects =
      gallery
      |> get_gallery_objects()
      |> Brando.Galleries.merge_loaded_media(socket.assigns[:gallery_objects] || [])

    socket
    |> assign(:gallery, gallery)
    |> assign(:gallery_objects, gallery_objects)
    |> assign(:selected_images, Media.selected_ids(gallery_objects, :image_id))
    |> assign(:selected_videos, Media.selected_ids(gallery_objects, :video_id))
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
    gallery_object = Thumb.find(assigns)

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

  # Grid layout — the shared thumbnail, which the Gallery blueprint's own
  # editor renders too (`Gallery.Thumb`). The list layout above is this
  # component's alone, so it stays here.
  def gallery_object(assigns) do
    ~H"""
    <Thumb.thumb
      gallery_objects={@gallery_objects}
      gallery_object_field={@gallery_object_field}
      form_name={@parent_form_name}
    />
    """
  end

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

    send_update(BrandoAdmin.Components.Form,
      id: entry_form_id(socket),
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
    if Media.selected?(socket.assigns.selected_images, id) do
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
    if Media.selected?(socket.assigns.selected_videos, id) do
      {:noreply, remove_gallery_media(socket, :video, id)}
    else
      {:noreply, add_gallery_media(socket, :video, id)}
    end
  end

  def handle_event("edit_image", %{"id" => _id}, socket) do
    {:noreply, socket}
  end

  defp add_gallery_media(socket, media_type, media_id, opts \\ []) do
    %{gallery_objects: gallery_objects, current_user: current_user} = socket.assigns

    {updated, selected_ids} = Media.add(gallery_objects, media_type, media_id, current_user)

    if Keyword.get(opts, :notify_picker, true), do: Media.notify_picker(media_type, selected_ids)

    commit_gallery(socket, updated, media_type, selected_ids)
  end

  defp remove_gallery_media(socket, media_type, media_id) do
    %{gallery_objects: gallery_objects} = socket.assigns

    {updated, selected_ids} = Media.remove(gallery_objects, media_type, media_id)
    Media.notify_picker(media_type, selected_ids)

    commit_gallery(socket, updated, media_type, selected_ids)
  end

  # The gallery may not exist yet — the first pick creates it, which is why the
  # config target is derived from the owning schema rather than read off it.
  defp commit_gallery(socket, gallery_objects, media_type, selected_ids) do
    %{field: field} = socket.assigns
    gallery = Ecto.Changeset.get_field(field.form.source, field.field)

    update_form_changeset(socket, %{
      config_target:
        (gallery && gallery.config_target) ||
          Brando.Assets.ConfigTarget.serialize({"gallery", field.form.data.__struct__, field.field}),
      gallery_objects: Media.slim(gallery_objects)
    })

    assign(socket, [
      {:gallery_objects, gallery_objects},
      {Media.selection_key(media_type), selected_ids}
    ])
  end

  # `changeset` here belongs to whatever schema OWNS the gallery field, which
  # for a nested gallery is a subform record, not the entry — so neither the
  # entry form's id nor a replacement entry changeset can be derived from it.
  # Ship the gallery and its path instead and let the entry form write it in
  # (`Form.update(%{action: :put_gallery, ...})`), exactly as uploads do.
  defp update_form_changeset(socket, new_gallery) do
    %{field: field, path: path} = socket.assigns

    send_update(BrandoAdmin.Components.Form,
      id: entry_form_id(socket),
      action: :put_gallery,
      path: path,
      key: field.field,
      gallery: new_gallery
    )
  end

  # `Form.input/1` threads the entry form component's own id down as `@form_id`
  # (`form.ex`, `form_id={@id}`), so it is authoritative — no derivation needed.
  #
  # The fallback covers a gallery rendered outside that pipeline. It reads the
  # ROOT segment of the form name ("page[items][0]" -> "page"), which is the
  # entry's, and never the owning schema's — deriving from
  # `changeset.data.__struct__` named `"<subrecord singular>_form"`, a component
  # that is not mounted, which is how nested picker selections vanished.
  defp entry_form_id(%{assigns: %{form_id: form_id}}) when is_binary(form_id), do: form_id

  defp entry_form_id(%{assigns: %{field: field}}) do
    root = field.form.name |> String.split("[", parts: 2) |> hd()
    "#{root}_form"
  end
end
