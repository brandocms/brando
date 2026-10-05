defmodule BrandoAdmin.Components.Form.VideoDrawer do
  @moduledoc """
  Markup for the form's video drawer.

  Extracted from `BrandoAdmin.Components.Form` in Phase 9C of the form audit.
  This module is **markup only**, by measurement rather than by preference. The
  drawer's `update/2` and `handle_event/3` clauses stay in `Form` because they
  write the *parent's* state: `handle_event("save_video_authorized", …)` assigns
  `:form` and `:entry` and calls `ship_all_field_changes/1`, and
  `update(%{action: :video_upload_complete}, …)` calls `update_changeset/3`.
  Drawer recovery is likewise parent-owned — `assign_drawer_recovery_state/1`
  computes image, video and file state in a single `cond`, feeding the
  `phx-auto-recover` form that hangs off `Form`'s own element.

  So the plan's premise that these components "already communicate via
  `send_update`, so the seams are clean" holds **inbound only** (six sites:
  `Form.Input.Video` and `BrandoAdmin.LiveView.Form.Hooks`). Outbound is direct
  assignment, not messages. Splitting the behaviour out would mean inventing a
  callback protocol for the changeset write and a CID change for every control
  in the drawer; splitting the markup out costs nothing, because every input
  this module needs — including `myself` — is already passed as an explicit
  assign at the call site.

  Follows `MetaDrawer` and `ScheduledPublishingDrawer`: a `:component` exposing
  `render/1`, whose events belong to the parent form.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Assets.MediaField
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias Phoenix.LiveView.JS

  # prop video_changeset, :any, required: true
  # prop myself, :any, required: true
  # prop schema, :atom, required: true
  # prop edit_video, :map, required: true
  # prop video_context, :any, required: true
  #
  # `myself` is the *parent* form's CID, not this module's — this is a function
  # component, so it has none. Every event the drawer emits is routed back to
  # `Form`, which is where its `handle_event/3` clauses stayed.

  # Stored as "width/height", what `Brando.HTML.Video` reads and providers
  # write. Anything else goes in the custom input below the presets.
  @aspect_ratios [{16, 9}, {4, 3}, {1, 1}, {4, 5}, {9, 16}, {21, 9}]

  def render(assigns) do
    cfg = field_config(assigns.edit_video)

    # A field's config already carries the inherited strategy; the default
    # config doesn't, so it gets the site's default here.
    upload_strategy = Map.get(cfg, :upload_strategy) || Brando.default_video_upload_strategy()
    allow_uploads? = Map.get(cfg, :allow_uploads, true)
    video_upload_available? = Brando.Uploads.video_upload_available?(video_config(cfg, upload_strategy))
    video_uploader_hook = uploader_hook(video_upload_available? && allow_uploads?, upload_strategy)
    upload_trigger? = video_upload_available? && allow_uploads? && is_nil(video_uploader_hook)
    upload_input = upload_input(video_uploader_hook, upload_trigger?, assigns.edit_video)
    video = persisted_video(assigns.edit_video[:video])
    url_allowed? = Map.get(cfg, :allow_external_urls, true)
    dimensions = stored_dimensions(video) || assigns.edit_video[:preview_dimensions]

    assigns =
      assigns
      |> assign(:video, video)
      |> assign(:video_uploader_hook, video_uploader_hook)
      |> assign(:upload_trigger?, upload_trigger?)
      |> assign(:upload_input, upload_input)
      |> assign(:url_allowed?, url_allowed?)
      |> assign(:dimensions, dimensions)
      |> assign(:aspect_ratios, @aspect_ratios)

    ~H"""
    <Content.drawer
      id="video-drawer"
      title={gettext("Video details")}
      close={close_video()}
      z={1001}
      narrow
      light
      workspace
      icon="film"
      subtitle={gettext("Edit the shared library video.")}
    >
      <.form
        :let={video_form}
        :if={@video_changeset}
        id="video-drawer-form"
        for={@video_changeset}
        phx-submit="save_video"
        phx-change="validate_video"
        phx-target={@myself}
      >
        <%!-- `data-click-mode="trigger"` for the same reason as the image
        drawer: the preview is a playable <video>, and under the default mode
        every click on its controls would also open the file chooser. Only the
        empty state's `.upload-trigger` opens it now, besides the Upload
        action. --%>
        <div
          id="video-drawer-preview"
          class="video-drawer-preview"
          phx-hook={@upload_trigger? && "Brando.UploadTrigger"}
          data-kind="entry_field"
          data-asset-type="video"
          data-max-files="1"
          data-asset-id={@video && @video.id}
          data-field={@edit_video.field}
          data-path={Jason.encode!(@edit_video.path || [])}
          data-config-target={
            @edit_video.field &&
              Brando.Assets.ConfigTarget.serialize({"video", Map.get(@edit_video, :schema) || @schema, @edit_video.field})
          }
          data-accept=".mp4,.webm,.mov,.avi,.ogv"
          data-click-mode="trigger"
        >
          <input :if={@upload_trigger?} id="video-drawer-upload-input" type="file" class="file-input" />
          <input
            :if={@video_uploader_hook}
            id={"video-uploader-#{@edit_video.field}"}
            type="file"
            class="file-input"
            accept=".mp4,.webm,.mov,.avi"
            phx-hook={@video_uploader_hook}
          />
          <div
            id="video-drawer-upload-progress"
            class="media-field-progress"
            phx-update="ignore"
            role="status"
            aria-live="polite"
          >
          </div>

          <%= cond do %>
            <% @video && MediaField.video_url(@video) -> %>
              <video
                id="video-drawer-preview-video"
                phx-hook={!stored_dimensions(@video) && "Brando.VideoDimensions"}
                controls
                muted
                playsinline
                preload="metadata"
                src={"#{MediaField.video_url(@video)}#t=0.1"}
                aria-label={gettext("Video preview")}
              />
            <% @video && thumbnail(@video) -> %>
              <Content.image image={thumbnail(@video)} size={:medium} />
            <% true -> %>
              <div class={["video-drawer-placeholder", !@video && @upload_input && "upload-trigger"]}>
                <.icon name="film" />
                <span :if={!@video}>{gettext("No video selected")}</span>
              </div>
          <% end %>

          <div :if={@video} class="video-detail-file-info">
            <span>{source_name(@video)}</span>
            <span :if={@dimensions}>{dimensions_label(@dimensions)}</span>
          </div>
          <p :if={@video} class="video-detail-source">
            {source_label(@video)}
            <a :if={source_link(@video)} href={source_link(@video)} target="_blank" rel="noopener">
              {gettext("Open source")}<.icon name="external-link" />
            </a>
          </p>
        </div>

        <div class="video-detail-actions">
          <%= if @video do %>
            <div id="video-drawer-replace" class="media-action-menu" phx-hook="Brando.FloatingDropdown">
              <button
                type="button"
                class="workspace-button"
                popovertarget="video-drawer-replace-menu"
                aria-expanded="false"
              >
                <.icon name="refresh-cw" />{gettext("Replace")}<.icon name="chevron-down" />
              </button>
              <div id="video-drawer-replace-menu" class="media-action-options" popover="auto">
                <button :if={@upload_input} type="button" phx-click={JS.dispatch("click", to: @upload_input)}>
                  <.icon name="upload" />{gettext("Upload")}
                </button>
                <button type="button" phx-click={open_picker(false)}>
                  <.icon name="folder" />{gettext("Select video")}
                </button>
                <button :if={@url_allowed?} type="button" phx-click={open_picker(true)}>
                  <.icon name="link" />{gettext("Add from URL")}
                </button>
              </div>
            </div>
            <div
              id="video-drawer-more"
              class="media-action-menu video-detail-more"
              phx-hook="Brando.FloatingDropdown"
              data-placement="bottom-end"
            >
              <button
                type="button"
                class="workspace-button"
                aria-label={gettext("More video actions")}
                popovertarget="video-drawer-more-menu"
                aria-expanded="false"
              >
                <.icon name="ellipsis" />
              </button>
              <div id="video-drawer-more-menu" class="media-action-options" popover="auto">
                <button type="button" class="destructive" phx-click={reset_video_field(@myself)}>
                  <.icon name="trash" />{gettext("Remove")}
                </button>
              </div>
            </div>
          <% else %>
            <button
              :if={@upload_input}
              type="button"
              class="workspace-button primary"
              phx-click={JS.dispatch("click", to: @upload_input)}
            >
              <.icon name="upload" />{gettext("Upload")}
            </button>
            <button type="button" class="workspace-button" phx-click={open_picker(false)}>
              <.icon name="folder" />{gettext("Select video")}
            </button>
            <button :if={@url_allowed?} type="button" class="workspace-button" phx-click={open_picker(true)}>
              <.icon name="link" />{gettext("Add from URL")}
            </button>
          <% end %>
        </div>

        <%= if @video do %>
          <section class="video-detail-section">
            <div class="video-detail-section-heading">
              <h3>{gettext("Library details")}</h3>
              <p>{gettext("Changes apply wherever this video is used.")}</p>
            </div>
            <Input.text field={video_form[:title]} label={gettext("Title")} />
            <Input.text field={video_form[:caption]} label={gettext("Caption")} />
          </section>

          <section class="video-detail-section">
            <div class="video-detail-section-heading">
              <h3 id="video-drawer-ratio-heading">{gettext("Aspect ratio")}</h3>
              <p>{gettext("The shape the video is shown in. Original uses the video's own size.")}</p>
            </div>
            <div class="video-detail-ratios" role="radiogroup" aria-labelledby="video-drawer-ratio-heading">
              <%!-- The known ratio sits where the other cards have theirs, with
                    "Original" under it; without one, "Original" is all it says. --%>
              <.ratio_option
                label={
                  if @dimensions,
                    do: Brando.Videos.Helpers.ratio_label(elem(@dimensions, 0), elem(@dimensions, 1)),
                    else: gettext("Original")
                }
                hint={@dimensions && gettext("Original")}
                value=""
                ratio={@dimensions || {16, 9}}
                current={video_form[:aspect_ratio].value}
                myself={@myself}
              />
              <.ratio_option
                :for={{w, h} <- @aspect_ratios}
                label={"#{w}:#{h}"}
                value={"#{w}/#{h}"}
                ratio={{w, h}}
                current={video_form[:aspect_ratio].value}
                myself={@myself}
              />
            </div>
            <Input.text
              field={video_form[:aspect_ratio]}
              label={gettext("Custom")}
              placeholder={gettext("Width/height, e.g. 3/2")}
              monospace
            />
          </section>

          <section class="video-detail-section">
            <div class="video-detail-section-heading">
              <h3>{gettext("Thumbnail")}</h3>
              <p>{gettext("Shown before the video plays.")}</p>
            </div>
            <div class="video-detail-thumbnail">
              <%= if thumbnail(@video) do %>
                <Content.image image={thumbnail(@video)} size={:thumb} />
              <% else %>
                <div class="video-detail-thumbnail-empty"><.icon name="image" /></div>
              <% end %>
              <div class="video-detail-thumbnail-actions">
                <button
                  type="button"
                  class="workspace-button"
                  phx-click={browse_video_thumbnail(@myself)}
                >
                  {gettext("Select from library")}
                </button>
                <button
                  :if={thumbnail(@video)}
                  type="button"
                  class="workspace-button quiet"
                  phx-click={reset_video_thumbnail(@myself)}
                >
                  {gettext("Remove")}
                </button>
              </div>
            </div>
          </section>

          <section :if={@video_context == :asset} class="video-detail-section">
            <div class="video-detail-section-heading">
              <h3>{gettext("Playback defaults")}</h3>
              <p>
                {gettext(
                  "Default leaves it to the page or block showing the video. On and Off apply wherever it's shown, unless a block overrides them."
                )}
              </p>
            </div>
            <div class="video-detail-flags">
              <.flag_choice field={video_form[:autoplay]} label={gettext("Autoplay")} />
              <.flag_choice field={video_form[:muted]} label={gettext("Muted")} />
              <.flag_choice field={video_form[:controls]} label={gettext("Show controls")} />
              <.flag_choice field={video_form[:loop]} label={gettext("Loop")} />
              <.flag_choice field={video_form[:preload]} label={gettext("Preload")} />
            </div>
          </section>
        <% end %>
      </.form>
      <:footer>
        <span>{gettext("Shared video settings")}</span>
        <button type="button" class="workspace-button primary" phx-click={close_video()}>{gettext("Done")}</button>
      </:footer>
    </Content.drawer>
    """
  end

  defp field_config(edit_video) do
    if edit_video[:schema] && edit_video[:field] do
      %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(edit_video.schema, edit_video.field)
      cfg
    else
      Brando.Type.VideoConfig.default_config()
    end
  end

  defp video_config(cfg, upload_strategy) do
    if is_struct(cfg, Brando.Type.VideoConfig),
      do: %{cfg | upload_strategy: upload_strategy},
      else: struct(Brando.Type.VideoConfig, Map.put(cfg, :upload_strategy, upload_strategy))
  end

  # Mux, Bunny, Cloudflare and Vimeo upload straight to the provider through their
  # own hook on a file input; local and S3 go through UploadTrigger.
  defp uploader_hook(uploads?, upload_strategy) do
    case {uploads?, upload_strategy} do
      {true, :mux} -> "Brando.MuxUploader"
      {true, :bunny} -> "Brando.BunnyUploader"
      {true, :cloudflare} -> "Brando.CloudflareUploader"
      {true, :vimeo} -> "Brando.VimeoUploader"
      _ -> nil
    end
  end

  defp upload_input(video_uploader_hook, upload_trigger?, edit_video) do
    cond do
      video_uploader_hook -> "#video-uploader-#{edit_video.field}"
      upload_trigger? -> "#video-drawer-upload-input"
      true -> nil
    end
  end

  defp persisted_video(video), do: if(video && video.id, do: video)

  attr :label, :string, required: true
  # "Original", under the video's own ratio when that's known
  attr :hint, :string, default: nil
  attr :value, :string, required: true
  attr :ratio, :any, required: true
  attr :current, :any, required: true
  attr :myself, :any, required: true

  # A preset as a radio card, drawn at its own proportions inside a 28px box.
  defp ratio_option(assigns) do
    {w, h} = assigns.ratio
    scale = 28 / max(w, h)

    assigns =
      assigns
      |> assign(:checked?, normalize_ratio(assigns.current) == assigns.value)
      |> assign(:rect_w, Float.round(w * scale, 1))
      |> assign(:rect_h, Float.round(h * scale, 1))

    ~H"""
    <button
      type="button"
      role="radio"
      aria-checked={to_string(@checked?)}
      class={["video-detail-ratio", @checked? && "is-checked"]}
      phx-click={JS.push("set_video_aspect_ratio", value: %{value: @value}, target: @myself)}
    >
      <svg viewBox="0 0 32 32" width="32" height="32" aria-hidden="true">
        <rect
          x={16 - @rect_w / 2}
          y={16 - @rect_h / 2}
          width={@rect_w}
          height={@rect_h}
          rx="2"
          stroke-dasharray={@value == "" && "3 2"}
        />
      </svg>
      <span>{@label}</span>
      <small :if={@hint} class="video-detail-ratio-hint">{@hint}</small>
    </button>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true

  # A playback flag has three states, not two: unset leaves it to whatever
  # shows the video (`Brando.HTML.Video` and the template's opts), which a
  # switch can only show as off — and saving the drawer then stored that off
  # as an explicit false, which beats the template. A blank radio casts back
  # to nil.
  defp flag_choice(assigns) do
    assigns = assign(assigns, :current, flag_value(assigns.field.value))

    ~H"""
    <fieldset class="video-detail-flag">
      <legend>{@label}</legend>
      <div class="video-detail-flag-options">
        <label :for={{value, text} <- [{"", gettext("Default")}, {"true", gettext("On")}, {"false", gettext("Off")}]}>
          <input type="radio" name={@field.name} value={value} checked={@current == value} />
          <span>{text}</span>
        </label>
      </div>
    </fieldset>
    """
  end

  defp flag_value(value) when value in [true, "true"], do: "true"
  defp flag_value(value) when value in [false, "false"], do: "false"
  defp flag_value(_), do: ""

  # What the presets compare against: "16:9" and " 16 / 9 " select 16/9, and a
  # blank value selects Original.
  defp normalize_ratio(value) when is_binary(value) do
    value |> String.replace(":", "/") |> String.replace(" ", "")
  end

  defp normalize_ratio(_), do: ""

  # Original is drawn at the video's own proportions when they're known: from
  # the record, or from the preview (`Brando.VideoDimensions`) when it has none.
  defp stored_dimensions(%{width: w, height: h}) when is_integer(w) and is_integer(h) and w > 0 and h > 0, do: {w, h}
  defp stored_dimensions(_), do: nil

  defp dimensions_label({w, h}), do: "#{w} × #{h} · #{Brando.Videos.Helpers.ratio_label(w, h)}"

  # The picker was set up for this field when the drawer opened; this only
  # chooses whether it opens on its URL input.
  defp open_picker(url?) do
    "set_url_input"
    |> JS.push(value: %{show: url?}, target: "#video-picker")
    |> toggle_drawer("#video-picker")
  end

  defp thumbnail(%{thumbnail: %Brando.Images.Image{} = image}), do: image
  defp thumbnail(_), do: nil

  # What the preview card names the video by: an upload's filename, else its
  # title. Not a linked file's filename — provider URLs end in names like
  # Vimeo's `file.mp4`, which say nothing; its host goes in the source line.
  defp source_name(%{file: %Brando.Files.File{filename: filename}}) when is_binary(filename), do: filename
  defp source_name(%{title: title}) when is_binary(title) and title != "", do: title
  defp source_name(_), do: gettext("Untitled video")

  defp source_label(%{type: :upload}), do: gettext("Uploaded video")

  defp source_label(%{type: :external_file, source_url: url}) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> gettext("Linked file from %{host}", host: host)
      _ -> gettext("Linked file")
    end
  end

  defp source_label(%{type: :external_file}), do: gettext("Linked file")
  defp source_label(%{type: :vimeo}), do: "Vimeo"
  defp source_label(%{type: :youtube}), do: "YouTube"
  defp source_label(%{type: :mux}), do: "Mux"
  defp source_label(%{type: :bunny}), do: "Bunny"
  defp source_label(%{type: :cloudflare}), do: "Cloudflare"
  defp source_label(%{type: :vimeo_account}), do: "Vimeo"
  defp source_label(_), do: gettext("Video")

  defp source_link(%{type: type, source_url: url})
       when type in [:external_file, :vimeo, :youtube] and is_binary(url) and url != "",
       do: url

  defp source_link(_), do: nil

  def reset_video_field(js \\ %JS{}, target) do
    js
    |> JS.push("reset_video_field", target: target)
    |> toggle_drawer("#video-drawer")
  end

  # Sets the image picker up for this video's thumbnail before showing it.
  # Toggled on its own, the picker kept whatever the last field had set: its
  # folder, and its target, so a pick replaced that field's image instead.
  def browse_video_thumbnail(js \\ %JS{}, target) do
    js
    |> JS.push("browse_video_thumbnail", target: target)
    |> toggle_drawer("#image-picker")
  end

  def reset_video_thumbnail(js \\ %JS{}, target) do
    JS.push(js, "reset_video_thumbnail", target: target)
  end

  def close_video(js \\ %JS{}) do
    js
    |> JS.dispatch("submit", to: "#video-drawer-form", detail: %{bubbles: true, cancelable: true})
    |> toggle_drawer("#video-drawer")
  end
end
