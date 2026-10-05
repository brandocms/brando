defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Brando.Utils, only: [loaded_assoc?: 2]

  alias Brando.Villain.Blocks.GalleryObjectOverride
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.Object
  alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog
  alias BrandoAdmin.Components.Form.Input.Gallery.Tile
  alias BrandoAdmin.Components.Form.Primitives
  alias Ecto.Changeset

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
  # data available_images, :list
  # data images, :list
  # data has_images?, :boolean
  # data image, :any
  # data selected_images_paths, :list
  # data display, :atom — the block's saved `display`, which the site's templates may read
  # data view, :atom — what the admin shows, :grid or :list. Starts at `display`
  #   and follows the view switch; never written to the block.
  # data text_editor, :map — the open caption/alt popover, `%{type, id, kind}`
  # data show_only_selected?, :boolean
  # data upload_formats, :string

  def mount(socket) do
    {:ok,
     assign(socket,
       available_images: [],
       show_only_selected?: false,
       form_id: nil,
       view: nil,
       text_editor: nil
     )}
  end

  def update(%{event: "image_processed", image: image}, socket) do
    # Keep the parent ref changeset in sync so live preview sees the processed image
    # without waiting for another block mutation (e.g. drag-and-drop reorder).
    Block.commit_ref_data(socket, replace_gallery_image: {image.id, image}, force_render: true)

    # Use locally tracked gallery_objects instead of re-reading from form.
    # After image_editor_new_copy, propagation may not have completed yet,
    # so the form changeset might still have the old image_id. But we update
    # @gallery_objects locally in image_editor_new_copy, so the new image_id
    # is already available here for matching.
    gallery_objects = socket.assigns[:gallery_objects] || []

    if Enum.any?(gallery_objects, &(&1.image_id == image.id)) do
      gallery_objects = Enum.map(gallery_objects, &put_processed_image(&1, image))

      {:ok,
       socket
       |> assign(:gallery_objects, gallery_objects)
       |> assign(:indexed_objects, Enum.with_index(gallery_objects))
       |> assign(:has_objects?, !Enum.empty?(gallery_objects))}
    else
      # The image isn't in our local list yet — processing finished before the
      # add's re-render reached this component (inline/fast queue). Do NOT
      # reassign the stale list (it would pin an outdated gallery over the
      # parent's incoming refresh); the Block-side replace above still ran.
      {:ok, socket}
    end
  end

  def update(%{event: "live_upload_complete", image_id: image_id}, socket) do
    socket
    |> Block.commit_ref_data(add_gallery_image_id: image_id)
    |> then(&{:ok, &1})
  end

  def update(%{event: "image_editor_new_copy", new_image: new_image, old_image_id: old_image_id}, socket) do
    new_block_data = Block.current_block_data_map(socket.assigns.block)

    # Update gallery_objects locally so image_processed can match on the new
    # image_id immediately, even before the propagation cascade completes.
    gallery_objects = socket.assigns[:gallery_objects] || []

    updated_gallery_objects =
      if old_image_id do
        Enum.map(gallery_objects, &replace_object_image(&1, old_image_id, new_image))
      else
        # Adding new image — append a temporary gallery object
        new_obj = %{image_id: new_image.id, image: new_image, video_id: nil, video: nil}
        gallery_objects ++ [new_obj]
      end

    gallery_action =
      if old_image_id do
        {:replace_gallery_image, {old_image_id, new_image}}
      else
        {:add_gallery_image_id, new_image.id}
      end

    socket
    |> Block.commit_ref_data([ref_data: new_block_data] ++ [gallery_action])
    |> assign(:gallery_objects, updated_gallery_objects)
    |> assign(:indexed_objects, Enum.with_index(updated_gallery_objects))
    |> assign(:has_objects?, !Enum.empty?(updated_gallery_objects))
    |> then(&{:ok, &1})
  end

  def update(%{event: "video_created_from_url", video_data: %{id: video_id}}, socket) do
    # Video was already created by VideoPicker — add it to gallery like select_video does
    socket
    |> Block.commit_ref_data(
      ref_data: Block.current_block_data_map(socket.assigns.block),
      add_gallery_video_id: video_id
    )
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    {gallery, gallery_objects} = get_gallery_and_objects(assigns)

    selected_ids =
      gallery_objects
      |> Enum.map(&selected_id/1)
      |> Enum.filter(& &1)

    block_data_cs = Block.get_block_data_changeset(assigns.block)
    upload_formats = upload_formats(Changeset.get_field(block_data_cs, :formats))

    # Recompute overrides from current gallery objects + current form state.
    # This keeps overrides in sync when objects are added/removed after mount.
    initialized_overrides = initialize_gallery_overrides(gallery_objects, block_data_cs)

    updated_block = update_block_with_overrides(assigns.block, initialized_overrides)
    updated_block_data_cs = Block.get_block_data_changeset(updated_block)
    gallery_config_target = gallery && Map.get(gallery, :config_target)

    uid = assigns.ref_form[:uid].value
    form_id = assigns[:form_id] || socket.assigns[:form_id] || BrandoAdmin.Utils.derive_form_id(assigns.ref_form.name)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:initialized_overrides, initialized_overrides)
     |> assign(:form_id, form_id)
     |> assign(:gallery, gallery)
     |> assign(:gallery_objects, gallery_objects)
     |> assign(:indexed_objects, Enum.with_index(gallery_objects))
     |> assign(:upload_formats, upload_formats)
     |> assign(:display, Changeset.get_field(block_data_cs, :display))
     |> assign(:view, socket.assigns[:view] || initial_view(Changeset.get_field(block_data_cs, :display)))
     |> assign(:sheet_counts, sheet_counts(gallery_objects, updated_block_data_cs))
     |> assign(:selected_ids, selected_ids)
     |> assign(:has_objects?, !Enum.empty?(gallery_objects))
     |> assign(:block, updated_block)
     |> assign(:uid, uid)
     |> assign(
       :image_config_target,
       Changeset.get_field(block_data_cs, :image_config_target) ||
         compatible_gallery_target(gallery_config_target, :image)
     )
     |> assign(
       :video_config_target,
       Changeset.get_field(block_data_cs, :video_config_target) ||
         compatible_gallery_target(gallery_config_target, :video)
     )
     |> assign(:allowed_types, Changeset.get_field(block_data_cs, :allowed_types) || [:image, :video])
     |> assign(:override_data, precompute_override_data(gallery_objects, updated_block_data_cs))}
  end

  defp put_processed_image(obj, image) do
    if obj.image_id == image.id, do: Map.put(obj, :image, image), else: obj
  end

  defp replace_object_image(obj, old_image_id, new_image) do
    if obj.image_id == old_image_id do
      obj |> Map.put(:image_id, new_image.id) |> Map.put(:image, new_image)
    else
      obj
    end
  end

  defp selected_id(obj) do
    cond do
      obj.image_id -> {:image, obj.image_id}
      obj.video_id -> {:video, obj.video_id}
      true -> nil
    end
  end

  defp upload_formats(nil), do: ""
  defp upload_formats(formats), do: Enum.join(formats, ",")

  defp initial_view(:list), do: :list
  defp initial_view(_display), do: :grid

  defp compatible_gallery_target(nil, _type), do: "default"
  defp compatible_gallery_target("default", _type), do: "default"
  defp compatible_gallery_target("gallery:" <> _ = target, _type), do: target
  defp compatible_gallery_target("image:" <> _ = target, :image), do: target
  defp compatible_gallery_target("video:" <> _ = target, :video), do: target
  defp compatible_gallery_target(_target, _type), do: "default"

  def render(assigns) do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} class="gallery-block">
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Block.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          multi={false}
          target={@target}
          ref_form={@ref_form}
          config_open={@config_open}
          carried_config={[
            block_data[:type],
            {:radio, block_data[:display]},
            block_data[:class],
            {:checkbox, block_data[:lightbox]},
            {:radio, block_data[:placeholder]}
          ]}
        >
          <:description>
            {block_data[:type].value}
            <%= if @ref_description not in ["", nil] do %>
              — {@ref_description}
            <% end %>
          </:description>

          <div
            id={"block-#{@uid}-upload"}
            phx-hook="Brando.UploadTrigger"
            data-kind="block_ref_gallery"
            data-upload-label={@ref_description || gettext("Gallery")}
            data-component-id={"#{@uid}-gallery"}
            data-asset-type="image"
            data-config-target={@image_config_target}
            data-folder-browser="true"
            data-click-mode="trigger"
            data-accept={Enum.map_join(@allowed_types, ",", &"#{&1}/*")}
            data-video-config-target={@video_config_target}
            data-allowed-types={Enum.join(@allowed_types, ",")}
            class="gallery-upload-wrapper media-gallery"
          >
            <input
              type="file"
              class="file-input"
              accept={Enum.map_join(@allowed_types, ",", &"#{&1}/*")}
              multiple
            />

            <div class="gallery-toolbar-row">
              <div class="gallery-buttons segmented-buttons">
                <button type="button" class="media-button primary upload-trigger">
                  {gettext("Upload media")}
                </button>
                <button
                  :if={:image in @allowed_types}
                  type="button"
                  class="media-button"
                  phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
                >
                  {gettext("Browse images")}
                </button>
                <button
                  :if={:video in @allowed_types}
                  type="button"
                  class="media-button"
                  phx-click={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
                >
                  {gettext("Browse videos")}
                </button>
              </div>
              <Tile.view_switch
                :if={@has_objects?}
                id={"block-#{@uid}-gallery-view"}
                view={@view}
                target={@myself}
                storage_key={"brando:gallery-view:block-#{@uid}"}
              />
            </div>

            <%= if @gallery do %>
              <.inputs_for :let={gallery_form} field={@ref_form[:gallery]}>
                <Input.input type={:hidden} field={gallery_form[:id]} />
                <Input.input type={:hidden} field={gallery_form[:config_target]} />
                <div
                  id={"sortable-#{block_data.id}-gallery-objects"}
                  class={[
                    "images",
                    (@view == :grid && "images-grid gallery-sheet") || "images-list"
                  ]}
                  phx-hook="Brando.SortableAssocs"
                  data-target={@myself}
                  data-sortable-id={"sortable-#{block_data.id}-gallery"}
                  data-sortable-handle=".sort-handle-gallery-object"
                  data-sortable-selector=".gallery-object"
                  data-sortable-dispatch-event="true"
                >
                  <.inputs_for
                    :let={gallery_object_form}
                    field={gallery_form[:gallery_objects]}
                    skip_hidden
                  >
                    <Object.render
                      gallery_object_form={gallery_object_form}
                      gallery_objects={@gallery_objects}
                      display={@view}
                      text_editor={@text_editor}
                      myself={@myself}
                      uid={@uid}
                      gallery_form={gallery_form}
                      override_data={@override_data}
                      block_data={block_data}
                      form_id={@form_id}
                    />
                  </.inputs_for>
                </div>
                <input type="hidden" name={"#{gallery_form.name}[drop_gallery_object_ids][]"} />
              </.inputs_for>
              <Tile.legend
                :if={@view == :grid && @has_objects?}
                images={@sheet_counts.images}
                missing_alt={@sheet_counts.missing_alt}
              />
            <% end %>

            <div :if={!@has_objects?} class="media-gallery-empty">
              <.icon name="image" />
              <span>{gettext("Drop media here to build your gallery")}</span>
              <span class="media-field-meta">{gettext("You can reorder and configure each item afterwards.")}</span>
            </div>
            <div
              id={"block-#{@uid}-gallery-progress"}
              class="media-field-progress"
              phx-update="ignore"
              role="status"
              aria-live="polite"
            >
            </div>
            <div class="media-field-drop" aria-hidden="true">
              <.icon name="upload" /><span>{gettext("Add to gallery")}</span>
            </div>
          </div>

          <:config>
            <Input.input type={:hidden} field={block_data[:type]} />
            <Input.radios
              field={block_data[:display]}
              label={gettext("Display")}
              opts={[
                options: [
                  %{label: "Grid", value: :grid},
                  %{label: "List", value: :list}
                ]
              ]}
            />
            <Input.text field={block_data[:class]} label={gettext("Class")} />
            <Input.toggle field={block_data[:lightbox]} label={gettext("Lightbox")} />

            <Input.radios
              field={block_data[:placeholder]}
              label={gettext("Placeholder")}
              opts={[
                options: [
                  %{label: "SVG", value: :svg},
                  %{label: "Dominant Color", value: :dominant_color},
                  %{label: "Dominant Color faded", value: :dominant_color_faded},
                  %{label: "Micro", value: :micro},
                  %{label: "None", value: :none}
                ]
              ]}
            />

            <input type="hidden" data-upload-formats={@upload_formats} />
          </:config>
          <%!-- Never edited in the config; rendered here so it does not depend
                on whether the config is open. --%>
          <Primitives.array_inputs
            :let={%{value: array_value, name: array_name}}
            field={block_data[:formats]}
          >
            <input type="hidden" name={array_name} value={array_value} />
          </Primitives.array_inputs>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("set_gallery_view", %{"view" => view}, socket) do
    case Tile.parse_view(view) do
      nil -> {:noreply, socket}
      view -> {:noreply, assign(socket, view: view, text_editor: nil)}
    end
  end

  def handle_event("open_text_editor", %{"type" => type, "id" => id, "kind" => kind}, socket)
      when type in ["image", "video"] and kind in ["caption", "alt"] and is_binary(id) do
    type = String.to_existing_atom(type)
    kind = String.to_existing_atom(kind)

    if Map.has_key?(socket.assigns.override_data, {type, id}) and not (type == :video and kind == :alt) do
      {:noreply, assign(socket, :text_editor, %{type: type, id: id, kind: kind})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_text_editor", _, socket) do
    {:noreply, assign(socket, :text_editor, nil)}
  end

  # Writes the override the object's settings dialog edits (`OverrideForm`),
  # with its `use_default_*` flag, through the block's ref data. An image's
  # caption is `title`, a video's is `caption`; alt text stays plain.
  def handle_event("save_object_text", %{"type" => type, "id" => id, "kind" => kind, "value" => value}, socket)
      when type in ["image", "video"] and kind in ["caption", "alt"] and is_binary(id) and is_binary(value) do
    type = String.to_existing_atom(type)
    field = override_text_field(type, kind)

    if field && Map.has_key?(socket.assigns.override_data, {type, id}) do
      text = override_text(kind, value)

      socket
      |> Block.commit_ref_data(ref_data: put_override_text(socket.assigns.block, type, id, field, text))
      |> assign(:text_editor, nil)
      |> then(&{:noreply, &1})
    else
      {:noreply, assign(socket, :text_editor, nil)}
    end
  end

  def handle_event("tiptap_link_dialog", params, socket) do
    TipTapLinkDialog.open(params, Brando.config(:default_language))
    {:noreply, socket}
  end

  def handle_event("tiptap_link_result", params, socket) do
    TipTapLinkDialog.receive_result(params)
    {:noreply, socket}
  end

  def handle_event("toggle_only_selected", _, socket) do
    {:noreply, assign(socket, :show_only_selected?, !socket.assigns.show_only_selected?)}
  end

  def handle_event("select_image", %{"id" => id}, socket) do
    {:ok, image} = Brando.Images.get_image(id)

    already_selected? = image.id in current_selected_image_ids(socket)

    {action_key, selected_images} =
      if already_selected? do
        {:remove_gallery_image_id, Enum.reject(current_selected_image_ids(socket), &(&1 == image.id))}
      else
        {:add_gallery_image_id, current_selected_image_ids(socket) ++ [image.id]}
      end

    Block.commit_ref_data(
      socket,
      Keyword.put([ref_data: Block.current_block_data_map(socket.assigns.block)], action_key, image.id)
    )

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      selected_images: selected_images
    )

    {:noreply, socket}
  end

  def handle_event("set_target", _, socket) do
    myself = socket.assigns.myself
    gallery_objects = socket.assigns.gallery_objects

    # Extract image IDs from gallery objects for the image picker
    selected_images =
      gallery_objects
      |> Enum.filter(& &1.image_id)
      |> Enum.map(& &1.image_id)

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: socket.assigns.image_config_target,
      event_target: myself,
      multi: true,
      selected_images: selected_images
    )

    {:noreply, socket}
  end

  def handle_event("open_video_picker", _, socket) do
    myself = socket.assigns.myself
    gallery_objects = socket.assigns.gallery_objects

    selected_videos =
      gallery_objects
      |> Enum.filter(& &1.video_id)
      |> Enum.map(& &1.video_id)

    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      config_target: socket.assigns.video_config_target,
      event_target: myself,
      multi: true,
      selected_videos: selected_videos
    )

    {:noreply, socket}
  end

  def handle_event("select_video", %{"id" => id}, socket) do
    video_id = String.to_integer(id)

    current_video_ids =
      socket.assigns.gallery_objects
      |> Enum.filter(& &1.video_id)
      |> Enum.map(& &1.video_id)

    action_key = if video_id in current_video_ids, do: :remove_gallery_video_id, else: :add_gallery_video_id

    Block.commit_ref_data(
      socket,
      Keyword.put([ref_data: Block.current_block_data_map(socket.assigns.block)], action_key, video_id)
    )

    {:noreply, socket}
  end

  def handle_event("open_image_editor", %{"image_id" => image_id}, socket) do
    {:ok, image} = Brando.Images.get_image(image_id)

    {:noreply,
     Block.push_image_editor_init(socket, image,
       block_target: {__MODULE__, socket.assigns.id},
       old_image_id: image.id
     )}
  end

  ## Private functions

  defp override_text_field(:image, "caption"), do: :title
  defp override_text_field(:video, "caption"), do: :caption
  defp override_text_field(:image, "alt"), do: :alt
  defp override_text_field(:video, "alt"), do: nil

  defp override_text("caption", value), do: Brando.Captions.normalize(value)
  defp override_text(_kind, value), do: trimmed(value)

  defp trimmed(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp put_override_text(block, type, id, field, text) do
    data = Block.current_block_data_map(block)
    overrides = data.gallery_object_overrides || []
    changes = %{field => text, :"use_default_#{field}" => is_nil(text)}

    {updated, found?} =
      Enum.map_reduce(overrides, false, fn override, found? ->
        if GalleryObjectOverride.for_media?(override, type, id),
          do: {override |> Map.merge(changes) |> Map.put(:object_type, type), true},
          else: {override, found?}
      end)

    updated =
      if found?,
        do: updated,
        else: updated ++ [Map.merge(%GalleryObjectOverride{object_id: id, object_type: type}, changes)]

    Map.put(data, :gallery_object_overrides, updated)
  end

  # Images and how many have no alt text, neither for this block nor in the
  # library. Videos have no alt text and are not counted.
  defp sheet_counts(gallery_objects, block_data_cs) do
    overrides =
      block_data_cs
      |> Changeset.get_field(:gallery_object_overrides, [])
      |> GalleryObjectOverride.index()

    images = Enum.filter(gallery_objects, &loaded_assoc?(&1, :image))

    missing =
      Enum.count(images, fn %{image: image} ->
        override = GalleryObjectOverride.lookup(overrides, :image, image.id)
        alt = if override && Map.get(override, :use_default_alt) != true, do: Map.get(override, :alt)
        not Tile.alt_state(alt, Brando.Images.text(image, :alt, nil)).set?
      end)

    %{images: length(images), missing_alt: missing}
  end

  defp update_block_with_overrides(block_form, initialized_overrides) do
    changeset = block_form.source
    current_data = Changeset.get_field(changeset, :data)

    updated_data_map =
      case current_data do
        %Changeset{} = data_cs ->
          data_cs
          |> Changeset.apply_changes()
          |> Map.from_struct()
          |> Map.put(:gallery_object_overrides, initialized_overrides)

        data when is_struct(data) ->
          data
          |> Map.from_struct()
          |> Map.put(:gallery_object_overrides, initialized_overrides)

        data when is_map(data) ->
          Map.put(data, :gallery_object_overrides, initialized_overrides)
      end

    updated_changeset = Changeset.put_change(changeset, :data, updated_data_map)

    %{block_form | source: updated_changeset}
  end

  defp initialize_gallery_overrides(gallery_objects, block_data_cs) do
    existing_overrides =
      block_data_cs
      |> Changeset.get_field(:gallery_object_overrides, [])
      |> GalleryObjectOverride.index()

    # Create override entries for all gallery objects
    gallery_objects
    |> Enum.map(fn obj ->
      case gallery_object_media(obj) do
        {object_type, object_id_str, _media} ->
          existing_overrides
          |> GalleryObjectOverride.lookup(object_type, object_id_str)
          |> typed_override(object_type, object_id_str)

        nil ->
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  # An override stored without a type takes the type of the media it is found
  # for, so image N and video N never end up sharing one override entry.
  defp typed_override(nil, object_type, object_id_str) do
    %GalleryObjectOverride{
      object_id: object_id_str,
      object_type: object_type,
      title: nil,
      credits: nil,
      alt: nil,
      use_default_title: true,
      use_default_credits: true,
      use_default_alt: true
    }
  end

  defp typed_override(%Changeset{} = override, object_type, _object_id_str),
    do: Changeset.put_change(override, :object_type, object_type)

  defp typed_override(override, object_type, _object_id_str), do: Map.put(override, :object_type, object_type)

  defp gallery_object_media(obj) do
    cond do
      loaded_assoc?(obj, :image) -> {:image, to_string(obj.image.id), obj.image}
      loaded_assoc?(obj, :video) -> {:video, to_string(obj.video.id), obj.video}
      true -> nil
    end
  end

  defp current_selected_image_ids(socket) do
    socket.assigns.gallery_objects
    |> Enum.filter(& &1.image_id)
    |> Enum.map(& &1.image_id)
  end

  defp get_gallery_and_objects(assigns) do
    with {:ok, ref_form} <- get_ref_form(assigns),
         {:ok, gallery} <- get_gallery_from_ref(ref_form) do
      objects = extract_gallery_objects(gallery)
      {gallery, objects}
    else
      _ -> {nil, []}
    end
  end

  defp get_ref_form(%{ref_form: ref_form}) when not is_nil(ref_form), do: {:ok, ref_form}
  defp get_ref_form(_), do: {:error, :no_ref_form}

  defp get_gallery_from_ref(ref_form) do
    ref_cs = ref_form.source

    # Check if gallery was explicitly changed to nil
    case Changeset.fetch_change(ref_cs, :gallery) do
      {:ok, nil} ->
        # Gallery was explicitly set to nil - don't fallback to gallery_id
        {:error, :no_gallery}

      _ ->
        # Either no change or has a value - check the field
        case Changeset.get_field(ref_cs, :gallery) do
          nil -> fetch_gallery_by_id(ref_cs)
          gallery -> {:ok, gallery}
        end
    end
  end

  defp fetch_gallery_by_id(ref_cs) do
    case Changeset.get_field(ref_cs, :gallery_id) do
      nil ->
        {:error, :no_gallery}

      gallery_id ->
        Brando.Galleries.get_gallery(%{
          matches: %{id: gallery_id},
          preload: [gallery_objects: [:image, video: [:thumbnail]]]
        })
    end
  end

  defp extract_gallery_objects(gallery) do
    case Map.get(gallery, :gallery_objects) do
      %Ecto.Association.NotLoaded{} ->
        []

      objects when is_list(objects) ->
        batch_load_media(objects)

      _ ->
        []
    end
  end

  defp batch_load_media(objects) do
    # Collect IDs that need loading
    {missing_image_ids, missing_video_ids} =
      Enum.reduce(objects, {[], []}, fn obj, {img_ids, vid_ids} ->
        img_ids = collect_missing_media_id(obj, :image_id, :image, img_ids)
        vid_ids = collect_missing_media_id(obj, :video_id, :video, vid_ids)
        {img_ids, vid_ids}
      end)

    # Batch fetch missing media
    images_map = batch_fetch_images(Enum.uniq(missing_image_ids))
    videos_map = batch_fetch_videos(Enum.uniq(missing_video_ids))

    # Merge loaded media back into objects
    Enum.map(objects, fn obj ->
      obj
      |> maybe_set_media(:image_id, :image, images_map)
      |> maybe_set_media(:video_id, :video, videos_map)
    end)
  end

  defp collect_missing_media_id(obj, id_field, assoc_field, acc) do
    media_id = Map.get(obj, id_field)
    assoc = Map.get(obj, assoc_field)

    needs_load? =
      media_id &&
        (assoc == nil ||
           match?(%Ecto.Association.NotLoaded{}, assoc) ||
           (assoc_field == :image && is_map(assoc) && Map.get(assoc, :status) != :processed))

    if needs_load?, do: [media_id | acc], else: acc
  end

  defp batch_fetch_images([]), do: %{}

  defp batch_fetch_images(ids) do
    case Brando.Images.list_images(%{filter: %{ids: ids}}) do
      {:ok, images} -> Map.new(images, &{&1.id, &1})
      _ -> %{}
    end
  end

  defp batch_fetch_videos([]), do: %{}

  defp batch_fetch_videos(ids) do
    case Brando.Videos.list_videos(%{filter: %{ids: ids}, preload: [:thumbnail]}) do
      {:ok, videos} -> Map.new(videos, &{&1.id, &1})
      _ -> %{}
    end
  end

  defp maybe_set_media(obj, id_field, assoc_field, media_map) do
    media_id = Map.get(obj, id_field)
    assoc = Map.get(obj, assoc_field)

    cond do
      is_nil(media_id) && match?(%Ecto.Association.NotLoaded{}, assoc) ->
        Map.put(obj, assoc_field, nil)

      is_nil(media_id) ->
        obj

      is_nil(assoc) || match?(%Ecto.Association.NotLoaded{}, assoc) ->
        Map.put(obj, assoc_field, Map.get(media_map, media_id))

      # Re-fetch unprocessed images from DB (they may have been processed since)
      refetch_image?(assoc_field, assoc, media_map, media_id) ->
        Map.put(obj, assoc_field, Map.get(media_map, media_id))

      true ->
        obj
    end
  end

  defp refetch_image?(assoc_field, assoc, media_map, media_id),
    do: assoc_field == :image && Map.get(assoc, :status) != :processed && Map.has_key?(media_map, media_id)

  # Keyed by `{object_type, object_id}`: an image and a video may share an id.
  defp precompute_override_data(gallery_objects, block_data_cs) do
    overrides =
      block_data_cs
      |> Changeset.get_field(:gallery_object_overrides, [])
      |> GalleryObjectOverride.index()

    # Gallery objects should already have media loaded via batch_load_media
    Enum.reduce(gallery_objects, %{}, fn obj, acc ->
      case gallery_object_media(obj) do
        {object_type, object_id_str, media_object} ->
          override_info =
            build_override_info(
              object_id_str,
              object_type,
              media_object,
              GalleryObjectOverride.lookup(overrides, object_type, object_id_str)
            )

          Map.put(acc, {object_type, object_id_str}, override_info)

        nil ->
          acc
      end
    end)
  end

  defp build_override_info(object_id_str, object_type, media_object, object_override) do
    # An image's own texts are language maps; show the default language's.
    media_object = Brando.Images.resolve_texts(media_object, nil)
    default_title = media_object.title || ""
    default_credits = Map.get(media_object, :credits) || ""
    default_alt = if object_type == :image, do: media_object.alt || "", else: ""
    defaults = {default_title, default_credits, default_alt}

    {use_default_title, use_default_credits, use_default_alt, current_title, current_credits, current_alt} =
      if object_override do
        object_override |> override_values() |> current_texts(defaults)
      else
        {true, true, true, default_title, default_credits, default_alt}
      end

    base = %{
      object_id: object_id_str,
      object_type: object_type,
      default_title: default_title,
      default_credits: default_credits,
      default_alt: default_alt,
      use_default_title: use_default_title,
      use_default_credits: use_default_credits,
      use_default_alt: use_default_alt,
      current_title: current_title,
      current_credits: current_credits,
      current_alt: current_alt,
      override_exists: object_override != nil
    }

    Map.merge(base, video_defaults(object_type, media_object))
  end

  # Video playback defaults
  defp video_defaults(object_type, media_object) do
    if object_type == :video do
      %{
        default_autoplay: Map.get(media_object, :autoplay) || false,
        default_loop: Map.get(media_object, :loop) || false,
        default_muted: Map.get(media_object, :muted) || false,
        default_controls: Map.get(media_object, :controls) || false,
        default_preload: Map.get(media_object, :preload) || false
      }
    else
      %{}
    end
  end

  defp override_values(object_override) do
    case object_override do
      %Changeset{} ->
        %{
          use_default_title: Changeset.get_field(object_override, :use_default_title),
          use_default_credits: Changeset.get_field(object_override, :use_default_credits),
          use_default_alt: Changeset.get_field(object_override, :use_default_alt),
          title: Changeset.get_field(object_override, :title),
          credits: Changeset.get_field(object_override, :credits),
          alt: Changeset.get_field(object_override, :alt)
        }

      _ ->
        %{
          use_default_title: Map.get(object_override, :use_default_title, true),
          use_default_credits: Map.get(object_override, :use_default_credits, true),
          use_default_alt: Map.get(object_override, :use_default_alt, true),
          title: Map.get(object_override, :title),
          credits: Map.get(object_override, :credits),
          alt: Map.get(object_override, :alt)
        }
    end
  end

  defp current_texts(values, {default_title, default_credits, default_alt}) do
    {
      values.use_default_title,
      values.use_default_credits,
      values.use_default_alt,
      current_text(values.use_default_title, default_title, values.title),
      current_text(values.use_default_credits, default_credits, values.credits),
      current_text(values.use_default_alt, default_alt, values.alt)
    }
  end

  defp current_text(use_default, default, value), do: if(use_default, do: default, else: value || "")
end
