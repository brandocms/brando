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

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Tab
  alias Phoenix.LiveView.JS

  # prop video_changeset, :any, required: true
  # prop myself, :any, required: true
  # prop schema, :atom, required: true
  # prop edit_video, :map, required: true
  # prop active_video_tab, :string, required: true
  # prop video_context, :any, required: true
  #
  # `myself` is the *parent* form's CID, not this module's — this is a function
  # component, so it has none. Every event the drawer emits is routed back to
  # `Form`, which is where its `handle_event/3` clauses stayed.

  @aspect_ratio_options [
    {"16:9 (Standard Widescreen)", "16:9"},
    {"4:3 (Classic)", "4:3"},
    {"21:9 (Ultrawide)", "21:9"},
    {"1:1 (Square)", "1:1"},
    {"4:5 (Portrait)", "4:5"},
    {"9:16 (Vertical/Stories)", "9:16"},
    {"1.91:1 (Landscape)", "1.91:1"},
    {"Custom", "custom"}
  ]

  defp metadata_inputs(assigns) do
    assigns = assign(assigns, :aspect_ratio_options, @aspect_ratio_options)

    ~H"""
    <div class="brando-input">
      <Input.text field={@video_form[:title]} label={gettext("Title")} />
    </div>

    <div class="brando-input">
      <Input.text field={@video_form[:caption]} label={gettext("Caption")} />
    </div>

    <Form.input
      type={:select}
      field={@video_form[:aspect_ratio]}
      label={gettext("Aspect Ratio")}
      placeholder={nil}
      instructions={nil}
      current_user={nil}
      form_id={nil}
      opts={[allow_custom: true]}
      options={@aspect_ratio_options}
    />
    """
  end

  defp thumbnail_section(assigns) do
    assigns =
      assigns
      |> assign_new(:show_extract_button, fn -> false end)

    ~H"""
    <div class="brando-input">
      <div class="field-wrapper">
        <div class="label-wrapper">
          <label class="control-label"><span>{gettext("Thumbnail")}</span></label>
        </div>
        <%= if @video && Ecto.assoc_loaded?(@video.thumbnail) && @video.thumbnail do %>
          <figure>
            <Content.image image={@video.thumbnail} size={:medium} />
          </figure>
          <figcaption class="tiny">{@video.thumbnail.path}</figcaption>
        <% else %>
          <div class="img-placeholder">
            <div class="placeholder-wrapper">
              <.icon name="hero-video-camera" />
            </div>
          </div>
        <% end %>

        <div class="button-group vertical">
          <button class="secondary" type="button" phx-click={toggle_drawer("#image-picker")}>
            {gettext("Select thumbnail from library")}
          </button>
          <button
            :if={@show_extract_button}
            class="secondary"
            type="button"
            phx-click={extract_thumbnail(@myself)}
          >
            {gettext("Extract thumbnail from video")}
          </button>
          <button
            :if={@video && Ecto.assoc_loaded?(@video.thumbnail) && @video.thumbnail}
            class="secondary"
            type="button"
            phx-click={reset_video_thumbnail(@myself)}
          >
            {gettext("Remove thumbnail")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp settings_section(assigns) do
    ~H"""
    <div class="video-settings-section">
      <div class="label-wrapper">
        <label class="control-label"><span>{gettext("Video Settings (Defaults)")}</span></label>
      </div>
      <p class="section-help">
        {gettext("These settings will be used as defaults when this video is displayed.")}
      </p>

      <div class="settings-grid">
        <Input.toggle field={@video_form[:autoplay]} label={gettext("Autoplay")} tiny={true} />
        <Input.toggle field={@video_form[:muted]} label={gettext("Muted")} tiny={true} />
        <Input.toggle field={@video_form[:controls]} label={gettext("Show controls")} tiny={true} />
        <Input.toggle field={@video_form[:loop]} label={gettext("Loop")} tiny={true} />
        <Input.toggle field={@video_form[:preload]} label={gettext("Preload")} tiny={true} />
        <Input.toggle
          field={@video_form[:playsinline]}
          label={gettext("Plays inline (mobile)")}
          tiny={true}
        />
      </div>
    </div>
    """
  end

  def render(assigns) do
    cfg =
      if assigns.edit_video[:schema] && assigns.edit_video[:field] do
        schema = assigns.edit_video.schema
        field = assigns.edit_video.field
        %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(schema, field)
        cfg
      else
        Brando.Type.VideoConfig.default_config()
      end

    upload_strategy = Map.get(cfg, :upload_strategy, :local)
    allow_uploads? = Map.get(cfg, :allow_uploads, true)
    allow_external_urls? = Map.get(cfg, :allow_external_urls, true)

    video_uploader_hook =
      case {allow_uploads?, upload_strategy} do
        {true, :mux} -> "Brando.MuxUploader"
        {true, :bunny} -> "Brando.BunnyUploader"
        {true, :cloudflare} -> "Brando.CloudflareUploader"
        _ -> nil
      end

    video_cfg =
      if is_struct(cfg, Brando.Type.VideoConfig),
        do: cfg,
        else: struct(Brando.Type.VideoConfig, cfg)

    video_upload_available? = Brando.Uploads.video_upload_available?(video_cfg)

    video_filename =
      case assigns.edit_video do
        %{video: %{file: %{filename: filename}}} when is_binary(filename) -> filename
        _ -> nil
      end

    assigns =
      assigns
      |> assign(:upload_strategy, upload_strategy)
      |> assign(:video_uploader_hook, video_uploader_hook)
      |> assign(:video_upload_available?, video_upload_available?)
      |> assign(:allow_external_urls?, allow_external_urls?)
      |> assign(:video_filename, video_filename)

    ~H"""
    <Content.drawer id="video-drawer" title={gettext("Video")} close={close_video()} z={1001} narrow>
      <.form
        :let={video_form}
        :if={@video_changeset}
        id="video-drawer-form"
        for={@video_changeset}
        phx-submit="save_video"
        phx-change="validate_video"
        phx-target={@myself}
      >
        <Tab.tabs active_tab={@active_video_tab}>
          <:buttons>
            <Tab.tab_button
              :if={@video_upload_available?}
              id="upload"
              label={gettext("Upload / File")}
              active_tab={@active_video_tab}
              target={@myself}
            />
            <Tab.tab_button
              :if={@allow_external_urls?}
              id="external"
              label={gettext("External (Vimeo/YouTube)")}
              active_tab={@active_video_tab}
              target={@myself}
            />
          </:buttons>

          <:tabs>
            <Tab.tab_content :if={@video_upload_available?} id="upload" active_tab={@active_video_tab}>
              <Input.input
                type={:hidden}
                field={video_form[:type]}
                value={(@edit_video.video && @edit_video.video.type) || :upload}
              />

              <div class="button-group vertical">
                <%!-- Direct upload strategies (Mux, Cloudflare, S3, Bunny) use external hooks --%>
                <%!-- Local strategy uses standard LiveView upload --%>
                <%= if @video_uploader_hook do %>
                  <div class="file-input-button">
                    <span class="label">
                      {gettext("Upload video file")}
                    </span>
                    <input
                      id={"video-uploader-#{@edit_video.field}"}
                      type="file"
                      accept=".mp4,.webm,.mov,.avi"
                      phx-hook={@video_uploader_hook}
                    />
                  </div>
                <% else %>
                  <div
                    id="video-drawer-upload-trigger"
                    class="file-input-button upload-trigger"
                    phx-hook="Brando.UploadTrigger"
                    data-kind="entry_field"
                    data-asset-type="video"
                    data-field={@edit_video.field}
                    data-path={Jason.encode!(@edit_video.path || [])}
                    data-config-target={
                      @edit_video.field &&
                        Brando.Assets.ConfigTarget.serialize(
                          {"video", Map.get(@edit_video, :schema) || @schema, @edit_video.field}
                        )
                    }
                    data-accept=".mp4,.webm,.mov,.avi,.ogv"
                  >
                    <span class="label">
                      {gettext("Upload video file")}
                    </span>
                    <input type="file" class="file-input" />
                  </div>
                <% end %>

                <button class="secondary" type="button" phx-click={toggle_drawer("#video-picker")}>
                  {gettext("Select existing video")}
                </button>
              </div>

              <%= if @edit_video.video && @edit_video.video.type == :upload do %>
                <div class="video-info">
                  <h5>{gettext("Video Information")}</h5>
                  <%= if @video_filename do %>
                    <div><strong>{gettext("Filename")}:</strong> {@video_filename}</div>
                  <% end %>
                  <%= if @edit_video.video.width && @edit_video.video.height do %>
                    <div>
                      <strong>{gettext("Dimensions")}:</strong> {@edit_video.video.width}×{@edit_video.video.height}
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= if @edit_video.video && @edit_video.video.id do %>
                <.metadata_inputs video_form={video_form} />
                <.thumbnail_section
                  video={@edit_video.video}
                  myself={@myself}
                  show_extract_button={@edit_video.video.type == :upload}
                />
              <% end %>
            </Tab.tab_content>

            <Tab.tab_content :if={@allow_external_urls?} id="external" active_tab={@active_video_tab}>
              <div class="brando-input">
                <Form.input
                  type={:select}
                  field={video_form[:type]}
                  label={gettext("Video Service")}
                  placeholder={nil}
                  instructions={nil}
                  current_user={nil}
                  form_id={nil}
                  opts={[]}
                  options={[
                    {gettext("Vimeo"), :vimeo},
                    {gettext("YouTube"), :youtube}
                  ]}
                />
              </div>

              <div class="brando-input">
                <Input.text
                  field={video_form[:source_url]}
                  label={gettext("Video URL")}
                  placeholder="https://vimeo.com/123456789 or https://youtube.com/watch?v=..."
                />
              </div>

              <div class="button-group vertical">
                <button class="primary" type="button" phx-click={parse_video_url(@myself)}>
                  {gettext("Parse URL and extract metadata")}
                </button>
              </div>

              <%= if @edit_video.video && @edit_video.video.remote_id do %>
                <div class="parsed-info">
                  <h5>{gettext("Parsed Information")}</h5>
                  <div><strong>{gettext("Remote ID")}:</strong> {@edit_video.video.remote_id}</div>
                  <div><strong>{gettext("Type")}:</strong> {@edit_video.video.type}</div>
                  <%= if @edit_video.video.width && @edit_video.video.height do %>
                    <div>
                      <strong>{gettext("Dimensions")}:</strong> {@edit_video.video.width}×{@edit_video.video.height}
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= if @edit_video.video && @edit_video.video.id do %>
                <.metadata_inputs video_form={video_form} />
                <.thumbnail_section video={@edit_video.video} myself={@myself} />
              <% end %>
            </Tab.tab_content>
          </:tabs>
        </Tab.tabs>

        <%= if @video_context == :asset && @edit_video.video && @edit_video.video.id do %>
          <.settings_section video_form={video_form} />
        <% end %>

        <%= if @edit_video.video && @edit_video.video.id do %>
          <div class="button-group vertical">
            <button class="secondary" type="button" phx-click={reset_video_field(@myself)}>
              {gettext("Reset video field")}
            </button>
          </div>
        <% end %>
      </.form>
    </Content.drawer>
    """
  end

  def reset_video_field(js \\ %JS{}, target) do
    js
    |> JS.push("reset_video_field", target: target)
    |> toggle_drawer("#video-drawer")
  end

  def reset_video_thumbnail(js \\ %JS{}, target) do
    JS.push(js, "reset_video_thumbnail", target: target)
  end

  def parse_video_url(js \\ %JS{}, target) do
    JS.push(js, "parse_video_url", target: target)
  end

  def extract_thumbnail(js \\ %JS{}, target) do
    JS.push(js, "extract_thumbnail", target: target)
  end

  def close_video(js \\ %JS{}) do
    js
    |> JS.dispatch("submit", to: "#video-drawer-form", detail: %{bubbles: true, cancelable: true})
    |> toggle_drawer("#video-drawer")
  end
end
