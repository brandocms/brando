defmodule BrandoAdmin.Components.Assets.MediaField do
  @moduledoc """
  Shared media intake and actions. Editing state belongs to the calling context;
  upload state belongs to the sticky UploadManager.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Assets.ConfigTarget
  alias Brando.Uploads
  alias BrandoAdmin.Components.Content

  attr :id, :string, required: true
  attr :type, :atom, values: [:image, :file, :video], required: true
  attr :asset, :any, default: nil
  attr :kind, :string, required: true
  attr :component_id, :string, default: nil
  attr :var_key, :string, default: nil
  attr :field, :any, default: nil
  attr :path, :list, default: []
  attr :config_target, :any, default: "default"
  attr :browse, :any, default: nil
  # Adds an asset by URL instead (a video's "Add from URL"); hidden when the
  # field's config doesn't allow external URLs.
  attr :link, :any, default: nil
  attr :configure, :any, default: nil
  attr :remove, :any, default: nil
  attr :editable, :boolean, default: true
  # `:line` is one line with all actions behind a single menu, for block
  # variables, where every variable is one row.
  attr :presentation, :atom, values: [:field, :block, :line], default: :field
  attr :label, :string, default: nil
  # A use's own alt text (a picture block's), shown instead of the library's
  attr :alt_override, :string, default: nil
  slot :inner_block
  slot :actions

  def field(assigns) do
    target = ConfigTarget.serialize(field_config_target(assigns.config_target))
    {config, _resolved_target} = config(assigns.type, target)
    asset = loaded_asset(assigns.asset)
    upload_enabled = assigns.editable && upload_enabled?(assigns.type, config)

    assigns =
      assigns
      |> assign(:asset, asset)
      |> assign(:compact?, assigns.presentation in [:field, :line])
      |> assign(:config_target, target)
      |> assign(:upload_enabled?, upload_enabled)
      |> assign(:upload_unavailable, upload_unavailable(assigns.type, config))
      |> assign(:accept, accept(config))
      |> assign(:limit, upload_limit(config))
      |> assign(:folder, Map.get(config, :upload_path))
      # An image on the default target uploads to a folder the editor picks
      |> assign(:choose_folder?, upload_enabled && assigns.type == :image && target == "default")
      |> assign(:name, asset_name(asset, assigns.type))
      |> assign(:details, asset_details(asset, assigns.type))
      |> assign(:alt, if(assigns.presentation != :line, do: alt_status(asset, assigns.type, assigns.alt_override)))
      |> assign(:processing_image?, processing_image?(asset, assigns.type))
      |> assign(:preview_ratio, image_ratio(asset, assigns.type))
      |> assign(
        :drop_label,
        if(upload_enabled, do: drop_label(assigns.type, asset), else: gettext("Choose media from the library"))
      )
      |> assign(:icon, media_icon(assigns.type))
      |> assign(:browse_label, browse_label(assigns.type))
      |> assign(:link, if(Map.get(config, :allow_external_urls, false), do: assigns.link))

    ~H"""
    <div
      id={@id}
      class={["media-field", "media-field--#{@presentation}", !@asset && "media-field--empty"]}
      phx-hook={@editable && "Brando.UploadTrigger"}
      data-upload-enabled={to_string(@upload_enabled?)}
      data-upload-unavailable={@upload_unavailable}
      data-kind={@kind}
      data-component-id={@component_id}
      data-var-key={@var_key}
      data-field={@field}
      data-path={Jason.encode!(@path)}
      data-asset-type={@type}
      data-config-target={@config_target}
      data-folder-browser={if @type == :image, do: "true", else: "false"}
      data-accept={@accept}
      data-click-mode="trigger"
      data-max-files="1"
      data-upload-label={@label || @name || @drop_label}
      data-drop-label={@drop_label}
      data-asset-id={@asset && @asset.id}
      data-processing-image={to_string(@processing_image?)}
      data-upload-processing={gettext("Processing…")}
    >
      <input :if={@upload_enabled?} type="file" class="file-input" accept={@accept} aria-label={gettext("Upload media")} />
      {render_slot(@inner_block)}
      <div class="media-field-content">
        <div
          class="media-field-preview"
          data-media-type={@type}
          style={@processing_image? && "aspect-ratio: #{@preview_ratio}"}
        >
          <%= cond do %>
            <% @type == :image && @asset && @asset.status == :processed -> %>
              <Content.image image={@asset} size={if @presentation == :block, do: :largest, else: :smallest} />
            <% @type == :video && @asset && loaded_asset(@asset.thumbnail) -> %>
              <Content.image image={@asset.thumbnail} size={:smallest} />
            <% @type == :video && video_url(@asset) -> %>
              <video muted preload="metadata" src={"#{video_url(@asset)}#t=0.1"} aria-label={gettext("Video preview")} />
            <% true -> %>
              <.icon name={@icon} />
          <% end %>
        </div>
        <div class="media-field-copy">
          <span class="media-field-name">{@name || @drop_label}</span>
          <span :if={@details} class="media-field-meta">{@details}</span>
          <%= case @alt do %>
            <% :missing -> %>
              <span class="media-field-alt is-missing">{gettext("No alt text")}</span>
            <% {text, missing} -> %>
              <span class="media-field-alt" title={text}>
                <span class="media-field-alt-label">{gettext("Alt")}</span> {text}
                <em :if={missing != []}>
                  {gettext("missing in %{languages}", languages: missing |> Enum.map(&String.upcase/1) |> Enum.join(", "))}
                </em>
              </span>
            <% _ -> %>
          <% end %>
          <span :if={@processing_image?} class="media-field-processing" role="status" aria-live="polite">
            <span class="media-field-spinner" aria-hidden="true"></span>
            {gettext("Processing image…")}
          </span>
          <span :if={!@asset && @upload_enabled?} class="media-field-meta">
            {gettext("Up to %{size}", size: @limit)}
          </span>
        </div>
      </div>
      <.action_menu
        :if={@editable && @presentation == :line}
        id={"#{@id}-actions"}
        label={if @asset, do: gettext("Change"), else: gettext("Add")}
      >
        <button :if={@upload_enabled?} type="button" class="upload-trigger">
          <.icon name="upload" />{if @asset, do: gettext("Upload replacement"), else: gettext("Upload")}
        </button>
        <button :if={@browse} type="button" phx-click={@browse}><.icon name="folder" />{@browse_label}</button>
        <button :if={@link} type="button" phx-click={@link}><.icon name="link" />{gettext("Add from URL")}</button>
        <button :if={@configure && (@asset || !@upload_enabled?)} type="button" phx-click={@configure}>
          <.icon name="sliders-horizontal" />{gettext("Configure")}
        </button>
        {render_slot(@actions)}
        <button :if={@asset && @remove} type="button" class="destructive" phx-click={@remove}>
          <.icon name="trash" />{gettext("Remove")}
        </button>
        <.folder_note :if={@upload_enabled?} folder={@folder} choose_folder?={@choose_folder?} />
      </.action_menu>
      <div :if={@editable && @presentation != :line} class="media-field-actions">
        <%!-- The two ways of filling an empty field read as one segmented control,
              the same as the asset's own actions do once it has been filled. --%>
        <div :if={!@asset && (@upload_enabled? || @browse || @link)} class="media-field-split">
          <button :if={@upload_enabled?} type="button" class="media-button primary upload-trigger">
            <.icon name="upload" />{gettext("Upload")}
          </button>
          <button :if={@browse} type="button" class="media-button" phx-click={@browse}>
            <.icon name="folder" />{@browse_label}
          </button>
          <button :if={@link} type="button" class="media-button" phx-click={@link}>
            <.icon name="link" />{gettext("Add from URL")}
          </button>
        </div>
        <%!-- A filled field's own actions are one segmented control too. The
              condition covers the union of the three below, so the group is
              there exactly when one of them is. --%>
        <div :if={@compact? && (@asset || !@upload_enabled?)} class="media-field-split">
          <button
            :if={@configure && (@asset || !@upload_enabled?)}
            type="button"
            class="media-button"
            phx-click={@configure}
          >
            {gettext("Configure")}
          </button>
          <%!-- Offered with Configure too: a filled field is replaced the same
                way everywhere, by upload, library or drop. --%>
          <button :if={@asset && @upload_enabled?} type="button" class="media-button upload-trigger">
            {gettext("Upload replacement")}
          </button>
          <button :if={@asset && @browse} type="button" class="media-button" phx-click={@browse}>
            <.icon name="folder" />{@browse_label}
          </button>
        </div>
        <%!-- On a block the asset's own controls — configure, whatever the caller
              adds, and replace — read as one segmented control. Remove stays
              outside it, since it is the one action that discards work. --%>
        <div class={["media-field-secondary-actions", @asset && !@compact? && "media-field-split"]}>
          <button
            :if={!@compact? && @configure && (@asset || !@upload_enabled?)}
            type="button"
            class="media-button"
            phx-click={@configure}
          >
            {gettext("Configure")}
          </button>
          {render_slot(@actions)}
          <div
            :if={@asset && !@compact? && (@upload_enabled? || @browse || @link)}
            id={"#{@id}-replace"}
            class="media-field-replace"
            phx-hook="Brando.FloatingDropdown"
            data-placement={if @type == :image && @actions != [], do: "bottom-end", else: "bottom-start"}
          >
            <button type="button" class="media-button" popovertarget={"#{@id}-replace-menu"} aria-expanded="false">
              {gettext("Replace")}<.icon name="chevron-down" />
            </button>
            <div id={"#{@id}-replace-menu"} class="media-field-menu" popover="auto">
              <button :if={@upload_enabled?} type="button" class="upload-trigger"><.icon name="upload" />{gettext(
                "Upload replacement"
              )}</button>
              <button :if={@browse} type="button" phx-click={@browse}><.icon name="folder" />{@browse_label}</button>
              <button :if={@link} type="button" phx-click={@link}><.icon name="link" />{gettext("Add from URL")}</button>
              <.folder_note :if={@upload_enabled?} folder={@folder} choose_folder?={@choose_folder?} />
            </div>
          </div>
        </div>
        <button
          :if={@asset && @remove && (!@compact? || !@configure)}
          type="button"
          class="media-button quiet destructive"
          phx-click={@remove}
        >
          {gettext("Remove")}
        </button>
      </div>
      <%!-- Where the next upload goes matters only when uploading is the next
            thing to do. A filled block keeps it in its Replace menu instead. --%>
      <div
        :if={@choose_folder? && (@presentation == :field || (@presentation == :block && !@asset))}
        class="media-field-destination"
      >
        <.icon name="folder" />
        <span>{gettext("Saved in")}</span>
        <span data-media-destination>{@folder}</span>
        <.change_folder_button />
      </div>
      <div id={"#{@id}-progress"} class="media-field-progress" phx-update="ignore" role="status" aria-live="polite"></div>
      <div class="media-field-drop" aria-hidden="true">
        <.icon name="upload" />
        <div>
          <span>{@drop_label}</span>
          <span :if={@upload_enabled?} class="media-field-drop-destination" data-media-destination>
            {@folder}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp field_config_target(config_target) when config_target in [nil, ""], do: "default"
  defp field_config_target(config_target), do: config_target

  defp processing_image?(asset, type), do: type == :image && asset != nil && asset.status != :processed

  # Where the next upload goes, under a menu's actions
  attr :folder, :string, required: true
  attr :choose_folder?, :boolean, required: true

  defp folder_note(assigns) do
    ~H"""
    <p class="media-field-menu-note">
      <.icon name="folder" />
      <span data-media-destination>{@folder}</span>
      <.change_folder_button :if={@choose_folder?} />
    </p>
    """
  end

  # Handled by the UploadTrigger hook, which opens the folder chooser
  defp change_folder_button(assigns) do
    ~H"""
    <button type="button" class="media-destination-change" aria-label={gettext("Change upload folder")}>
      {gettext("Change")}
    </button>
    """
  end

  @doc """
  A button that opens a small menu of actions, painted in the top layer so a
  scrolling drawer or a clipped block can't cut it off. Menu items are plain
  buttons; add `class="destructive"` to one that discards work.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :placement, :string, default: "bottom-start"
  slot :inner_block, required: true

  def action_menu(assigns) do
    ~H"""
    <div id={@id} class="media-field-replace media-action-menu" phx-hook="Brando.FloatingDropdown" data-placement={@placement}>
      <button type="button" class="media-button" popovertarget={"#{@id}-menu"} aria-expanded="false">
        {@label}<.icon name="chevron-down" />
      </button>
      <div id={"#{@id}-menu"} class="media-field-menu" popover="auto">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  def entry_config(field, type), do: ConfigTarget.serialize({to_string(type), field.form.data.__struct__, field.field})

  defp config(:image, target), do: Uploads.resolve_image_config(target)
  defp config(:file, target), do: Uploads.resolve_file_config(target)
  defp config(:video, target), do: Uploads.resolve_video_config(target)

  defp upload_enabled?(:video, cfg), do: Uploads.video_upload_available?(cfg) && cfg.upload_strategy in [:local, :s3]
  defp upload_enabled?(_, _), do: true

  # What a file dropped on a field that can't take it is told. A provider
  # video field (Mux, Bunny, Cloudflare) uploads through the picker instead —
  # unless the provider has no credentials, when nothing can upload and the
  # picker can only pick or add by URL.
  defp upload_unavailable(:video, cfg) do
    if Uploads.video_upload_available?(cfg) do
      gettext("Use %{action} to upload a video with this provider.", action: browse_label(:video))
    else
      gettext("Video upload isn't set up. Use %{action} to pick a video from the library or add one by URL.",
        action: browse_label(:video)
      )
    end
  end

  defp upload_unavailable(_type, _cfg), do: nil

  defp accept(%{allowed_mimetypes: types}) when is_list(types), do: Enum.join(types, ",")
  defp accept(_), do: nil
  defp loaded_asset(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded_asset(%Ecto.Changeset{} = asset), do: Ecto.Changeset.apply_changes(asset)
  defp loaded_asset(asset), do: asset

  @doc """
  Returns a playable address for a video, or `nil` when it has none.

  Uploaded files and linked external files have one. Vimeo, YouTube and
  provider videos have nothing to put in a `<video>` element. The video
  drawer uses this for its preview as well.
  """
  def video_url(%{type: :upload, file: %Brando.Files.File{} = file}), do: Brando.Utils.media_url(file)
  def video_url(%{type: :external_file, source_url: url}) when is_binary(url) and url != "", do: url
  def video_url(_), do: nil

  defp asset_name(nil, _), do: nil
  defp asset_name(asset, :image), do: Path.basename(asset.path || "")
  defp asset_name(asset, :file), do: asset.filename
  defp asset_name(asset, :video), do: asset.title || gettext("Untitled video")

  @doc """
  Returns the human-readable upload size limit for a field config, such as
  `"25 MB"`. Falls back to the global upload limit when the config sets none.
  """
  def upload_limit(config) do
    bytes =
      case Map.get(config, :size_limit) do
        limit when is_integer(limit) and limit > 0 -> limit
        _ -> Uploads.max_file_size()
      end

    size_label(bytes)
  end

  defp size_label(bytes) when bytes >= 1_000_000 do
    size = bytes |> Kernel./(1_000_000) |> Float.round(1) |> Float.to_string() |> String.trim_trailing(".0")
    "#{size} MB"
  end

  defp size_label(bytes), do: Brando.Utils.human_size(bytes)

  defp asset_details(nil, _), do: nil

  defp asset_details(%{width: width, height: height}, :image)
       when is_number(width) and width > 0 and is_number(height) and height > 0,
       do: "#{width} × #{height}"

  defp asset_details(_, :image), do: nil
  defp asset_details(asset, :file), do: Brando.Utils.human_size(asset.filesize)

  defp asset_details(video, :video) do
    case Brando.Videos.Helpers.aspect_ratio_label(video) do
      nil -> video_source(video)
      ratio -> "#{video_source(video)} · #{ratio}"
    end
  end

  defp video_source(%{type: :upload}), do: gettext("Uploaded video")
  defp video_source(%{type: :youtube}), do: "YouTube"
  defp video_source(%{type: type}) when type in [:vimeo, :vimeo_account], do: "Vimeo"
  defp video_source(_asset), do: gettext("Video")

  defp image_ratio(%{width: width, height: height}, :image)
       when is_number(width) and width > 0 and is_number(height) and height > 0,
       do: "#{width} / #{height}"

  defp image_ratio(_, _), do: "1"

  defp drop_label(:image, nil), do: gettext("Drop an image here")
  defp drop_label(:file, nil), do: gettext("Drop a file here")
  defp drop_label(:video, nil), do: gettext("Drop a video here")
  defp drop_label(:image, _), do: gettext("Drop an image to replace")
  defp drop_label(:file, _), do: gettext("Drop a file to replace")
  defp drop_label(:video, _), do: gettext("Drop a video to replace")

  # Short, and named after what is picked: three of these share a row with
  # Configure and Upload replacement.
  defp browse_label(:image), do: gettext("Select image")
  defp browse_label(:video), do: gettext("Select video")
  defp browse_label(_file), do: gettext("Select file")

  defp media_icon(:image), do: "image"
  defp media_icon(:file), do: "file"
  defp media_icon(:video), do: "film"

  # What the image says to someone who can't see it: its alt text in the
  # default language (or the first it has), and the content languages that
  # lack one. Nothing for an image whose alt text comes from its entry.
  defp alt_status(%Brando.Images.Image{status: :processed}, :image, override)
       when is_binary(override) and override != "",
       do: {override, []}

  defp alt_status(%Brando.Images.Image{status: :processed} = image, :image, _override) do
    alias Brando.Images.AltText

    if AltText.alt_from_entry?(image) do
      nil
    else
      languages = AltText.languages()

      case Enum.find_value(languages, &present_alt(image.alt, &1)) do
        nil -> :missing
        text -> {text, AltText.missing_languages(image)}
      end
    end
  end

  defp alt_status(_asset, _type, _override), do: nil

  defp present_alt(%{} = alt, language) do
    case Map.get(alt, language) do
      text when is_binary(text) -> if String.trim(text) != "", do: text
      _ -> nil
    end
  end

  defp present_alt(_alt, _language), do: nil
end
