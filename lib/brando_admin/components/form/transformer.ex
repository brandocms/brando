defmodule BrandoAdmin.Components.Form.Transformer do
  @moduledoc """
  Stream-based transformer component for managing has_many associations
  with bulk media uploads (images and/or videos).

  Unlike the changeset-based Subform approach, this component:
  - Owns its items as a LiveView stream (no `inputs_for`)
  - Does not touch the parent form changeset during editing
  - Collects data at save time via the signal-and-collect pattern

  Supports three transformer styles:
  - `{:transformer, :image_field}` — image-only (backward compatible)
  - `{:transformer, [:image_field]}` — image-only (list syntax)
  - `{:transformer, [:image_field, :video_field]}` — mixed media
  """
  use BrandoAdmin, :live_component

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Form.Subform

  import Ecto.Changeset, only: [change: 2, get_field: 2]

  use Gettext, backend: Brando.Gettext

  @image_extensions ~w(.jpg .jpeg .png .gif .webp .svg)
  @video_extensions ~w(.mp4 .webm .mov .avi .ogv)

  def mount(socket) do
    {:ok,
     socket
     |> assign(:initialized?, false)
     |> assign(:items, [])
     |> assign(:open_entries, MapSet.new())
     |> assign(:picking_dom_id, nil)
     |> assign(:editing_dom_id, nil)
     |> assign(:upload_errors, [])}
  end

  # --- Update handlers ---

  def update(%{event: "fetch_transformer_data", tag: tag}, socket) do
    items = socket.assigns.items
    relation_key = socket.assigns.relation_key
    form_id = socket.assigns.form_id

    # Placeholders have no asset yet, so they cannot be persisted. Saving mid
    # batch keeps everything already delivered and leaves the rest uploading —
    # dropping them silently would look like data loss, so say so.
    {pending, ready} = Enum.split_with(items, & &1.pending)

    # Build save-time data: changesets for existing records, maps for new
    save_data =
      ready
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        fields_with_sequence = Map.put(item.changes, :sequence, idx)

        if item.is_new do
          Map.merge(item.source, fields_with_sequence)
        else
          change(item.source, fields_with_sequence)
        end
      end)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      event: "provide_transformer_data",
      transformer_field: relation_key,
      transformer_data: save_data,
      tag: tag
    )

    {:ok, maybe_warn_about_pending(socket, pending)}
  end

  def update(%{event: "image_updated", image: image}, socket) do
    update_item_asset(socket, socket.assigns.image_field, image)
  end

  # Delivered by the form's pending-image registry once processing finishes —
  # this is what swaps the "Processing" card for the real thumbnail.
  def update(%{event: "image_processed", image: image}, socket) do
    update_item_asset(socket, socket.assigns.image_field, image)
  end

  def update(%{event: "video_updated", video: video}, socket) do
    update_item_asset(socket, socket.assigns.video_field, video)
  end

  # VideoPicker reports a grid selection as a send_update rather than an event.
  def update(%{event: "select_video", id: id}, socket) do
    case Brando.Videos.get_video(id) do
      {:ok, video} -> {:ok, select_asset(socket, socket.assigns.video_field, video)}
      _error -> {:ok, socket}
    end
  end

  # Delivered by the sticky UploadManager. The ref is the one the client
  # registered its placeholder under; without it — an upload started somewhere
  # the batch never registered — we simply append.
  #
  # Images ride the manager too, rather than a component-local allow_upload:
  # LiveView routes upload *progress* by the file input's form owner, and this
  # component's input necessarily sits inside the entry form, which belongs to
  # the Form component. A component-local upload preflights correctly and then
  # crashes on the first progress tick with an unknown upload ref.
  def update(%{event: "upload_complete", asset: %Brando.Videos.Video{} = video} = assigns, socket) do
    deliver(socket, Map.get(assigns, :ref), socket.assigns.video_field, video, &append_video_item/2)
  end

  def update(%{event: "upload_complete", asset: %Brando.Images.Image{} = image} = assigns, socket) do
    deliver(socket, Map.get(assigns, :ref), socket.assigns.image_field, image, &append_image_item/2)
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns.initialized? do
      {:ok, socket}
    else
      initialize(socket)
    end
  end

  defp deliver(socket, ref, asset_field, asset, append_fun) do
    case find_pending_index(socket.assigns.items, &(&1.ref == ref)) do
      nil -> {:ok, append_fun.(socket, asset)}
      index -> {:ok, resolve_pending_item(socket, index, asset_field, asset)}
    end
  end

  defp update_item_asset(socket, nil, _asset), do: {:ok, socket}

  defp update_item_asset(socket, asset_key, asset) do
    items = socket.assigns.items
    asset_id_key = :"#{asset_key}_id"

    case Enum.find_index(
           items,
           &(Map.get(&1.source, asset_id_key) == asset.id ||
               Map.get(&1.changes, asset_id_key) == asset.id)
         ) do
      nil ->
        {:ok, socket}

      idx ->
        item = Enum.at(items, idx)

        updated_source =
          if item.is_new, do: item.source, else: Map.put(item.source, asset_key, asset)

        updated_item = %{
          item
          | source: updated_source,
            assets: Map.put(item.assets, asset_key, asset)
        }

        updated_items = List.replace_at(items, idx, updated_item)

        {:ok,
         socket
         |> assign(:items, updated_items)
         |> stream_insert(:transformer_items, stream_entry(updated_item))}
    end
  end

  # --- Initialization ---

  defp initialize(socket) do
    field = socket.assigns.field
    subform = socket.assigns.subform

    # Normalize style: {:transformer, :field} → [:field], {:transformer, [:f1, :f2]} → [:f1, :f2]
    asset_fields = normalize_asset_fields(subform.style)

    parent_schema = field.form.data.__struct__
    relation = Brando.Blueprint.Relations.__relation__(parent_schema, subform.name)
    relation_module = get_in(relation, [Access.key(:opts), Access.key(:module)])

    # Determine which asset fields are images and which are videos
    {image_field, image_cfg} = resolve_asset_field(relation_module, asset_fields, :image)
    {video_field, video_cfg} = resolve_asset_field(relation_module, asset_fields, :video)

    # Get existing items from the changeset
    existing = get_field(field.form.source, subform.name) || []

    items =
      Enum.map(existing, fn struct ->
        new_item("transformer-item-#{struct.id}", struct, is_new: false)
      end)

    stream_entries = Enum.map(items, &stream_entry/1)

    image_max_size = (image_cfg && Brando.Utils.try_path(image_cfg, [:size_limit])) || 4_000_000

    # Determine video upload strategy
    upload_strategy =
      if video_cfg do
        Map.get(video_cfg, :upload_strategy) || Brando.default_video_upload_strategy()
      else
        nil
      end

    video_upload_available? =
      video_cfg &&
        Brando.Uploads.video_upload_available?(%{video_cfg | upload_strategy: upload_strategy})

    {:ok,
     socket
     |> assign(:initialized?, true)
     |> assign(:items, items)
     |> assign(:relation_key, subform.name)
     |> assign(:image_field, image_field)
     |> assign(:video_field, video_field)
     |> assign(:image_cfg, image_cfg)
     |> assign(:video_cfg, video_cfg)
     |> assign(:asset_fields, asset_fields)
     |> assign(:relation_module, relation_module)
     |> assign(:relation_type, relation.type)
     |> assign(:sequenced?, sequenced?(relation, relation_module))
     |> assign(:upload_strategy, upload_strategy)
     |> assign(:video_upload_available?, video_upload_available?)
     |> assign(:add_entry?, Map.get(subform, :add_entry, true))
     |> assign(:layout, Map.get(subform, :layout, :list))
     |> assign(:image_max_size, image_max_size)
     |> assign(:video_max_size, video_max_size(video_cfg))
     # Without this the stream prefixes its DOM ids ("transformer_items-<id>"),
     # and every handler that looks an entry up by the dom_id the markup sent
     # back — toggle, remove, field edits, reorder — silently matches nothing.
     |> stream_configure(:transformer_items, dom_id: & &1.id)
     |> stream(:transformer_items, stream_entries)}
  end

  # Mirrors Brando.Uploads' resolution so the browser can reject an oversized
  # file before it registers a placeholder for it.
  defp video_max_size(nil), do: nil

  defp video_max_size(cfg) do
    case Map.get(cfg, :size_limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      _ -> Brando.Uploads.max_file_size()
    end
  end

  defp normalize_asset_fields({:transformer, fields}) when is_list(fields), do: fields
  defp normalize_asset_fields({:transformer, field}) when is_atom(field), do: [field]

  defp resolve_asset_field(relation_module, asset_fields, expected_type) do
    Enum.find_value(asset_fields, {nil, nil}, fn field_name ->
      asset = Brando.Blueprint.Assets.__asset__(relation_module, field_name)

      if asset && asset.type == expected_type do
        %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(relation_module, field_name)
        {field_name, cfg}
      end
    end)
  end

  defp sequenced?(relation, relation_module) do
    case relation.type do
      :has_many -> relation_module.has_trait(Brando.Trait.Sequenced)
      :embeds_many -> true
      _ -> false
    end
  end

  defp stream_entry(item) do
    %{id: item.dom_id, item: item}
  end

  # --- Render ---

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :editing_item,
        Enum.find(assigns.items, &(&1.dom_id == assigns.editing_dom_id))
      )

    ~H"""
    <fieldset>
      <Primitives.field_base
        field={@field}
        label={@label}
        instructions={@instructions}
        class="subform"
        meta_top
      >
        <div
          id={"#{@id}-uploader"}
          class="transformer-uploader"
          phx-hook="Brando.TransformerUploader"
          data-target={@myself}
          data-image-accept={@image_field && image_accept()}
          data-image-max-size={@image_field && @image_max_size}
          data-video-accept={@video_field && @video_upload_available? && video_accept()}
          data-video-max-size={@video_max_size}
          data-video-mode={video_mode(@video_field, @video_upload_available?, @upload_strategy)}
          data-video-hook-id={"#{@id}-video-uploader"}
          data-component-id={@id}
          data-config-target={
            @video_field &&
              Brando.Assets.ConfigTarget.serialize({:video, @relation_module, @video_field})
          }
          data-image-config-target={
            @image_field &&
              Brando.Assets.ConfigTarget.serialize({:image, @relation_module, @image_field})
          }
        >
          <.empty_state :if={@items == []} />
          <%!-- The sortable hook must sit on the stream container itself:
                Sortable only drags direct children, and the phx-update="stream"
                div would otherwise stand between it and the entries. --%>
          <div>
            <div
              id={"#{@id}-stream"}
              class={["transformer-entries", "layout-#{@layout}"]}
              phx-update="stream"
              phx-hook="Brando.TransformerSortable"
              data-sortable={to_string(@sequenced?)}
            >
              <div
                :for={{dom_id, entry} <- @streams.transformer_items}
                id={dom_id}
                class={[
                  "transformer-entry",
                  "subform-entry",
                  "group",
                  entry.item.pending && "pending",
                  entry.item.pending && entry.item.pending.status == :error && "failed",
                  dom_id not in @open_entries && "listing"
                ]}
                data-id={dom_id}
              >
                <div class="subform-tools">
                  <Subform.subentry_edit
                    :if={is_nil(entry.item.pending)}
                    on_click={JS.push("toggle_entry", value: %{dom_id: dom_id}, target: @myself)}
                    open={dom_id in @open_entries}
                  />
                  <button
                    type="button"
                    class="subform-delete"
                    phx-click={JS.push("remove_entry", value: %{dom_id: dom_id}, target: @myself)}
                  >
                    <.icon name="hero-x-mark" />
                  </button>
                </div>
                <.item_listing
                  item={entry.item}
                  image_field={@image_field}
                  video_field={@video_field}
                  relation_module={@relation_module}
                  subform={@subform}
                />
                <div :if={@layout == :list and dom_id in @open_entries} class="subform-fields">
                  <.item_fields
                    item={entry.item}
                    subform={@subform}
                    image_field={@image_field}
                    video_field={@video_field}
                    myself={@myself}
                    current_user={@current_user}
                  />
                </div>
              </div>
            </div>
          </div>
          <%!-- A permanent target, not a hover-only hint: drag and drop is
                invisible as an affordance unless something says so before the
                drag starts. Clicking it opens the combined picker. --%>
          <div class="transformer-dropzone" data-pick="files">
            <.icon name="hero-arrow-up-tray" />
            <span>{dropzone_label(@image_field, @video_field, @video_upload_available?)}</span>
          </div>
          <div class="actions">
            <Subform.subentry_add
              :if={@add_entry?}
              on_click={JS.push("add_entry", target: @myself)}
            />
            <.upload_button
              :if={@image_field && @video_field && @video_upload_available?}
              kind="files"
              label={gettext("Upload files")}
            />
            <.upload_button :if={@image_field} kind="images" label={gettext("Pick images")} />
            <.upload_button
              :if={@video_field && @video_upload_available?}
              kind="videos"
              label={gettext("Pick videos")}
            />
            <Subform.sort_by_filename on_click={JS.push("sort_by_filename", target: @myself)} />
          </div>
          <div
            :if={@video_field && @video_upload_available? && provider_strategy?(@upload_strategy)}
            id={"#{@id}-video-uploader"}
            phx-hook={video_uploader_hook(@upload_strategy)}
            data-target={@myself}
          />
          <.rejected_files :if={@upload_errors != []} errors={@upload_errors} myself={@myself} />

          <%!-- Grid entries are cards a couple of hundred pixels wide; an
                expanded form cannot fit inside one. Edit in a modal instead and
                leave the card showing only what it can show well. --%>
          <Content.modal
            :if={@layout == :grid}
            id={"#{@id}-entry-modal"}
            title={gettext("Edit entry")}
            medium
            show={@editing_dom_id != nil}
            close={JS.push("close_entry", target: @myself)}
          >
            <.item_fields
              :if={@editing_item}
              item={@editing_item}
              subform={@subform}
              image_field={@image_field}
              video_field={@video_field}
              myself={@myself}
              current_user={@current_user}
            />
          </Content.modal>
        </div>
      </Primitives.field_base>
    </fieldset>
    """
  end

  defp rejected_files(assigns) do
    ~H"""
    <div class="transformer-upload-errors">
      <div :for={error <- @errors} class="transformer-upload-error">
        <.icon name="hero-exclamation-triangle" />
        <span class="filename">{error.filename}</span>
        <span class="reason">{error.reason}</span>
      </div>
      <button type="button" class="tiny" phx-click={JS.push("dismiss_upload_errors", target: @myself)}>
        {gettext("Dismiss")}
      </button>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="subform-empty">&rarr; {gettext("No associated entries")}</div>
    """
  end

  # Inert markup — Brando.TransformerUploader owns the click, so a picked file
  # and a dropped file take exactly the same path. `kind` only decides which
  # extensions the OS dialog offers; everything is validated again on intake.
  defp upload_button(assigns) do
    ~H"""
    <button type="button" class="upload-button" data-pick={@kind}>
      <.icon name={upload_button_icon(@kind)} />
      {@label}
    </button>
    """
  end

  defp upload_button_icon("images"), do: "hero-photo"
  defp upload_button_icon("videos"), do: "hero-video-camera"
  defp upload_button_icon(_kind), do: "hero-arrow-up-tray"

  defp dropzone_label(_image_field, video_field, video_available?)
       when not is_nil(video_field) and video_available? do
    gettext("Drop images and videos here, or click to pick")
  end

  defp dropzone_label(image_field, _video_field, _video_available?) when not is_nil(image_field) do
    gettext("Drop images here, or click to pick")
  end

  defp dropzone_label(_image_field, _video_field, _video_available?) do
    gettext("Drop videos here, or click to pick")
  end

  defp item_listing(assigns) do
    item = assigns.item
    data = resolve_item_data(item)
    image = assigns.image_field && resolve_asset(item, data, assigns.image_field)
    video = assigns.video_field && resolve_asset(item, data, assigns.video_field)

    entry =
      listing_entry(data, assigns.relation_module, [
        {assigns.image_field, image},
        {assigns.video_field, video}
      ])

    assigns =
      assigns
      |> assign(:image, image)
      |> assign(:video, video)
      |> assign(:entry, entry)
      |> assign(:pending, item.pending)

    ~H"""
    <div :if={@pending} class="subform-listing pending-listing">
      <div class="img-sq">
        <div class="img-placeholder">
          <.icon name={if @pending.kind == :video, do: "hero-video-camera", else: "hero-photo"} />
        </div>
      </div>
      <div class="subform-listing-row">
        <div class="pending-filename">{@pending.filename}</div>
        <div :if={@pending.status == :error} class="pending-error">{@pending.error}</div>
        <div :if={@pending.status != :error} class="pending-progress">
          <div class="progress-bar">
            <div class="progress-fill" style={"width: #{@pending.progress}%"} />
          </div>
          <small>{pending_status_label(@pending)}</small>
        </div>
      </div>
    </div>
    <div :if={is_nil(@pending)} class="subform-listing">
      <%= cond do %>
        <% @image -> %>
          <div class="img-sq">
            <%= if @image.status != :unprocessed do %>
              <img src={Brando.Utils.img_url(@image, :thumb, prefix: Brando.Utils.media_url())} />
            <% else %>
              <div class="img-placeholder"><.icon name="hero-arrow-path" /></div>
            <% end %>
          </div>
        <% @video -> %>
          <div class="img-sq">
            <%= if @video.status == :ready && video_thumbnail_url(@video) do %>
              <img src={video_thumbnail_url(@video)} />
            <% else %>
              <div class="img-placeholder"><.icon name="hero-arrow-path" /></div>
            <% end %>
          </div>
        <% true -> %>
          <div class="img-sq">
            <div class="img-placeholder"><.icon name="hero-photo" /></div>
          </div>
      <% end %>
      <div class="subform-listing-row">
        <%= if @subform.listing do %>
          {Phoenix.LiveView.TagEngine.component(
            @subform.listing,
            [entry: @entry],
            {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
          )}
        <% end %>
      </div>
    </div>
    """
  end

  defp item_fields(assigns) do
    item = assigns.item
    data = resolve_item_data(item)

    changeset = change(data, item.changes)
    form = Phoenix.HTML.FormData.to_form(changeset, as: "transformer_item")

    # Asset fields get their own picker row rather than a regular input — the
    # standard image/video inputs bind to a changeset field path, and a
    # transformer item deliberately has none.
    skip_fields = [assigns.image_field, assigns.video_field] |> Enum.reject(&is_nil/1)

    assigns =
      assigns
      |> assign(:item_form, form)
      |> assign(:skip_fields, skip_fields)
      |> assign(:image_asset, assigns.image_field && resolve_asset(item, data, assigns.image_field))
      |> assign(:video_asset, assigns.video_field && resolve_asset(item, data, assigns.video_field))

    ~H"""
    <div class="transformer-assets">
      <.asset_picker
        :if={@image_field}
        kind="image"
        label={gettext("Image")}
        asset={@image_asset}
        item={@item}
        myself={@myself}
      />
      <.asset_picker
        :if={@video_field}
        kind="video"
        label={gettext("Video")}
        asset={@video_asset}
        item={@item}
        myself={@myself}
      />
    </div>
    <div
      :for={input <- @subform.sub_fields}
      :if={input.name not in @skip_fields and input.type not in [:image, :video]}
      class="field-wrapper"
    >
      <Primitives.input
        id={"#{@item.dom_id}-input-#{input.name}"}
        field={@item_form[input.name]}
        label={nil}
        instructions={nil}
        placeholder={nil}
        opts={input.opts}
        type={input.type}
        current_user={@current_user}
        target={@myself}
      />
    </div>
    """
  end

  defp asset_picker(assigns) do
    ~H"""
    <div class="transformer-asset">
      <div class="transformer-asset-label">{@label}</div>
      <div class="transformer-asset-actions">
        <button
          type="button"
          class="tiny"
          phx-click={
            JS.push("pick_asset",
              value: %{dom_id: @item.dom_id, kind: @kind},
              target: @myself
            )
            |> toggle_drawer("##{@kind}-picker")
          }
        >
          {if @asset, do: gettext("Replace"), else: gettext("Select")}
        </button>
        <button
          :if={@asset}
          type="button"
          class="tiny asset-remove"
          phx-click={JS.push("clear_asset", value: %{dom_id: @item.dom_id, kind: @kind}, target: @myself)}
        >
          {gettext("Remove")}
        </button>
      </div>
    </div>
    """
  end

  # --- Events ---

  # Grid entries edit in a modal, so "open" is a single entry rather than a set.
  def handle_event("toggle_entry", %{"dom_id" => dom_id}, %{assigns: %{layout: :grid}} = socket) do
    editing = if socket.assigns.editing_dom_id == dom_id, do: nil, else: dom_id
    {:noreply, assign(socket, :editing_dom_id, editing)}
  end

  def handle_event("close_entry", _, socket) do
    {:noreply, assign(socket, :editing_dom_id, nil)}
  end

  def handle_event("toggle_entry", %{"dom_id" => dom_id}, socket) do
    open = socket.assigns.open_entries

    updated =
      if MapSet.member?(open, dom_id) do
        MapSet.delete(open, dom_id)
      else
        MapSet.put(open, dom_id)
      end

    socket = assign(socket, :open_entries, updated)

    # Entries render inside a stream, so assigning open_entries is not enough —
    # LiveView only re-renders a stream item that is re-inserted. Without this
    # the expand toggle changes state the DOM never hears about.
    socket =
      case Enum.find(socket.assigns.items, &(&1.dom_id == dom_id)) do
        nil -> socket
        item -> stream_insert(socket, :transformer_items, stream_entry(item))
      end

    {:noreply, socket}
  end

  def handle_event("add_entry", _, socket) do
    subform = socket.assigns.subform
    entry_data = resolve_parent_entry(socket)
    default_map = build_default(subform, socket.assigns.relation_module, entry_data, nil)
    dom_id = "transformer-item-new-#{System.unique_integer([:positive])}"

    item = new_item(dom_id, default_map)

    {:noreply,
     socket
     |> update(:items, &(&1 ++ [item]))
     |> stream_insert(:transformer_items, stream_entry(item))
     |> notify_relation_change()}
  end

  # The client has sorted the batch by filename and validated it against the
  # configs advertised on the hook element. Placeholders go in immediately so
  # the whole drop is visible — and ordered — before a single byte lands.
  def handle_event("register_batch", %{"files" => files}, socket) when is_list(files) do
    subform = socket.assigns.subform
    relation_module = socket.assigns.relation_module
    entry_data = resolve_parent_entry(socket)

    placeholders =
      files
      |> Enum.map(&build_placeholder(&1, subform, relation_module, entry_data))
      |> Enum.reject(&is_nil/1)

    socket =
      Enum.reduce(placeholders, socket, fn item, acc ->
        acc
        |> update(:items, &(&1 ++ [item]))
        |> stream_insert(:transformer_items, stream_entry(item))
      end)

    {:noreply, socket}
  end

  # Files the browser refused before registering them (wrong type, too large).
  def handle_event("reject_files", %{"files" => files}, socket) when is_list(files) do
    rejected =
      Enum.map(files, fn file ->
        %{filename: to_string(file["filename"]), reason: to_string(file["reason"])}
      end)

    {:noreply, update(socket, :upload_errors, &(&1 ++ rejected))}
  end

  def handle_event("dismiss_upload_errors", _, socket) do
    {:noreply, assign(socket, :upload_errors, [])}
  end

  # --- Asset selection ---
  #
  # Transformer items live outside the parent changeset, so the regular asset
  # inputs cannot bind to them. The pickers can: they take an arbitrary
  # event_target, and the selection is written into the item exactly the way an
  # upload writes into it.

  def handle_event("pick_asset", %{"dom_id" => dom_id, "kind" => "image"}, socket) do
    relation_module = socket.assigns.relation_module
    image_field = socket.assigns.image_field
    selected = current_asset_id(socket, dom_id, image_field)

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: {"image", relation_module, image_field},
      event_target: socket.assigns.myself,
      multi: false,
      selected_images: List.wrap(selected)
    )

    {:noreply, assign(socket, :picking_dom_id, dom_id)}
  end

  def handle_event("pick_asset", %{"dom_id" => dom_id, "kind" => "video"}, socket) do
    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      config_target: {"video", socket.assigns.relation_module, socket.assigns.video_field},
      event_target: socket.assigns.myself,
      multi: false
    )

    {:noreply, assign(socket, :picking_dom_id, dom_id)}
  end

  def handle_event("clear_asset", %{"dom_id" => dom_id, "kind" => kind}, socket) do
    field = asset_field_for(socket, kind)

    case Enum.find_index(socket.assigns.items, &(&1.dom_id == dom_id)) do
      nil -> {:noreply, socket}
      index -> {:noreply, put_item_asset(socket, index, field, nil)}
    end
  end

  def handle_event("select_image", %{"id" => id}, socket) do
    with {:ok, image} <- Brando.Images.get_image(id) do
      {:noreply, select_asset(socket, socket.assigns.image_field, image)}
    else
      _error -> {:noreply, socket}
    end
  end

  def handle_event("select_video", %{"id" => id}, socket) do
    with {:ok, video} <- Brando.Videos.get_video(id) do
      {:noreply, select_asset(socket, socket.assigns.video_field, video)}
    else
      _error -> {:noreply, socket}
    end
  end

  def handle_event("remove_entry", %{"dom_id" => dom_id}, socket) do
    items = socket.assigns.items

    case Enum.find(items, &(&1.dom_id == dom_id)) do
      nil ->
        {:noreply, socket}

      item ->
        updated_items = Enum.reject(items, &(&1.dom_id == dom_id))

        {:noreply,
         socket
         |> assign(:items, updated_items)
         |> stream_delete(:transformer_items, stream_entry(item))
         |> maybe_abort_pending_upload(item)
         |> notify_relation_change()}
    end
  end

  def handle_event("sort_by_filename", _, socket) do
    items = socket.assigns.items
    image_field = socket.assigns.image_field

    sorted =
      Enum.sort_by(items, fn item ->
        data = resolve_item_data(item)

        if image_field do
          image = Map.get(data, image_field)
          (image && Map.get(image, :path, "")) || ""
        else
          ""
        end
      end)

    {:noreply,
     socket
     |> assign(:items, sorted)
     |> stream(:transformer_items, Enum.map(sorted, &stream_entry/1), reset: true)
     |> notify_relation_change()}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices}, socket) do
    items = socket.assigns.items

    ordered =
      order_indices
      |> Enum.map(fn dom_id -> Enum.find(items, &(&1.dom_id == dom_id)) end)
      |> Enum.reject(&is_nil/1)

    # Anything the client did not name keeps its place at the end rather than
    # being dropped. A reorder is a reorder — an id that fails to match must
    # never be able to delete an entry, let alone all of them.
    unnamed = Enum.reject(items, &(&1 in ordered))
    reordered = ordered ++ unnamed

    {:noreply,
     socket
     |> assign(:items, reordered)
     |> stream(:transformer_items, Enum.map(reordered, &stream_entry/1), reset: true)
     |> notify_relation_change()}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event(
        "update_field",
        %{"dom_id" => dom_id, "field" => field, "value" => value},
        socket
      ) do
    field_atom =
      try do
        String.to_existing_atom(field)
      rescue
        ArgumentError -> nil
      end

    if is_nil(field_atom) do
      {:noreply, socket}
    else
      items = socket.assigns.items

      case Enum.find_index(items, &(&1.dom_id == dom_id)) do
        nil ->
          {:noreply, socket}

        idx ->
          item = Enum.at(items, idx)
          updated_changes = Map.put(item.changes, field_atom, value)
          updated_item = %{item | changes: updated_changes}
          updated_items = List.replace_at(items, idx, updated_item)

          {:noreply,
           socket
           |> assign(:items, updated_items)
           |> stream_insert(:transformer_items, stream_entry(updated_item))}
      end
    end
  end

  # --- Video upload events (from MuxUploader/BunnyUploader JS hooks) ---

  def handle_event(
        "get_video_upload_url",
        %{
          "request_ref" => request_ref,
          "filename" => filename,
          "size" => size,
          "mime_type" => mime_type
        },
        socket
      ) do
    user = socket.assigns.current_user
    video_field = socket.assigns.video_field
    relation_module = socket.assigns.relation_module
    video_cfg = socket.assigns.video_cfg

    config_target = Brando.Assets.ConfigTarget.serialize({:video, relation_module, video_field})

    case Brando.Videos.Uploader.initiate_upload(filename, user,
           config: video_cfg,
           config_target: config_target,
           file_meta: %{name: filename, size: size, type: mime_type}
         ) do
      {:ok, %{upload_url: url, video: video} = result} ->
        Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:video:#{video.id}", link: true)

        subform = socket.assigns.subform
        entry_data = resolve_parent_entry(socket)

        video_id_key = :"#{video_field}_id"

        # The Video row exists now, but the transfer is what takes time — the
        # placeholder keeps its progress bar until the browser reports success.
        socket =
          case find_pending_index(socket.assigns.items, &(&1.ref == request_ref)) do
            nil ->
              default_map =
                subform
                |> build_default(relation_module, entry_data, nil)
                |> Map.put(video_id_key, video.id)

              item = new_item(new_item_dom_id(), default_map)

              socket
              |> update(:items, &(&1 ++ [item]))
              |> stream_insert(:transformer_items, stream_entry(item))

            index ->
              update_item(socket, index, fn item ->
                %{
                  item
                  | source: Map.put(item.source, video_id_key, video.id),
                    pending: %{item.pending | status: :uploading}
                }
              end)
          end

        event_payload =
          %{
            upload_url: url,
            video_id: video.id,
            filename: filename,
            request_ref: request_ref
          }
          |> maybe_add_tus_auth(result)

        {:noreply, push_event(socket, "video_upload_url_ready", event_payload)}

      {:error, reason} ->
        message = upload_error_message(reason)

        {:noreply,
         socket
         |> fail_pending_upload(request_ref, message)
         |> push_event("video_upload_url_error", %{
           error: message,
           filename: filename,
           request_ref: request_ref
         })}
    end
  end

  def handle_event("get_video_upload_url", params, socket) do
    {:noreply,
     push_event(socket, "video_upload_url_error", %{
       error: "Invalid video upload request",
       filename: Map.get(params, "filename", ""),
       request_ref: Map.get(params, "request_ref", "")
     })}
  end

  def handle_event("video_upload_complete", %{"video_id" => video_id} = params, socket) do
    # Video uploaded to provider. The item was already created in
    # get_video_upload_url. Status updates arrive via PubSub when the webhook
    # fires, so the placeholder can retire here.
    with {:ok, video} <- Brando.Videos.get_video(video_id) do
      Brando.Videos.Uploader.complete_client_upload(video)
    end

    {:noreply, clear_pending_upload(socket, Map.get(params, "request_ref"))}
  end

  def handle_event(
        "video_upload_progress",
        %{"request_ref" => request_ref, "percentage" => percentage},
        socket
      ) do
    {:noreply, progress_pending_upload(socket, request_ref, percentage)}
  end

  def handle_event("upload_error", %{"error" => error} = params, socket) do
    # The failed placeholder carries the filename and the reason, so a batch of
    # thirty does not reduce to one anonymous alert.
    {:noreply, fail_pending_upload(socket, Map.get(params, "request_ref"), error)}
  end

  # Catch-all for unused events from child components
  def handle_event("focus", _, socket), do: {:noreply, socket}
  def handle_event("blur", _, socket), do: {:noreply, socket}
  def handle_event("reposition", _, socket), do: {:noreply, socket}

  # Video PubSub updates are routed via live_view/form.ex hooks → update(%{event: "video_updated"})

  # --- Image upload handling ---

  # --- Items ---

  # The single definition of an item's shape. Every construction site goes
  # through here: hand-written literals drift, and a missing key surfaces as a
  # KeyError from deep inside render rather than anywhere near the cause.
  #
  # - `source`   the struct (existing row) or map (unsaved) the entry wraps
  # - `changes`  inline field edits, merged over source at save
  # - `pending`  upload placeholder state, or nil once the asset lands
  # - `assets`   render-only resolved assets; never merged into save data
  @doc false
  def new_item(dom_id, source, opts \\ []) do
    %{
      dom_id: dom_id,
      source: source,
      changes: %{},
      is_new: Keyword.get(opts, :is_new, true),
      pending: Keyword.get(opts, :pending),
      assets: Keyword.get(opts, :assets, %{})
    }
  end

  defp new_item_dom_id, do: "transformer-item-new-#{System.unique_integer([:positive])}"

  # --- Placeholder helpers ---

  # A placeholder is an ordinary item carrying a `pending` map. It renders as a
  # queued card, is skipped at save time, and becomes a real item the moment its
  # asset id lands — the position it was given on drop never changes.
  @doc false
  def build_placeholder(%{"ref" => ref, "filename" => filename} = file, subform, relation_module, entry_data)
      when is_binary(ref) and is_binary(filename) do
    if valid_ref?(ref) do
      new_item("transformer-item-pending-#{ref}", build_default(subform, relation_module, entry_data, nil),
        pending: %{
          ref: ref,
          filename: filename,
          size: parse_size(Map.get(file, "size")),
          kind: if(Map.get(file, "kind") == "video", do: :video, else: :image),
          status: :waiting,
          progress: 0,
          error: nil
        }
      )
    end
  end

  def build_placeholder(_file, _subform, _relation_module, _entry_data), do: nil

  # Same charset as Brando.Uploads.AssetIntent — this reaches the DOM as an id.
  defp valid_ref?(ref), do: Regex.match?(~r/^[A-Za-z0-9_-]{1,64}$/, ref)

  defp parse_size(size) when is_integer(size), do: size
  defp parse_size(_), do: nil

  @doc false
  # What a `listing:` component receives as `entry`.
  #
  # An unsaved item carries a plain map as its source, because that map is what
  # `put_assoc` casts at save time — but a listing component should never have to
  # know that. It always gets a struct of the related schema, with the resolved
  # assets attached, so `entry.image` works the same for a row loaded from the
  # database and a file dropped a second ago.
  def listing_entry(data, relation_module, assets) do
    entry = if is_struct(data), do: data, else: struct(relation_module, data)

    Enum.reduce(assets, entry, fn
      {nil, _asset}, acc -> acc
      {field, asset}, acc -> Map.put(acc, field, asset)
    end)
  end

  # An item's asset can come from three places: a preloaded association on an
  # existing row, an upload delivery, or a picker selection. The last two land in
  # `assets`, which therefore wins — including when it holds an explicit nil from
  # a cleared field.
  defp resolve_asset(item, data, field) do
    case Map.fetch(item.assets, field) do
      {:ok, asset} -> asset
      :error -> Map.get(data, field)
    end
  end

  defp asset_field_for(socket, "image"), do: socket.assigns.image_field
  defp asset_field_for(socket, "video"), do: socket.assigns.video_field

  defp current_asset_id(socket, dom_id, field) do
    socket.assigns.items
    |> Enum.find(&(&1.dom_id == dom_id))
    |> case do
      nil -> nil
      item -> item |> resolve_item_data() |> Map.get(:"#{field}_id")
    end
  end

  # A picked asset lands on the item the same way an uploaded one does, so both
  # routes converge on one shape at save time.
  defp select_asset(socket, nil, _asset), do: socket

  defp select_asset(%{assigns: %{picking_dom_id: nil}} = socket, _field, _asset), do: socket

  defp select_asset(socket, field, asset) do
    dom_id = socket.assigns.picking_dom_id

    case Enum.find_index(socket.assigns.items, &(&1.dom_id == dom_id)) do
      nil -> assign(socket, :picking_dom_id, nil)
      index -> socket |> put_item_asset(index, field, asset) |> assign(:picking_dom_id, nil)
    end
  end

  # Existing rows keep an Ecto struct as their source, so the association has to
  # be written alongside the id or the listing keeps showing the old asset.
  defp put_item_asset(socket, index, field, asset) do
    socket
    |> do_put_item_asset(index, field, asset)
    |> notify_relation_change()
  end

  defp do_put_item_asset(socket, index, field, asset) do
    update_item(socket, index, fn item ->
      id = asset && asset.id

      %{
        item
        | source: Map.put(item.source, :"#{field}_id", id),
          changes: Map.put(item.changes, :"#{field}_id", id),
          assets: Map.put(item.assets, field, asset)
      }
    end)
  end

  defp find_pending_index(items, fun) do
    Enum.find_index(items, fn item -> item.pending && fun.(item.pending) end)
  end

  defp update_item(socket, index, fun) do
    items = socket.assigns.items
    updated_item = items |> Enum.at(index) |> fun.()

    socket
    |> assign(:items, List.replace_at(items, index, updated_item))
    |> stream_insert(:transformer_items, stream_entry(updated_item))
  end

  defp resolve_pending_item(socket, index, asset_field, asset) do
    socket
    |> do_resolve_pending_item(index, asset_field, asset)
    |> notify_relation_change()
  end

  defp do_resolve_pending_item(socket, index, asset_field, asset) do
    update_item(socket, index, fn item ->
      %{
        item
        | source: Map.put(item.source, :"#{asset_field}_id", asset.id),
          assets: Map.put(item.assets, asset_field, asset),
          pending: nil
      }
    end)
  end

  defp clear_pending_upload(socket, ref) do
    case find_pending_index(socket.assigns.items, &(&1.ref == ref)) do
      nil -> socket
      index -> update_item(socket, index, &%{&1 | pending: nil})
    end
  end

  defp progress_pending_upload(socket, ref, percentage) do
    case find_pending_index(socket.assigns.items, &(&1.ref == ref)) do
      nil ->
        socket

      index ->
        update_item(socket, index, fn item ->
          %{item | pending: %{item.pending | status: :uploading, progress: clamp(percentage)}}
        end)
    end
  end

  defp fail_pending_upload(socket, ref, message) do
    case find_pending_index(socket.assigns.items, &(&1.ref == ref)) do
      nil -> alert_upload_failure(socket, message)
      index -> mark_failed(socket, index, message)
    end
  end

  defp mark_failed(socket, index, message) do
    update_item(socket, index, fn item ->
      %{item | pending: %{item.pending | status: :error, error: message}}
    end)
  end

  # No placeholder to attach the failure to — fall back to a toast rather than
  # letting it disappear.
  defp alert_upload_failure(socket, message) do
    push_event(socket, "b:alert", %{
      title: gettext("Upload failed"),
      message: message,
      type: "error"
    })
  end

  defp maybe_abort_pending_upload(socket, %{pending: %{ref: ref}}) do
    push_event(socket, "transformer:abort_upload", %{ref: ref})
  end

  defp maybe_abort_pending_upload(socket, _item), do: socket

  # The transformer deliberately keeps its items out of the parent changeset
  # until save — but live preview renders from the form's entry, so without this
  # it shows the relation as it was on mount. Push the current list whenever the
  # list itself changes (order, membership, assets); not on progress ticks.
  defp notify_relation_change(socket) do
    form_id = socket.assigns[:form_id]

    if form_id do
      send_update(BrandoAdmin.Components.Form,
        id: form_id,
        event: "update_entry_relation",
        path: [socket.assigns.relation_key],
        updated_relation: relation_entries(socket)
      )
    end

    socket
  end

  # Placeholders carry no asset yet, so they would render as holes in the
  # preview. They are excluded here for the same reason they are at save time.
  defp relation_entries(socket) do
    image_field = socket.assigns.image_field
    video_field = socket.assigns.video_field
    relation_module = socket.assigns.relation_module

    socket.assigns.items
    |> Enum.reject(& &1.pending)
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      data = resolve_item_data(item)

      data
      |> listing_entry(relation_module, [
        {image_field, image_field && resolve_asset(item, data, image_field)},
        {video_field, video_field && resolve_asset(item, data, video_field)}
      ])
      |> Map.put(:sequence, index)
    end)
  end

  defp maybe_warn_about_pending(socket, []), do: socket

  defp maybe_warn_about_pending(socket, pending) do
    push_event(socket, "b:alert", %{
      title: gettext("Uploads still running"),
      message: gettext("%{count} upload(s) had not finished and were not saved.", count: length(pending)),
      type: "warning"
    })
  end

  defp clamp(percentage) when is_number(percentage), do: percentage |> max(0) |> min(100) |> round()
  defp clamp(_), do: 0

  defp pending_status_label(%{status: :waiting}), do: gettext("Waiting…")
  defp pending_status_label(%{status: :uploading, progress: progress}), do: "#{progress}%"
  defp pending_status_label(_pending), do: gettext("Uploading…")

  # Delegated rather than duplicated: `Brando.Uploads` owns the text, because
  # the picker and the video drawer report the same failures on the same
  # channel. The clauses that used to live here are its tail — what it adds is
  # a fixed string for the error atoms this file used to render with
  # `to_string/1`, which is how `provider_not_configured` reached an editor.
  defp upload_error_message(reason), do: Brando.Uploads.video_upload_error_message(reason)

  # --- Helpers ---

  defp resolve_item_data(%{source: source, changes: changes, is_new: false}) do
    struct(source.__struct__, Map.merge(Map.from_struct(source), changes))
  end

  defp resolve_item_data(%{source: source, changes: changes, is_new: true}) do
    Map.merge(source, changes)
  end

  defp resolve_parent_entry(socket) do
    changeset = socket.assigns.field.form.source
    Ecto.Changeset.apply_changes(changeset)
  end

  defp append_video_item(socket, video), do: append_asset_item(socket, socket.assigns.video_field, video)

  defp append_image_item(socket, image), do: append_asset_item(socket, socket.assigns.image_field, image)

  # A delivery with no placeholder to fill — an upload the batch never
  # registered. Append it rather than dropping the asset on the floor.
  defp append_asset_item(socket, nil, _asset), do: socket

  defp append_asset_item(socket, asset_field, asset) do
    default_map =
      socket.assigns.subform
      |> build_default(
        socket.assigns.relation_module,
        resolve_parent_entry(socket),
        asset
      )
      |> Map.put(:"#{asset_field}_id", asset.id)

    item = new_item(new_item_dom_id(), default_map)

    socket
    |> update(:items, &(&1 ++ [item]))
    |> stream_insert(:transformer_items, stream_entry(item))
    |> notify_relation_change()
  end

  @doc false
  def build_default(%{default: nil}, relation_module, _entry, _asset) do
    relation_module
    |> struct()
    |> to_insertable_map()
  end

  def build_default(%{default: default}, _relation_module, entry, asset) when is_function(default, 2) do
    default
    |> then(& &1.(entry, asset))
    |> to_insertable_map()
  end

  def build_default(%{default: default}, _relation_module, _entry, _asset) do
    to_insertable_map(default)
  end

  defp to_insertable_map(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__, :id])
    |> Enum.reject(fn {_k, v} -> match?(%Ecto.Association.NotLoaded{}, v) end)
    |> Map.new()
  end

  defp to_insertable_map(map) when is_map(map), do: map

  defp to_insertable_map(default) do
    raise ArgumentError,
          "Blueprint transformer default must return a map or struct, got: #{inspect(default)}"
  end

  defp video_uploader_hook(:mux), do: "Brando.MuxUploader"
  defp video_uploader_hook(:bunny), do: "Brando.BunnyUploader"
  defp video_uploader_hook(:cloudflare), do: "Brando.CloudflareUploader"
  defp video_uploader_hook(_strategy), do: nil

  defp provider_strategy?(strategy), do: not is_nil(video_uploader_hook(strategy))

  # How the drop-zone hook should route video files: straight to the provider
  # hook, into the sticky UploadManager, or nowhere at all.
  defp video_mode(nil, _available?, _strategy), do: "none"
  defp video_mode(_field, false, _strategy), do: "none"

  defp video_mode(_field, _available?, strategy) do
    if provider_strategy?(strategy), do: "provider", else: "manager"
  end

  defp image_accept, do: Enum.join(@image_extensions, ",")
  defp video_accept, do: Enum.join(@video_extensions, ",")

  defp video_thumbnail_url(%{meta: %{"mux" => %{"playback_policy" => "signed"}}}), do: nil

  defp video_thumbnail_url(%{meta: %{"mux" => %{"playback_id" => playback_id}}}) do
    "https://image.mux.com/#{playback_id}/thumbnail.jpg?width=120&height=120&fit_mode=smartcrop"
  end

  defp video_thumbnail_url(%Brando.Videos.Video{} = video) do
    Brando.Videos.Helpers.thumbnail_url(video)
  end

  defp video_thumbnail_url(%{thumbnail: %Brando.Images.Image{} = thumb}) do
    Brando.Utils.img_url(thumb, :thumb, prefix: Brando.Utils.media_url())
  end

  defp video_thumbnail_url(_), do: nil

  defp maybe_add_tus_auth(payload, %{tus_auth: tus_auth}), do: Map.put(payload, :tus_auth, tus_auth)
  defp maybe_add_tus_auth(payload, _), do: payload
end
