defmodule BrandoAdmin.Components.Form.Input.Blocks.VideoBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Assets.MediaField
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Primitives
  alias Ecto.Changeset

  # prop block, :any
  # prop block_count, :integer
  # prop is_ref?, :boolean, default: false
  # prop belongs_to, :string

  # prop insert_module, :event, required: true
  # prop duplicate_block, :event, required: true

  # data block_data, :any
  # data uid, :string

  # Override fields that can be customized in the video block data
  @video_override_fields [
    :title,
    :poster,
    :autoplay,
    :opacity,
    :preload,
    :play_button,
    :progress,
    :controls,
    :cover,
    :aspect_ratio,
    :loop,
    :muted,
    :video_class,
    :container_class,
    :config_target,
    :cover_image
  ]

  # Override fields for cover image (still used for embedded cover images)
  @picture_fields_to_take [
    :picture_class,
    :img_class,
    :link,
    :srcset,
    :media_queries,
    :formats,
    :path,
    :width,
    :height,
    :sizes,
    :cdn,
    :lazyload,
    :moonwalk,
    :dominant_color,
    :placeholder,
    :focal,
    :fetchpriority
    # :config_target
  ]

  def update(%{event: "select_video", expected_asset_id: expected} = assigns, socket) do
    current_id = socket.assigns[:video] && socket.assigns.video.id

    if Brando.Uploads.AssetIntent.current_selection?(expected, current_id) do
      update(Map.delete(assigns, :expected_asset_id), socket)
    else
      {:ok, socket}
    end
  end

  def update(%{event: "video_created_from_url"} = assigns, socket) do
    # Handle the video creation event from VideoPicker
    socket
    |> Block.commit_ref_data(
      ref_data: Block.current_block_data_map(socket.assigns.block, @video_override_fields),
      video_data: assigns.video_data,
      form: socket.assigns.ref_form,
      force_render: true
    )
    |> assign(:video_data, assigns.video_data)
    |> assign(:type, Map.get(assigns.video_data, :type, :file))
    |> assign(:cover_image, nil)
    |> assign(:cover_image_id, nil)
    |> assign(:video, struct(Brando.Videos.Video, assigns.video_data))
    |> then(&{:ok, &1})
  end

  def update(%{event: "select_video", video_id: video_id}, socket) do
    case Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail, :file]}) do
      {:ok, video} ->
        video_data = Map.from_struct(video)

        socket
        |> Block.commit_ref_data(
          ref_data: Block.current_block_data_map(socket.assigns.block, @video_override_fields),
          video_id: video_id,
          form: socket.assigns.ref_form,
          force_render: true
        )
        |> assign(:video, video)
        |> assign(:video_data, video_data)
        |> assign(:type, Map.get(video_data, :type, :file))
        |> assign(:cover_image, Map.get(video_data, :thumbnail))
        |> assign(:cover_image_id, cover_image_id(Map.get(video_data, :thumbnail)))
        |> then(&{:ok, &1})

      {:error, _reason} ->
        {:ok, socket}
    end
  end

  def update(assigns, socket) do
    block_cs = assigns.block.source
    block_data = Changeset.get_field(block_cs, :data)
    _block_data_cs = Changeset.change(block_data)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, assigns.ref_form[:uid].value)
     |> assign_new(:initial_override_defaults, fn ->
       # Capture the initial override field values (from the module's template_video)
       # so we can restore them when resetting the video
       block_data
       |> Map.from_struct()
       |> Map.take(@video_override_fields)
     end)
     |> assign_new(:video, fn ->
       # Always get video from ref_form since we only use refs now
       Block.resolve_ref_association(assigns[:ref_form], :video, :video_id, fn video_id ->
         Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail, :file]})
       end)
     end)
     |> assign_new(:video_data, fn %{video: video} -> if video, do: Map.from_struct(video), else: %{} end)
     |> assign_new(:type, fn %{video_data: video_data} -> Map.get(video_data, :type, :file) end)
     |> assign_new(:cover_image, fn %{video_data: video_data} -> Map.get(video_data, :thumbnail) end)
     |> assign_new(:cover_image_id, fn %{cover_image: cover_image} -> cover_image_id(cover_image) end)
     |> assign_new(:video_upload_strategy, fn ->
       config_target = Map.get(block_data, :config_target)

       if config_target do
         case Brando.Videos.get_config_for(config_target) do
           {:ok, %{upload_strategy: strategy}} -> strategy
           _ -> Brando.default_video_upload_strategy()
         end
       else
         Brando.default_video_upload_strategy()
       end
     end)}
  end

  def render(assigns) do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} class="video-block" data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Block.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          multi={false}
          target={@target}
          ref_form={@ref_form}
          config_open={@config_open}
          config_layout="editor"
          config_title={gettext("Configure video")}
          config_subtitle={@ref_description || gettext("Settings for this use of the video")}
          config_icon="hero-film"
        >
          <:description>
            <%= case @type do %>
              <% :external_file -> %>
                {gettext("External video")}
                <%= if @video_data[:source_url] do %>
                  — {URI.parse(@video_data[:source_url]).host}
                <% end %>
              <% :youtube -> %>
                {gettext("YouTube")}: {@video_data[:remote_id]}
                <%= if @video_data[:title] do %>
                  — {@video_data[:title]}
                <% end %>
              <% :vimeo -> %>
                {gettext("Vimeo")}: {@video_data[:remote_id]}
                <%= if @video_data[:title] do %>
                  — {@video_data[:title]}
                <% end %>
              <% :upload -> %>
                {gettext("Uploaded video")}
                <%= if @video_data[:title] do %>
                  — {@video_data[:title]}
                <% end %>
              <% _ -> %>
                <%= if @video_data[:remote_id] do %>
                  {gettext("Video")}: {@video_data[:remote_id]}
                <% else %>
                  {gettext("No video selected")}
                <% end %>
            <% end %>
          </:description>
          <:config>
            <Content.modal_sections id={"video-#{@uid}-config-sections"}>
              <:section id="video" label={gettext("Video")} icon="hero-film">
                <div class="media-section-heading">
                  <h3 class="modal-section-title">{gettext("Selected video")}</h3>
                  <p class="modal-muted">{gettext("Replace the video while keeping this reference’s settings.")}</p>
                </div>
                <MediaField.field
                  id={"block-#{@uid}-video-modal-upload"}
                  type={:video}
                  asset={@video}
                  kind="block_ref_video"
                  component_id={"#{@uid}-video"}
                  config_target={block_data[:config_target].value || "default"}
                  presentation={:block}
                  browse={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
                  remove={JS.push("reset_video", target: @myself)}
                />
                <div class="media-config-fields">
                  <Input.rich_text
                    field={block_data[:title]}
                    label={gettext("Caption")}
                    default_value={@video && @video.title}
                    reset
                    opts={[]}
                  />
                </div>
              </:section>
              <:section id="playback" label={gettext("Playback")} icon="hero-play">
                <div class="media-section-heading">
                  <h3 class="modal-section-title">{gettext("Playback")}</h3>
                  <p class="modal-muted">{gettext("Use the video’s defaults or customize playback for this reference.")}</p>
                </div>
                <Input.override_toggle_group
                  label={gettext("Video playback")}
                  fields={[
                    {block_data[:autoplay], gettext("Autoplay"), @video && @video.autoplay},
                    {block_data[:preload], gettext("Preload"), @video && @video.preload},
                    {block_data[:controls], gettext("Controls"), @video && @video.controls},
                    {block_data[:loop], gettext("Loop"), @video && @video.loop},
                    {block_data[:muted], gettext("Muted"), @video && Map.get(@video, :muted, false)}
                  ]}
                  target={@myself}
                />
                <div class="media-playback-extra">
                  <Input.toggle tiny field={block_data[:play_button]} label={gettext("Play button")} />
                  <Input.toggle tiny field={block_data[:progress]} label={gettext("Progress bar")} />
                </div>
              </:section>
              <:section id="display" label={gettext("Display")} icon="hero-adjustments-horizontal">
                <div class="media-section-heading">
                  <h3 class="modal-section-title">{gettext("Display")}</h3>
                </div>
                <div class="media-cover-settings">
                  <Content.image :if={@cover_image} image={@cover_image} size={:smallest} />
                  <div class="media-field-actions">
                    <button
                      type="button"
                      class="secondary"
                      phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
                    >{gettext("Select cover image")}</button>
                    <button
                      :if={@cover_image}
                      type="button"
                      class="secondary"
                      phx-click={JS.push("reset_image", target: @myself)}
                    >{gettext("Remove cover image")}</button>
                  </div>
                </div>
                <Input.input type={:hidden} field={block_data[:poster]} />
                <%= if block_data[:cover].value in ["false", "svg"] do %>
                  <Input.input type={:hidden} field={block_data[:cover]} />
                <% else %>
                  <Input.text field={block_data[:cover]} label={gettext("Cover")} />
                <% end %>
                <Input.text field={block_data[:aspect_ratio]} label={gettext("Aspect ratio override")} placeholder="16:9" />
                <Input.text field={block_data[:video_class]} label={gettext("Video CSS classes")} />
                <Input.text field={block_data[:container_class]} label={gettext("Container CSS classes")} />
                <Input.number field={block_data[:opacity]} label={gettext("Opacity (0–100)")} step="1" min="0" max="100" />
              </:section>
            </Content.modal_sections>
            <Input.input type={:hidden} field={block_data[:config_target]} />
            <.inputs_for :let={cover_image} :if={block_data[:cover_image].value} field={block_data[:cover_image]}>
              <Input.input type={:hidden} field={cover_image[:placeholder]} />
              <Input.input type={:hidden} field={cover_image[:cdn]} />
              <Input.input type={:hidden} field={cover_image[:moonwalk]} />
              <Input.input type={:hidden} field={cover_image[:lazyload]} />
              <Input.input type={:hidden} field={cover_image[:credits]} />
              <Input.input type={:hidden} field={cover_image[:dominant_color]} />
              <Input.input type={:hidden} field={cover_image[:height]} />
              <Input.input type={:hidden} field={cover_image[:width]} />
              <Input.input type={:hidden} field={cover_image[:path]} />

              <.inputs_for :let={focal_form} field={cover_image[:focal]}>
                <Input.input type={:hidden} field={focal_form[:x]} />
                <Input.input type={:hidden} field={focal_form[:y]} />
              </.inputs_for>

              <Primitives.map_inputs :let={%{value: value, name: name}} field={cover_image[:sizes]}>
                <input type="hidden" name={"#{name}"} value={"#{value}"} />
              </Primitives.map_inputs>

              <Primitives.array_inputs :let={%{value: array_value, name: array_name}} field={cover_image[:formats]}>
                <input type="hidden" name={array_name} value={array_value} />
              </Primitives.array_inputs>
            </.inputs_for>
          </:config>
          <MediaField.field
            id={"block-#{@uid}-video-upload"}
            type={:video}
            asset={@video}
            kind="block_ref_video"
            component_id={"#{@uid}-video"}
            config_target={block_data[:config_target].value || "default"}
            presentation={:block}
            label={@ref_description}
            configure={JS.push("open_block_config", target: @target, value: %{uid: @uid})}
            browse={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
            remove={JS.push("reset_video", target: @myself)}
          />
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_override", %{"field" => field_name, "default" => default_str}, socket) do
    field_atom = String.to_existing_atom(field_name)
    default_val = default_str == "true"

    current_value =
      socket.assigns.block
      |> Block.get_block_data_changeset()
      |> Changeset.get_field(field_atom)

    visual_state = if is_nil(current_value), do: default_val, else: current_value

    ref_data =
      Block.current_block_data_map(socket.assigns.block, @video_override_fields, %{field_atom => !visual_state})

    socket
    |> Block.commit_ref_data(ref_data: ref_data, force_render: true)
    |> then(&{:noreply, &1})
  end

  def handle_event("reset_override", %{"field" => field_name}, socket) do
    field_atom = String.to_existing_atom(field_name)
    ref_data = Block.current_block_data_map(socket.assigns.block, @video_override_fields, %{field_atom => nil})

    socket
    |> Block.commit_ref_data(ref_data: ref_data, force_render: true)
    |> then(&{:noreply, &1})
  end

  def handle_event("reset_override_group", %{"fields" => fields_str}, socket) do
    overrides =
      fields_str
      |> String.split(",")
      |> Map.new(&{String.to_existing_atom(&1), nil})

    ref_data = Block.current_block_data_map(socket.assigns.block, @video_override_fields, overrides)

    socket
    |> Block.commit_ref_data(ref_data: ref_data, force_render: true)
    |> then(&{:noreply, &1})
  end

  def handle_event("set_target", _, socket) do
    myself = socket.assigns.myself
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)
    config_target = Map.get(block_data, :config_target, "default") || "default"

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: config_target,
      event_target: myself,
      multi: false,
      # "Selection means current editing state" (uploads skill) — the picker has
      # to mark the cover the block is showing right now, saved or not.
      selected_images: List.wrap(socket.assigns.cover_image_id)
    )

    {:noreply, socket}
  end

  def handle_event("reset_image", _, socket) do
    ref_data = Block.current_block_data_map(socket.assigns.block, @video_override_fields, %{cover_image: nil})

    socket
    |> Block.commit_ref_data(ref_data: ref_data)
    |> assign(:cover_image, nil)
    |> assign(:cover_image_id, nil)
    |> then(&{:noreply, &1})
  end

  def handle_event("reset_video", _, socket) do
    socket
    |> Block.commit_ref_data(
      ref_data: Block.current_block_data_map(socket.assigns.block, @video_override_fields),
      video_id: nil,
      force_render: true
    )
    |> assign(:video, nil)
    |> assign(:video_data, %{})
    |> assign(:type, :file)
    |> assign(:cover_image, nil)
    |> assign(:cover_image_id, nil)
    |> then(&{:noreply, &1})
  end

  def handle_event("select_image", %{"id" => id}, socket) do
    {:ok, image} = Brando.Images.get_image(id)

    # For cover images, we still embed the picture data in the video block
    picture_data =
      image
      |> Map.from_struct()
      |> Map.take(@picture_fields_to_take)

    ref_data =
      Block.current_block_data_map(socket.assigns.block, @video_override_fields, %{cover_image: picture_data})

    socket
    |> Block.commit_ref_data(ref_data: ref_data)
    |> assign(:cover_image, picture_data)
    |> assign(:cover_image_id, image.id)
    |> then(&{:noreply, &1})
  end

  def handle_event("open_video_picker", _, socket) do
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)
    config_target = Map.get(block_data, :config_target) || "default"

    upload_strategy =
      case Brando.Videos.get_config_for(config_target) do
        {:ok, %{upload_strategy: strategy}} -> strategy
        _ -> Brando.default_video_upload_strategy()
      end

    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      config_target: config_target,
      upload_strategy: upload_strategy,
      event_target: socket.assigns.myself,
      multi: false,
      selected_videos: if(socket.assigns.video, do: [socket.assigns.video.id], else: [])
    )

    {:noreply, socket}
  end

  def handle_event("select_video", %{"id" => video_id}, socket) do
    case Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail, :file]}) do
      {:ok, video} ->
        video_data = Map.from_struct(video)

        socket
        |> Block.commit_ref_data(
          # preserve override fields; the video itself goes to the association
          ref_data: Block.current_block_data_map(socket.assigns.block, @video_override_fields),
          video_id: video_id,
          form: socket.assigns.ref_form,
          force_render: true
        )
        |> assign(:video, video)
        |> assign(:video_data, video_data)
        |> assign(:type, Map.get(video_data, :type, :file))
        |> assign(:cover_image, Map.get(video_data, :thumbnail))
        |> assign(:cover_image_id, cover_image_id(Map.get(video_data, :thumbnail)))
        |> then(&{:noreply, &1})

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # The cover image reaches this component two ways: as the video's preloaded
  # `thumbnail` (a `Brando.Images.Image`, so it has an id) or as the stripped
  # `picture_data` map that `select_image` builds — which has none, because
  # `@picture_fields_to_take` omits `:id` and the `PictureBlock.Data` embed it
  # is cast into has no field that could hold one. `cover_image_id` is therefore
  # tracked alongside the data rather than read back out of it.
  defp cover_image_id(%{id: id}) when not is_nil(id), do: id
  defp cover_image_id(_cover_image), do: nil
end
