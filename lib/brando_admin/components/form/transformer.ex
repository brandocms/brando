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

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Subform

  import Ecto.Changeset, only: [change: 2, get_field: 2]

  use Gettext, backend: Brando.Gettext

  @image_extensions ~w(.jpg .jpeg .png .gif .webp .svg)

  def mount(socket) do
    {:ok,
     socket
     |> assign(:initialized?, false)
     |> assign(:items, [])
     |> assign(:open_entries, MapSet.new())
     |> assign(:processing, false)
     |> assign(:upload_progress, nil)}
  end

  # --- Update handlers ---

  def update(%{event: "fetch_transformer_data", tag: tag}, socket) do
    items = socket.assigns.items
    relation_key = socket.assigns.relation_key
    form_id = socket.assigns.form_id

    # Build save-time data: changesets for existing records, maps for new
    save_data =
      items
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

    {:ok, socket}
  end

  def update(%{event: "image_updated", image: image}, socket) do
    update_item_asset(socket, socket.assigns.image_field, image)
  end

  def update(%{event: "video_updated", video: video}, socket) do
    update_item_asset(socket, socket.assigns.video_field, video)
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns.initialized? do
      {:ok, socket}
    else
      initialize(socket)
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

        updated_item = %{item | source: updated_source}
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
        %{
          dom_id: "transformer-item-#{struct.id}",
          source: struct,
          changes: %{},
          is_new: false
        }
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
     |> stream(:transformer_items, stream_entries)
     |> maybe_allow_image_upload(image_field, image_max_size)
     |> maybe_allow_video_upload(video_field)}
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

  defp maybe_allow_image_upload(socket, nil, _max_size), do: socket

  defp maybe_allow_image_upload(socket, _image_field, max_size) do
    allow_upload(socket, :transformer_images,
      accept: @image_extensions,
      max_entries: 50,
      max_file_size: max_size,
      chunk_timeout: 60_000,
      auto_upload: true,
      progress: &handle_image_upload_progress/3
    )
  end

  defp maybe_allow_video_upload(socket, nil), do: socket

  defp maybe_allow_video_upload(socket, _video_field) do
    # Video uploads bypass LiveView upload — handled by MuxUploader/BunnyUploader hooks.
    # We register a dummy upload to satisfy LiveView's upload tracking.
    socket
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
    ~H"""
    <fieldset>
      <Form.field_base
        field={@field}
        label={@label}
        instructions={@instructions}
        class="subform"
        meta_top
      >
        <div
          id={"#{@id}-sortable"}
          phx-hook="Brando.SortableEmbeds"
          data-sortable-handle=".subform-handle"
          data-sortable-id={"#{@id}-sortable"}
          data-sortable-selector=".transformer-entry"
        >
          <.empty_state :if={@items == []} />
          <div id={"#{@id}-stream"} phx-update="stream">
            <div
              :for={{dom_id, entry} <- @streams.transformer_items}
              id={dom_id}
              class={[
                "transformer-entry",
                "subform-entry",
                "group",
                dom_id not in @open_entries && "listing"
              ]}
              data-id={dom_id}
            >
              <div class="subform-tools">
                <Subform.subentry_edit
                  on_click={JS.push("toggle_entry", value: %{dom_id: dom_id}, target: @myself)}
                  open={dom_id in @open_entries}
                />
                <Subform.subentry_sequence :if={@sequenced?} />
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
                subform={@subform}
              />
              <div :if={dom_id in @open_entries} class="subform-fields">
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
        <div class="actions">
          <Subform.subentry_add on_click={JS.push("add_entry", target: @myself)} />
          <.image_upload_button :if={@image_field} upload={@uploads.transformer_images} />
          <.video_upload_button
            :if={@video_field && @upload_strategy && @upload_strategy != :local}
            upload_strategy={@upload_strategy}
            id={@id}
            myself={@myself}
          />
          <Subform.sort_by_filename on_click={JS.push("sort_by_filename", target: @myself)} />
        </div>
        <.upload_progress :if={@upload_progress} progress={@upload_progress} />
      </Form.field_base>
    </fieldset>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="subform-empty">&rarr; {gettext("No associated entries")}</div>
    """
  end

  defp image_upload_button(assigns) do
    ~H"""
    <label class="upload-button">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="16"
        height="16"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
      </svg>
      {gettext("Pick images")}
      <.live_file_input upload={@upload} />
    </label>
    """
  end

  defp video_upload_button(assigns) do
    ~H"""
    <div
      id={"#{@id}-video-uploader"}
      phx-hook={video_uploader_hook(@upload_strategy)}
      data-target={@myself}
    >
      <label class="upload-button">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="16"
          height="16"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="m15.75 10.5 4.72-4.72a.75.75 0 0 1 1.28.53v11.38a.75.75 0 0 1-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 0 0 2.25-2.25v-9a2.25 2.25 0 0 0-2.25-2.25h-9A2.25 2.25 0 0 0 2.25 7.5v9a2.25 2.25 0 0 0 2.25 2.25Z"
          />
        </svg>
        {gettext("Pick videos")}
        <input type="file" accept="video/*" class="video-picker-file-input hidden" />
      </label>
    </div>
    """
  end

  defp upload_progress(assigns) do
    ~H"""
    <div class="upload-progress">
      <div class="progress-bar">
        <div class="progress-fill" data-progress={@progress.percentage} />
      </div>
      <small>{@progress.uploaded_mb}MB / {@progress.total_mb}MB ({@progress.percentage}%)</small>
    </div>
    """
  end

  defp item_listing(assigns) do
    item = assigns.item
    data = resolve_item_data(item)
    image = assigns.image_field && Map.get(data, assigns.image_field)
    video = assigns.video_field && Map.get(data, assigns.video_field)

    assigns =
      assigns
      |> assign(:image, image)
      |> assign(:video, video)
      |> assign(:entry, data)

    ~H"""
    <div class="subform-listing">
      <%= cond do %>
        <% @image -> %>
          <div class="img-sq">
            <%= if @image.status != :unprocessed do %>
              <img src={Brando.Utils.img_url(@image, :thumb)} />
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

    # Filter out asset fields — they're not editable inline
    skip_fields = [assigns.image_field, assigns.video_field] |> Enum.reject(&is_nil/1)

    assigns =
      assigns
      |> assign(:item_form, form)
      |> assign(:skip_fields, skip_fields)

    ~H"""
    <div
      :for={input <- @subform.sub_fields}
      :if={input.name not in @skip_fields and input.type not in [:image, :video]}
      class="field-wrapper"
    >
      <Form.input
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

  # --- Events ---

  def handle_event("toggle_entry", %{"dom_id" => dom_id}, socket) do
    open = socket.assigns.open_entries

    updated =
      if MapSet.member?(open, dom_id) do
        MapSet.delete(open, dom_id)
      else
        MapSet.put(open, dom_id)
      end

    {:noreply, assign(socket, :open_entries, updated)}
  end

  def handle_event("add_entry", _, socket) do
    subform = socket.assigns.subform
    entry_data = resolve_parent_entry(socket)
    default_map = build_default(subform, socket.assigns.relation_module, entry_data, nil)
    dom_id = "transformer-item-new-#{System.unique_integer([:positive])}"

    item = %{
      dom_id: dom_id,
      source: default_map,
      changes: %{},
      is_new: true
    }

    {:noreply,
     socket
     |> update(:items, &(&1 ++ [item]))
     |> stream_insert(:transformer_items, stream_entry(item))}
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
         |> stream_delete(:transformer_items, stream_entry(item))}
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
     |> stream(:transformer_items, Enum.map(sorted, &stream_entry/1), reset: true)}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices}, socket) do
    items = socket.assigns.items

    reordered =
      order_indices
      |> Enum.map(fn dom_id -> Enum.find(items, &(&1.dom_id == dom_id)) end)
      |> Enum.reject(&is_nil/1)

    {:noreply,
     socket
     |> assign(:items, reordered)
     |> stream(:transformer_items, Enum.map(reordered, &stream_entry/1), reset: true)}
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

  def handle_event("get_video_upload_url", %{"filename" => filename}, socket) do
    user = socket.assigns.current_user
    video_field = socket.assigns.video_field
    relation_module = socket.assigns.relation_module
    video_cfg = socket.assigns.video_cfg

    config_target = Brando.Assets.ConfigTarget.serialize({:video, relation_module, video_field})

    case Brando.Videos.Uploader.initiate_upload(filename, user,
           config: video_cfg,
           config_target: config_target
         ) do
      {:ok, %{upload_url: url, video: video} = result} ->
        Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:video:#{video.id}", link: true)

        subform = socket.assigns.subform
        entry_data = resolve_parent_entry(socket)

        video_id_key = :"#{video_field}_id"

        default_map =
          subform
          |> build_default(relation_module, entry_data, nil)
          |> Map.put(video_id_key, video.id)

        dom_id = "transformer-item-new-#{System.unique_integer([:positive])}"

        item = %{
          dom_id: dom_id,
          source: default_map,
          changes: %{},
          is_new: true
        }

        event_payload =
          %{upload_url: url, video_id: video.id, filename: filename}
          |> maybe_add_tus_auth(result)

        {:noreply,
         socket
         |> update(:items, &(&1 ++ [item]))
         |> stream_insert(:transformer_items, stream_entry(item))
         |> push_event("video_upload_url_ready", event_payload)}

      {:error, reason} ->
        require Logger
        Logger.error("Failed to get video upload URL: #{inspect(reason)}")

        {:noreply,
         push_event(socket, "video_upload_url_error", %{
           error: "Failed to initiate video upload",
           filename: filename
         })}
    end
  end

  def handle_event("video_upload_complete", %{"video_id" => _video_id}, socket) do
    # Video uploaded to provider. The MediaItem was already created in get_video_upload_url.
    # Status updates will come via PubSub when the webhook fires.
    {:noreply, assign(socket, :upload_progress, nil)}
  end

  def handle_event(
        "video_upload_progress",
        %{
          "video_id" => _video_id,
          "uploaded_mb" => uploaded_mb,
          "total_mb" => total_mb,
          "percentage" => percentage
        },
        socket
      ) do
    progress = %{uploaded_mb: uploaded_mb, total_mb: total_mb, percentage: percentage}
    {:noreply, assign(socket, :upload_progress, progress)}
  end

  def handle_event("upload_error", %{"filename" => filename, "error" => error}, socket) do
    require Logger
    Logger.error("Upload error for #{filename}: #{error}")

    {:noreply,
     socket
     |> assign(:upload_progress, nil)
     |> push_event("b:alert", %{
       title: gettext("Upload failed"),
       message: "#{filename}: #{error}",
       type: "error"
     })}
  end

  # Catch-all for unused events from child components
  def handle_event("focus", _, socket), do: {:noreply, socket}
  def handle_event("blur", _, socket), do: {:noreply, socket}
  def handle_event("reposition", _, socket), do: {:noreply, socket}

  # Video PubSub updates are routed via live_view/form.ex hooks → update(%{event: "video_updated"})

  # --- Image upload handling ---

  defp handle_image_upload_progress(:transformer_images, entry, socket) do
    if entry.done? do
      handle_completed_image_upload(entry, socket)
    else
      {:noreply, assign(socket, :processing, entry.progress)}
    end
  end

  defp handle_completed_image_upload(entry, socket) do
    current_user = socket.assigns.current_user
    relation_module = socket.assigns.relation_module
    image_field = socket.assigns.image_field
    image_cfg = socket.assigns.image_cfg
    subform = socket.assigns.subform

    config_target = Brando.Assets.ConfigTarget.serialize({:image, relation_module, image_field})

    case consume_uploaded_entry(
           socket,
           entry,
           fn meta ->
             Brando.Upload.handle_upload(
               Map.put(meta, :config_target, config_target),
               entry,
               image_cfg,
               current_user
             )
           end
         ) do
      {:upload_error, reason} ->
        {:noreply,
         socket
         |> assign(:processing, false)
         |> push_event("b:alert", %{
           title: "Upload failed",
           message: inspect(reason),
           type: "error"
         })}

      image ->
        Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}", link: true)

        Brando.Images.Processing.queue_processing(
          image,
          current_user,
          {:transformer, socket.assigns.relation_key, image_field, image.id}
        )

        entry_data = resolve_parent_entry(socket)

        image_id_key = :"#{image_field}_id"

        default_map =
          subform
          |> build_default(relation_module, entry_data, image)
          |> Map.put(image_id_key, image.id)

        dom_id = "transformer-item-new-#{System.unique_integer([:positive])}"

        item = %{
          dom_id: dom_id,
          source: default_map,
          changes: %{},
          is_new: true
        }

        {:noreply,
         socket
         |> assign(:processing, false)
         |> update(:items, &(&1 ++ [item]))
         |> stream_insert(:transformer_items, stream_entry(item))}
    end
  end

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
  defp video_uploader_hook(strategy), do: "Brando.#{strategy |> to_string() |> String.capitalize()}Uploader"

  defp video_thumbnail_url(%{meta: %{"mux" => %{"playback_id" => playback_id}}}) do
    "https://image.mux.com/#{playback_id}/thumbnail.jpg?width=120&height=120&fit_mode=smartcrop"
  end

  defp video_thumbnail_url(%{thumbnail: %Brando.Images.Image{} = thumb}) do
    Brando.Utils.img_url(thumb, :thumb)
  end

  defp video_thumbnail_url(_), do: nil

  defp maybe_add_tus_auth(payload, %{tus_auth: tus_auth}), do: Map.put(payload, :tus_auth, tus_auth)
  defp maybe_add_tus_auth(payload, _), do: payload
end
