defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Brando.Utils, only: [loaded_assoc?: 2]

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.Object
  alias BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.OverrideForm
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
  # data display, :atom
  # data show_only_selected?, :boolean
  # data upload_formats, :string

  def mount(socket) do
    {:ok, assign(socket, available_images: [], show_only_selected?: false)}
  end

  def update(assigns, socket) do
    {gallery, gallery_objects} = get_gallery_and_objects(assigns)

    selected_ids =
      gallery_objects
      |> Enum.map(fn obj ->
        cond do
          obj.image_id -> {:image, obj.image_id}
          obj.video_id -> {:video, obj.video_id}
          true -> nil
        end
      end)
      |> Enum.filter(& &1)

    block_data_cs = Block.get_block_data_changeset(assigns.block)

    upload_formats =
      case Changeset.get_field(block_data_cs, :formats) do
        nil -> ""
        formats -> Enum.join(formats, ",")
      end

    # Initialize overrides once on mount, then preserve across updates
    initialized_overrides =
      socket.assigns[:initialized_overrides] ||
        initialize_gallery_overrides(gallery_objects, block_data_cs)

    updated_block = update_block_with_overrides(assigns.block, initialized_overrides)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:initialized_overrides, initialized_overrides)
     |> assign(:gallery, gallery)
     |> assign(:gallery_objects, gallery_objects)
     |> assign(:indexed_objects, Enum.with_index(gallery_objects))
     |> assign(:upload_formats, upload_formats)
     |> assign(:display, Changeset.get_field(block_data_cs, :display))
     |> assign(:selected_ids, selected_ids)
     |> assign(:has_objects?, !Enum.empty?(gallery_objects))
     |> assign(:block, updated_block)
     |> assign(:uid, assigns.ref_form[:uid].value)
     |> assign_new(:override_data, fn -> precompute_override_data(gallery_objects, block_data_cs) end)}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="gallery-block"
      phx-hook="Brando.LegacyImageUpload"
      data-upload-multi="true"
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
          ref_form={@ref_form}
        >
          <:description>
            {block_data[:type].value}
            <%= if @ref_description not in ["", nil] do %>
              — {@ref_description}
            <% end %>
          </:description>

          <div id={"block-#{@uid}-base-f-in"} phx-update="ignore">
            <input name={"block-#{@uid}-f-in"} class="file-input" type="file" multiple />
          </div>

          <span id={"block-#{@uid}-base-file-upload-btn-with-images"} phx-update="ignore">
            <button type="button" class="tiny file-upload" id={"block-#{@uid}-up-btn-with-images"}>
              {gettext("Upload images")}
            </button>
          </span>
          <button
            type="button"
            class="tiny"
            phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
          >
            {gettext("Select images")}
          </button>
          <button
            type="button"
            class="tiny"
            phx-click={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
          >
            {gettext("Select videos")}
          </button>
          <%= if @gallery do %>
            <.inputs_for :let={gallery_form} field={@ref_form[:gallery]}>
              <Input.input type={:hidden} field={gallery_form[:id]} />
              <Input.input type={:hidden} field={gallery_form[:config_target]} />
              <div
                id={"sortable-#{block_data.id}-gallery-objects"}
                class={[
                  "images",
                  (@display == :grid && "images-grid") || "images-list"
                ]}
                phx-hook="Brando.SortableAssocs"
                data-target={@myself}
                data-sortable-id={"sortable-#{block_data.id}-gallery"}
                data-sortable-handle=".sort-handle-gallery-object"
                data-sortable-selector=".gallery-object"
                data-sortable-push-event="true"
              >
                <.inputs_for :let={gallery_object_form} field={gallery_form[:gallery_objects]} skip_hidden>
                  <Object.render
                    gallery_object_form={gallery_object_form}
                    gallery_objects={@gallery_objects}
                    display={@display}
                    myself={@myself}
                    uid={@uid}
                    gallery_form={gallery_form}
                    override_data={@override_data}
                    block_data={block_data}
                  />
                </.inputs_for>
              </div>
            </.inputs_for>
          <% end %>

          <div :if={!@has_objects?} class="upload-canvas empty">
            <div class="alert">
              {gettext(
                "No objects currently in block. Click one of the buttons above to get started, or drag and drop media here."
              )}
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
            <Input.text field={block_data[:series_slug]} label={gettext("Series slug")} />
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

            <Form.array_inputs :let={%{value: array_value, name: array_name}} field={block_data[:formats]}>
              <input type="hidden" name={array_name} value={array_value} />
            </Form.array_inputs>

            <input type="hidden" data-upload-formats={@upload_formats} />
          </:config>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_only_selected", _, socket) do
    {:noreply, assign(socket, :show_only_selected?, !socket.assigns.show_only_selected?)}
  end

  def handle_event("reposition", %{"old" => old_idx, "new" => new_idx}, socket) do
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    # Get current block data for gallery settings
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)

    # Only gallery configuration data goes to block data
    new_block_data = Map.from_struct(block_data)

    send_update(target, %{
      event: "update_ref_data",
      ref_data: new_block_data,
      ref_name: ref_name,
      reorder_gallery_objects: {old_idx, new_idx}
    })

    {:noreply, socket}
  end

  def handle_event("image_uploaded", %{"id" => id}, socket) do
    # For refs, add image to gallery association
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    {:ok, image} = Brando.Images.get_image(id)

    # Get current block data for gallery settings
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)

    # Only gallery configuration data goes to block data
    new_block_data = Map.from_struct(block_data)

    send_update(target, %{
      event: "update_ref_data",
      ref_data: new_block_data,
      ref_name: ref_name,
      add_gallery_image_id: image.id
    })

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id, "selected" => "false"}, socket) do
    # For refs, add image to gallery association
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    {:ok, image} = Brando.Images.get_image(id)

    # Get current block data for gallery settings
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)

    # Only gallery configuration data goes to block data
    new_block_data = Map.from_struct(block_data)

    send_update(target, %{
      event: "update_ref_data",
      ref_data: new_block_data,
      ref_name: ref_name,
      add_gallery_image_id: image.id
    })

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id, "selected" => "true"}, socket) do
    # For refs, remove image from gallery association
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    {:ok, image} = Brando.Images.get_image(id)

    # Get current block data for gallery settings
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)

    # Only gallery configuration data goes to block data
    new_block_data = Map.from_struct(block_data)

    send_update(target, %{
      event: "update_ref_data",
      ref_data: new_block_data,
      ref_name: ref_name,
      remove_gallery_image_id: image.id
    })

    {:noreply, socket}
  end

  def handle_event("remove_object", %{"index" => obj_index}, socket) do
    # For refs, remove object from gallery association by index
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    # Get current block data for gallery settings
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)

    # Only gallery configuration data goes to block data
    new_block_data = Map.from_struct(block_data)

    send_update(target, %{
      event: "update_ref_data",
      ref_data: new_block_data,
      ref_name: ref_name,
      remove_gallery_object_index: String.to_integer(obj_index)
    })

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
      config_target: "default",
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
      config_target: nil,
      event_target: myself,
      multi: true,
      selected_videos: selected_videos
    )

    {:noreply, socket}
  end

  def handle_event("select_video", %{"id" => id, "selected" => "false"}, socket) do
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)
    new_block_data = Map.from_struct(block_data)

    send_update(target, %{
      event: "update_ref_data",
      ref_data: new_block_data,
      ref_name: ref_name,
      add_gallery_video_id: String.to_integer(id)
    })

    {:noreply, socket}
  end

  def handle_event("select_video", %{"id" => id, "selected" => "true"}, socket) do
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)
    new_block_data = Map.from_struct(block_data)

    send_update(target, %{
      event: "update_ref_data",
      ref_data: new_block_data,
      ref_name: ref_name,
      remove_gallery_video_id: String.to_integer(id)
    })

    {:noreply, socket}
  end

  ## Function components

  attr :obj, :map, required: true
  attr :uid, :string, required: true
  attr :override_data, :map, required: true
  attr :block_data, :any, required: true

  def gallery_caption_overrides(assigns) do
    # Extract object ID and look up precomputed data
    object_id_str =
      cond do
        loaded_assoc?(assigns.obj, :image) -> to_string(assigns.obj.image.id)
        loaded_assoc?(assigns.obj, :video) -> to_string(assigns.obj.video.id)
        true -> nil
      end

    # Get the precomputed override info for this object
    override_info = Map.get(assigns.override_data, object_id_str)

    assigns = assign(assigns, :override_info, override_info)
    assigns = assign(assigns, :object_id_str, object_id_str)

    ~H"""
    <div>
      <h4>{gettext("Caption Overrides")}</h4>

      <.inputs_for :let={override_form} field={@block_data[:gallery_object_overrides]}>
        <%= if override_form[:object_id].value == @object_id_str do %>
          <.live_component
            module={OverrideForm}
            id={"override-modal-#{@uid}-#{@object_id_str}"}
            form={override_form}
            override_info={@override_info}
            variant={:modal}
          />
        <% end %>
      </.inputs_for>
    </div>
    """
  end

  ## Private functions

  defp update_block_with_overrides(block_form, initialized_overrides) do
    # Update the changeset in the form's source with the initialized overrides
    changeset = block_form.source

    # Since :data has on_replace: :update, we need to update it via put_change with a map
    # Get the current data
    current_data = Changeset.get_field(changeset, :data)

    # Convert the data to a map and add the overrides
    data_map =
      case current_data do
        %Changeset{} -> current_data |> Changeset.get_field(:__struct__) |> Map.from_struct()
        data -> Map.from_struct(data)
      end

    # Update the data map with the overrides
    updated_data_map = Map.put(data_map, :gallery_object_overrides, initialized_overrides)

    # Update the main changeset with the map (not a changeset)
    updated_changeset = Changeset.put_change(changeset, :data, updated_data_map)

    # Return the updated form
    %{block_form | source: updated_changeset}
  end

  defp initialize_gallery_overrides(gallery_objects, block_data_cs) do
    existing_overrides = Changeset.get_field(block_data_cs, :gallery_object_overrides, [])

    # Build a map of existing overrides by object_id
    existing_map =
      Enum.reduce(existing_overrides, %{}, fn override, acc ->
        Map.put(acc, override.object_id, override)
      end)

    # Create override entries for all gallery objects
    all_overrides =
      Enum.map(gallery_objects, fn obj ->
        object_id_str =
          cond do
            loaded_assoc?(obj, :image) -> to_string(obj.image.id)
            loaded_assoc?(obj, :video) -> to_string(obj.video.id)
            true -> nil
          end

        object_type =
          cond do
            loaded_assoc?(obj, :image) -> :image
            loaded_assoc?(obj, :video) -> :video
            true -> nil
          end

        if object_id_str do
          # Use existing override or create a new default one
          Map.get(existing_map, object_id_str, %Brando.Villain.Blocks.GalleryObjectOverride{
            object_id: object_id_str,
            object_type: object_type,
            title: nil,
            credits: nil,
            alt: nil,
            use_default_title: true,
            use_default_credits: true,
            use_default_alt: true
          })
        end
      end)
      |> Enum.filter(& &1)

    # Return the complete overrides list - will be applied to changeset in render
    all_overrides
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

    needs_load? = media_id && (assoc == nil || match?(%Ecto.Association.NotLoaded{}, assoc))

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

      true ->
        obj
    end
  end

  defp precompute_override_data(gallery_objects, block_data_cs) do
    current_overrides = Changeset.get_field(block_data_cs, :gallery_object_overrides, [])

    overrides_map = Map.new(current_overrides, &{&1.object_id, &1})

    # Gallery objects should already have media loaded via batch_load_media
    Enum.reduce(gallery_objects, %{}, fn obj, acc ->
      {object_id_str, object_type, media_object} =
        cond do
          loaded_assoc?(obj, :image) -> {to_string(obj.image.id), :image, obj.image}
          loaded_assoc?(obj, :video) -> {to_string(obj.video.id), :video, obj.video}
          true -> {nil, nil, nil}
        end

      if object_id_str do
        override_info =
          build_override_info(
            object_id_str,
            object_type,
            media_object,
            Map.get(overrides_map, object_id_str)
          )

        Map.put(acc, object_id_str, override_info)
      else
        acc
      end
    end)
  end

  defp build_override_info(object_id_str, object_type, media_object, object_override) do
    default_title = media_object.title || ""
    default_credits = Map.get(media_object, :credits) || ""
    default_alt = if object_type == :image, do: media_object.alt || "", else: ""

    {use_default_title, use_default_credits, use_default_alt, current_title, current_credits, current_alt} =
      if object_override do
        {
          object_override.use_default_title,
          object_override.use_default_credits,
          object_override.use_default_alt,
          if(object_override.use_default_title, do: default_title, else: object_override.title || ""),
          if(object_override.use_default_credits, do: default_credits, else: object_override.credits || ""),
          if(object_override.use_default_alt, do: default_alt, else: object_override.alt || "")
        }
      else
        {true, true, true, default_title, default_credits, default_alt}
      end

    %{
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
  end
end
