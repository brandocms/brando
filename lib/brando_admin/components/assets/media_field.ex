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
  attr :configure, :any, default: nil
  attr :remove, :any, default: nil
  attr :editable, :boolean, default: true
  attr :presentation, :atom, values: [:field, :block], default: :field
  attr :label, :string, default: nil
  slot :inner_block
  slot :actions

  def field(assigns) do
    target = ConfigTarget.serialize(if assigns.config_target in [nil, ""], do: "default", else: assigns.config_target)
    {config, _resolved_target} = config(assigns.type, target)
    asset = loaded_asset(assigns.asset)
    upload_enabled = assigns.editable && upload_enabled?(assigns.type, config)

    assigns =
      assigns
      |> assign(:asset, asset)
      |> assign(:compact?, assigns.presentation == :field)
      |> assign(:config_target, target)
      |> assign(:upload_enabled?, upload_enabled)
      |> assign(:accept, accept(config))
      |> assign(:limit, size_label(config.size_limit))
      |> assign(:folder, Map.get(config, :upload_path))
      |> assign(:name, asset_name(asset, assigns.type))
      |> assign(:details, asset_details(asset, assigns.type))
      |> assign(
        :drop_label,
        if(upload_enabled, do: drop_label(assigns.type, asset), else: gettext("Choose media from the library"))
      )
      |> assign(:icon, media_icon(assigns.type))

    ~H"""
    <div
      id={@id}
      class={["media-field", "media-field--#{@presentation}", !@asset && "media-field--empty"]}
      phx-hook={@editable && "Brando.UploadTrigger"}
      data-upload-enabled={to_string(@upload_enabled?)}
      data-upload-unavailable={gettext("Use Browse library to upload a video with this provider.")}
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
    >
      <input :if={@upload_enabled?} type="file" class="file-input" accept={@accept} aria-label={gettext("Upload media")} />
      {render_slot(@inner_block)}
      <div class="media-field-content">
        <div class="media-field-preview" data-media-type={@type}>
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
          <span :if={@asset} class="media-field-meta">{@details}</span>
          <span :if={!@asset && @upload_enabled?} class="media-field-meta">
            {gettext("Up to %{size}", size: @limit)}
          </span>
        </div>
      </div>
      <div :if={@editable} class="media-field-actions">
        <button :if={!@asset && @upload_enabled?} type="button" class="media-button primary upload-trigger">
          <.icon name="hero-arrow-up-tray" />{gettext("Upload")}
        </button>
        <button :if={!@asset && @browse} type="button" class="media-button" phx-click={@browse}>
          <.icon name="hero-folder" />{gettext("Browse library")}
        </button>
        <button :if={@configure && (@asset || !@upload_enabled?)} type="button" class="media-button" phx-click={@configure}>
          {gettext("Configure")}
        </button>
        <button :if={@compact? && @asset && !@configure && @upload_enabled?} type="button" class="media-button upload-trigger">
          {gettext("Upload replacement")}
        </button>
        <button :if={@compact? && @asset && @browse} type="button" class="media-button" phx-click={@browse}>
          <.icon name="hero-folder" />{gettext("Browse library")}
        </button>
        <div class={[
          "media-field-secondary-actions",
          @asset && @type == :image && !@compact? && @actions != [] && "media-field-split"
        ]}>
          {render_slot(@actions)}
          <details :if={@asset && !@compact? && (@upload_enabled? || @browse)} class="media-field-replace">
            <summary class="media-button">{gettext("Replace")}<.icon name="hero-chevron-down-mini" /></summary>
            <div class="media-field-menu">
              <button :if={@upload_enabled?} type="button" class="upload-trigger"><.icon name="hero-arrow-up-tray" />{gettext(
                "Upload replacement"
              )}</button>
              <button :if={@browse} type="button" phx-click={@browse}><.icon name="hero-folder" />{gettext("Browse library")}</button>
            </div>
          </details>
        </div>
        <button
          :if={@asset && @remove && (!@compact? || !@configure)}
          type="button"
          class={["media-button quiet", @type == :image && "destructive"]}
          phx-click={@remove}
        >
          {gettext("Remove")}
        </button>
      </div>
      <div :if={@upload_enabled?} class="media-field-destination">
        <.icon name="hero-folder" />
        <span :if={@type == :image && @config_target == "default"} data-media-destination>{gettext(
          "Choose a folder when uploading"
        )}</span>
        <span :if={@type != :image || @config_target != "default"} data-media-destination>{@folder}</span>
      </div>
      <div id={"#{@id}-progress"} class="media-field-progress" phx-update="ignore" role="status" aria-live="polite"></div>
      <div class="media-field-drop" aria-hidden="true">
        <.icon name="hero-arrow-up-tray" />
        <div>
          <span>{@drop_label}</span>
          <span :if={@upload_enabled?} class="media-field-drop-destination" data-media-destination>
            {if @type == :image && @config_target == "default", do: gettext("Choose a folder before uploading"), else: @folder}
          </span>
        </div>
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

  defp accept(%{allowed_mimetypes: types}) when is_list(types), do: Enum.join(types, ",")
  defp accept(_), do: nil
  defp loaded_asset(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded_asset(%Ecto.Changeset{} = asset), do: Ecto.Changeset.apply_changes(asset)
  defp loaded_asset(asset), do: asset

  defp video_url(%{type: :upload, file: %Brando.Files.File{} = file}), do: Brando.Utils.media_url(file)
  defp video_url(%{type: :external_file, source_url: url}) when is_binary(url) and url != "", do: url
  defp video_url(_), do: nil

  defp asset_name(nil, _), do: nil
  defp asset_name(asset, :image), do: Path.basename(asset.path || "")
  defp asset_name(asset, :file), do: asset.filename
  defp asset_name(asset, :video), do: asset.title || gettext("Untitled video")

  defp size_label(bytes) when bytes >= 1_000_000 do
    size = bytes |> Kernel./(1_000_000) |> Float.round(1) |> Float.to_string() |> String.trim_trailing(".0")
    "#{size} MB"
  end

  defp size_label(bytes), do: Brando.Utils.human_size(bytes)

  defp asset_details(nil, _), do: nil
  defp asset_details(%{status: status}, :image) when status != :processed, do: gettext("Processing image…")
  defp asset_details(asset, :image), do: "#{asset.width} × #{asset.height}"
  defp asset_details(asset, :file), do: Brando.Utils.human_size(asset.filesize)
  defp asset_details(%{type: :upload}, :video), do: gettext("Uploaded video")
  defp asset_details(%{type: :youtube}, :video), do: "YouTube"
  defp asset_details(%{type: :vimeo}, :video), do: "Vimeo"
  defp asset_details(_asset, :video), do: gettext("Video")

  defp drop_label(:image, nil), do: gettext("Drop an image here")
  defp drop_label(:file, nil), do: gettext("Drop a file here")
  defp drop_label(:video, nil), do: gettext("Drop a video here")
  defp drop_label(:image, _), do: gettext("Drop an image to replace")
  defp drop_label(:file, _), do: gettext("Drop a file to replace")
  defp drop_label(:video, _), do: gettext("Drop a video to replace")

  defp media_icon(:image), do: "hero-photo"
  defp media_icon(:file), do: "hero-document"
  defp media_icon(:video), do: "hero-film"
end
