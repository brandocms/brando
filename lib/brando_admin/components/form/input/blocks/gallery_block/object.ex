defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.Object do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  import Brando.Utils, only: [loaded_assoc?: 2]

  alias Brando.Images
  alias Brando.Villain.Blocks.GalleryObjectOverride
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.OverrideForm
  alias BrandoAdmin.Components.Form.Input.Gallery.Tile
  alias Ecto.Changeset
  alias Phoenix.LiveView.JS

  # prop gallery_object_form, :any, required: true
  # prop gallery_objects, :list, required: true
  # prop display, :atom, required: true — the admin's view (:grid/:list), not the block's saved `display`
  # prop text_editor, :map — the open caption/alt popover, `%{type, id, kind}`
  # prop myself, :any, required: true
  # prop uid, :string, required: true
  # prop gallery_form, :any, required: true
  # prop override_data, :map, required: true
  # prop block_data, :any, required: true
  # prop form_id, :string, required: true

  def render(assigns) do
    # Find the corresponding object for display - use index for new objects without IDs
    obj = Enum.at(assigns.gallery_objects, assigns.gallery_object_form.index)
    object_modal_id = "gallery-object-modal-#{assigns.uid}-#{assigns.gallery_object_form.index}"

    current_override = get_current_override_from_form(assigns.block_data, media_key(obj))

    # Determine the actual display values (considering current form overrides)
    display_values =
      obj
      |> compute_display_values_from_form(current_override)
      |> Map.put(:caption, override_value(current_override, :caption))

    assigns = assign(assigns, :obj, obj)
    assigns = assign(assigns, :object_modal_id, object_modal_id)
    assigns = assign(assigns, :display_values, display_values)
    assigns = assign(assigns, :list_row, list_row(obj, assigns.gallery_object_form, display_values))
    assigns = assign_tile(assigns, obj, current_override)

    ~H"""
    <div
      id={"gallery-object-#{@uid}-#{gallery_object_dom_key(@gallery_object_form)}"}
      class="gallery-object preview sort-handle-gallery-object draggable"
      data-id={@gallery_object_form.index}
    >
      <!-- Hidden form fields -->
      <input type="hidden" name={@gallery_object_form[:id].name} value={@gallery_object_form[:id].value} />
      <input type="hidden" name={@gallery_object_form[:_persistent_id].name} value={@gallery_object_form.index} />
      <Input.input type={:hidden} field={@gallery_object_form[:gallery_id]} />
      <Input.input type={:hidden} field={@gallery_object_form[:image_id]} />
      <Input.input type={:hidden} field={@gallery_object_form[:video_id]} />
      <Input.input type={:hidden} field={@gallery_object_form[:creator_id]} />

      <!-- Hidden inputs for sorting -->
      <input
        type="hidden"
        name={"#{@gallery_form.name}[sort_gallery_object_ids][]"}
        value={@gallery_object_form.index}
      />

      <div :if={@display != :grid} class="gallery-block-list-row">
        <div class="gallery-block-list-thumb">
          <%= cond do %>
            <% @obj && loaded_assoc?(@obj, :image) -> %>
              <Content.image image={@obj.image} size={:thumb} />
            <% @obj && loaded_assoc?(@obj, :video) && @obj.video.thumbnail -> %>
              <Content.image image={@obj.video.thumbnail} size={:thumb} />
            <% true -> %>
              <div class="img-placeholder">
                <.icon name={if @list_row.media_type == :video, do: "video", else: "image"} />
              </div>
          <% end %>
        </div>
        <div
          class="gallery-block-list-copy"
          phx-click={show_modal("##{@object_modal_id}")}
          data-sortable-filter
        >
          <div class="gallery-block-list-title">{@list_row.title}</div>
          <div :if={@list_row.details != []} class="gallery-block-list-details">
            <span :for={detail <- @list_row.details}>{detail}</span>
          </div>
          <%= cond do %>
            <% @display_values.alt -> %>
              <div class="gallery-block-list-alt" title={@display_values.alt}>
                <span class="gallery-block-list-alt-label">{gettext("Alt")}</span>
                {@display_values.alt}
              </div>
            <% @list_row.media_type == :image -> %>
              <div class="gallery-block-list-alt is-missing">{gettext("No alt text")}</div>
            <% true -> %>
          <% end %>
        </div>
        <.object_actions gallery_object_form={@gallery_object_form} gallery_form={@gallery_form} myself={@myself} />
      </div>

      <Tile.tile
        :if={@display == :grid}
        id={"gallery-tile-#{@uid}-#{@gallery_object_form.index}"}
        number={@gallery_object_form.index + 1}
        media_type={@tile.media_type}
        thumb_url={@tile.thumb_url}
        processing={@tile.processing}
        caption={@tile.caption}
        alt={@tile.alt}
        editing={@tile.editing}
        open_caption={open_text_editor(@tile, :caption, @myself)}
        open_alt={open_text_editor(@tile, :alt, @myself)}
      >
        <:actions>
          <.object_actions
            gallery_object_form={@gallery_object_form}
            gallery_form={@gallery_form}
            myself={@myself}
            configure={show_modal("##{@object_modal_id}")}
          />
        </:actions>
        <:editor :if={@tile.editing}>
          <Tile.text_editor
            id={"gallery-tile-#{@uid}-#{@gallery_object_form.index}-#{@tile.editing}-editor"}
            kind={@tile.editing}
            filename={@tile.filename}
            value={if @tile.editing == :caption, do: @tile.caption_override, else: @tile.alt_override}
            placeholder={@tile.alt_library}
            target={@myself}
            save_event="save_object_text"
            close_event="close_text_editor"
            params={%{type: @tile.object_type, id: @tile.object_id, kind: @tile.editing}}
          />
        </:editor>
      </Tile.tile>

      <!-- Individual modal for this gallery object (inside the div) -->
      <Content.modal title={gettext("Edit captions")} id={@object_modal_id} data-sortable-filter>
        <div class="panels">
          <div class="panel">
            <figure>
              <%= if @obj && loaded_assoc?(@obj, :image) do %>
                <Content.image image={@obj.image} size={:smallest} />
              <% else %>
                <%= if @obj && loaded_assoc?(@obj, :video) && @obj.video.thumbnail do %>
                  <Content.image image={@obj.video.thumbnail} size={:smallest} />
                <% else %>
                  <div class="video-placeholder">
                    <.icon name="video" />
                  </div>
                <% end %>
              <% end %>
            </figure>
          </div>
          <div class="panel">
            <.gallery_caption_overrides
              obj={@obj}
              uid={@uid}
              override_data={@override_data}
              block_data={@block_data}
            />
          </div>
        </div>
      </Content.modal>
    </div>
    """
  end

  ## Private functions

  defp open_text_editor(%{object_type: nil}, _kind, _myself), do: nil

  defp open_text_editor(tile, kind, myself),
    do: JS.push("open_text_editor", target: myself, value: %{type: tile.object_type, id: tile.object_id, kind: kind})

  # What the grid square shows. A caption or alt text applies when its
  # `use_default_*` flag is off, as on the site (`Brando.Villain.Parser`). An
  # image's caption is the override's `title`; a video's is its `caption`.
  defp assign_tile(%{display: :grid} = assigns, obj, override) do
    {object_type, object_id} = media_key(obj) || {nil, nil}
    caption_field = if object_type == :video, do: :caption, else: :title
    caption_override = override_value(override, caption_field)
    alt_override = override_value(override, :alt)

    editing = text_editor_kind(assigns[:text_editor], object_type, object_id)

    tile =
      case object_type do
        :image -> image_tile(obj.image, caption_override, alt_override)
        :video -> video_tile(obj.video, caption_override)
        _ -> empty_tile(assigns.gallery_object_form)
      end

    tile =
      Map.merge(tile, %{
        object_type: object_type,
        object_id: object_id,
        editing: editing,
        caption_override: caption_override,
        alt_override: alt_override
      })

    assign(assigns, :tile, tile)
  end

  defp assign_tile(assigns, _obj, _override), do: assign(assigns, :tile, nil)

  defp text_editor_kind(text_editor, object_type, object_id) do
    case text_editor do
      %{type: ^object_type, id: ^object_id, kind: kind} when not is_nil(object_type) -> kind
      _ -> nil
    end
  end

  defp image_tile(image, caption_override, alt_override) do
    alt_library = Images.text(image, :alt, nil)

    %{
      media_type: :image,
      thumb_url: image.status == :processed && Brando.Utils.img_url(image, :thumb, prefix: Brando.Utils.media_url()),
      processing: image.status != :processed,
      filename: image.path && Path.basename(image.path),
      caption: Tile.caption_state(caption_override, Images.text(image, :title, nil)),
      alt: Tile.alt_state(alt_override, alt_library),
      alt_library: alt_library
    }
  end

  defp video_tile(video, caption_override) do
    %{
      media_type: :video,
      thumb_url: Brando.Videos.Helpers.thumbnail_url(video),
      processing: false,
      filename: video.title || video.remote_id,
      caption: Tile.caption_state(caption_override, video.title),
      alt: nil,
      alt_library: nil
    }
  end

  defp empty_tile(gallery_object_form) do
    media_type = if gallery_object_form[:image_id].value, do: :image, else: :video

    %{
      media_type: media_type,
      thumb_url: nil,
      processing: false,
      filename: nil,
      caption: %{set?: false, html: nil},
      alt: if(media_type == :image, do: %{set?: false, text: nil}),
      alt_library: nil
    }
  end

  defp override_value(nil, _field), do: nil

  defp override_value(override, field) do
    {value, use_default} =
      case override do
        %Changeset{} -> {Changeset.get_field(override, field), Changeset.get_field(override, :"use_default_#{field}")}
        %{} -> {Map.get(override, field), Map.get(override, :"use_default_#{field}", true)}
      end

    if use_default != true and is_binary(value) and String.trim(value) != "", do: value
  end

  defp get_current_override_from_form(_block_data_form, nil), do: nil

  defp get_current_override_from_form(block_data_form, {object_type, object_id_str}) do
    block_data_form.source
    |> Changeset.get_field(:gallery_object_overrides, [])
    |> Enum.find(&GalleryObjectOverride.for_media?(&1, object_type, object_id_str))
  end

  # Images and videos are numbered separately, so the id alone is not unique
  # within a gallery.
  defp media_key(obj) do
    cond do
      obj && loaded_assoc?(obj, :image) -> {:image, to_string(obj.image.id)}
      obj && loaded_assoc?(obj, :video) -> {:video, to_string(obj.video.id)}
      true -> nil
    end
  end

  defp gallery_object_dom_key(gallery_object_form) do
    case gallery_object_form[:image_id].value do
      nil -> "video-#{gallery_object_form[:video_id].value}"
      image_id -> "image-#{image_id}"
    end
  end

  defp override_form_for_media?(override_form, {object_type, object_id_str}) do
    GalleryObjectOverride.for_media?(
      %{object_id: override_form[:object_id].value, object_type: override_form[:object_type].value},
      object_type,
      object_id_str
    )
  end

  defp compute_display_values_from_form(nil, _), do: %{title: nil, alt: nil, credits: nil}

  defp compute_display_values_from_form(obj, nil), do: base_display_values(obj)

  defp compute_display_values_from_form(obj, override) do
    base_values = base_display_values(obj)

    {use_default_title, use_default_credits, use_default_alt, title, credits, alt} = override_fields(override)

    # Apply overrides from the current values
    %{
      title: override_or_default(use_default_title, title, base_values.title),
      alt: override_or_default(use_default_alt, alt, base_values.alt),
      credits: override_or_default(use_default_credits, credits, base_values.credits)
    }
  end

  # Extract override values whether it's a changeset or struct
  defp override_fields(override) do
    case override do
      %Changeset{} ->
        {
          Changeset.get_field(override, :use_default_title),
          Changeset.get_field(override, :use_default_credits),
          Changeset.get_field(override, :use_default_alt),
          Changeset.get_field(override, :title),
          Changeset.get_field(override, :credits),
          Changeset.get_field(override, :alt)
        }

      %{} ->
        {
          Map.get(override, :use_default_title, true),
          Map.get(override, :use_default_credits, true),
          Map.get(override, :use_default_alt, true),
          Map.get(override, :title),
          Map.get(override, :credits),
          Map.get(override, :alt)
        }

      _ ->
        {true, true, true, nil, nil, nil}
    end
  end

  defp override_or_default(use_default, value, base_value) do
    if use_default, do: base_value, else: value || base_value
  end

  # The list row's title and details line. The title is the caption when there
  # is one (captions may hold markup, the row shows plain text), else the
  # image's filename; with a caption the filename moves to the details line.
  # A video's caption falls back to its own title.
  defp list_row(obj, gallery_object_form, display_values) do
    caption = plain_text(display_values[:caption]) || plain_text(display_values.title)

    cond do
      obj && loaded_assoc?(obj, :image) ->
        image_list_row(obj.image, caption)

      obj && loaded_assoc?(obj, :video) ->
        video_list_row(obj.video, caption)

      true ->
        media_type = if gallery_object_form[:image_id].value, do: :image, else: :video
        %{media_type: media_type, title: "-", details: []}
    end
  end

  defp image_list_row(image, caption) do
    filename = image.path && Path.basename(image.path)

    %{
      media_type: :image,
      title: caption || filename || "-",
      details: present([caption && filename, dimensions(image), image_formats(image.formats)])
    }
  end

  defp video_list_row(video, caption) do
    %{
      media_type: :video,
      title: caption || video.remote_id || gettext("Video"),
      details: present([video_source(video.type), dimensions(video)])
    }
  end

  defp dimensions(media), do: media.width && media.height && "#{media.width}\u00d7#{media.height}"

  defp plain_text(nil), do: nil

  defp plain_text(text) do
    case text |> HtmlSanitizeEx.strip_tags() |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  defp present(values), do: Enum.filter(values, &(is_binary(&1) and &1 != ""))

  defp image_formats(formats) when is_list(formats) do
    formats
    |> Enum.reject(&(&1 == :original))
    |> Enum.map_join(", ", &to_string/1)
  end

  defp image_formats(_), do: nil

  defp video_source(type) when type in [:vimeo, :vimeo_account], do: "Vimeo"
  defp video_source(:youtube), do: "YouTube"
  defp video_source(:mux), do: "Mux"
  defp video_source(:bunny), do: "Bunny"
  defp video_source(:cloudflare), do: "Cloudflare"
  defp video_source(_), do: gettext("Video")

  ## Function components

  attr :gallery_object_form, :any, required: true
  attr :gallery_form, :any, required: true
  attr :myself, :any, required: true
  attr :configure, :any, default: nil, doc: "Opens the object's settings; the grid has no row to click"

  # Edit, then delete. A corner group in the grid, the row's right edge in the list.
  defp object_actions(assigns) do
    ~H"""
    <div class="gallery-object-actions" data-sortable-filter>
      <button
        :if={@gallery_object_form[:image_id].value}
        class="edit-image-btn"
        type="button"
        aria-label={gettext("Edit image")}
        phx-click={
          JS.push("open_image_editor",
            target: @myself,
            value: %{image_id: @gallery_object_form[:image_id].value}
          )
          |> open_image_editor_drawer()
        }
        data-sortable-filter
      >
        <.icon name="square-pen" />
      </button>
      <button
        :if={@configure}
        class="configure-object"
        type="button"
        aria-label={gettext("Configure")}
        title={gettext("Configure")}
        phx-click={@configure}
        data-sortable-filter
      >
        <.icon name="settings" />
      </button>
      <button
        class="delete-x"
        type="button"
        aria-label={gettext("Delete")}
        name={"#{@gallery_form.name}[drop_gallery_object_ids][]"}
        value={@gallery_object_form.index}
        phx-click={JS.dispatch("change")}
        data-sortable-filter
      >
        <.icon name="x" />
      </button>
    </div>
    """
  end

  attr :obj, :map, required: true
  attr :uid, :string, required: true
  attr :override_data, :map, required: true
  attr :block_data, :any, required: true

  def gallery_caption_overrides(assigns) do
    media_key = media_key(assigns.obj)

    override_info = media_key && Map.get(assigns.override_data, media_key)

    if override_info do
      {object_type, object_id_str} = media_key

      assigns =
        assign(assigns,
          override_info: override_info,
          media_key: media_key,
          component_id: "override-inline-#{assigns.uid}-#{object_type}-#{object_id_str}"
        )

      ~H"""
      <div>
        {# With initialized overrides, we can always use standard inputs_for}
        <.inputs_for :let={override_form} field={@block_data[:gallery_object_overrides]}>
          <%= if override_form_for_media?(override_form, @media_key) do %>
            <.live_component
              module={OverrideForm}
              id={@component_id}
              form={override_form}
              override_info={@override_info}
              variant={:inline}
            />
          <% end %>
        </.inputs_for>
      </div>
      """
    else
      ~H"""
      <div>
        <p>{gettext("Caption overrides not available - no override data")}</p>
      </div>
      """
    end
  end

  defp base_display_values(obj) do
    cond do
      loaded_assoc?(obj, :image) ->
        %{
          title: Images.text(obj.image, :title, nil),
          alt: Images.text(obj.image, :alt, nil),
          credits: Images.text(obj.image, :credits, nil)
        }

      loaded_assoc?(obj, :video) ->
        %{title: obj.video.title, alt: nil, credits: nil}

      true ->
        %{title: nil, alt: nil, credits: nil}
    end
  end
end
