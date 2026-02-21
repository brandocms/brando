defmodule BrandoAdmin.Components.Form.Input.Blocks.VideoBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  use Gettext, backend: Brando.Gettext

  import BrandoAdmin.Components.Content.List.Checklist

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
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
    :controls,
    :cover,
    :aspect_ratio,
    :loop,
    :muted,
    :playsinline,
    :video_class,
    :container_class,
    :config_target
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

  def update(%{event: "video_created_from_url"} = assigns, socket) do
    # Handle the video creation event from VideoPicker
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    ref_form = socket.assigns.ref_form

    # Get the current block data to use as ref_data
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    current_block_data = Changeset.apply_changes(block_data_cs)

    # Create ref_data with the video block overrides
    ref_data =
      current_block_data
      |> Map.from_struct()
      |> Map.take(@video_override_fields)

    # Send the update to the parent with both ref_data and video_data
    send_update(target, %{
      event: "update_ref_data",
      ref_name: ref_name,
      ref_data: ref_data,
      video_data: assigns.video_data,
      form: ref_form,
      force_render: true
    })

    # Update assigns for immediate display
    socket =
      socket
      |> assign(:video_data, assigns.video_data)
      |> assign(:type, Map.get(assigns.video_data, :type, :file))
      |> assign(:cover_image, nil)
      |> assign(:video, struct(Brando.Videos.Video, assigns.video_data))

    {:ok, socket}
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
       if assigns[:ref_form] do
         ref_cs = assigns.ref_form.source

         case Changeset.get_field(ref_cs, :video) do
           nil ->
             # If no video preloaded, try to fetch via video_id
             case Changeset.get_field(ref_cs, :video_id) do
               nil ->
                 nil

               video_id ->
                 case Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail]}) do
                   {:ok, video} -> video
                   _ -> nil
                 end
             end

           video ->
             video
         end
       else
         nil
       end
     end)
     |> assign_new(:video_data, fn %{video: video} -> if video, do: Map.from_struct(video), else: %{} end)
     |> assign_new(:type, fn %{video_data: video_data} -> Map.get(video_data, :type, :file) end)
     |> assign_new(:cover_image, fn %{video_data: video_data} -> Map.get(video_data, :thumbnail) end)
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
            <Input.input type={:hidden} field={block_data[:config_target]} />
            <%= if is_nil(@video) do %>
              <!-- Video association data is handled separately -->
              <Input.input type={:hidden} field={block_data[:title]} />
              <Input.input type={:hidden} field={block_data[:poster]} />
              <Input.input type={:hidden} field={block_data[:cover]} />

              <div class="empty-video-state">
                <div class="instructions">
                  <button
                    type="button"
                    class="primary small"
                    phx-click={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
                  >
                    {gettext("Select or create video")}
                  </button>
                  <p>
                    <small>
                      {gettext("Choose from existing videos or create new from URL (YouTube, Vimeo, direct files)")}
                    </small>
                  </p>
                </div>
              </div>
            <% else %>
              <div class="panels">
                <div class="panel">
                  <div :if={@cover_image} class="cover">
                    <Content.image image={@cover_image} size={:smallest} />
                  </div>

                  <div :if={!@cover_image && @video_data[:source_url]} class="cover">
                    <video
                      preload="metadata"
                      muted
                      class="video-frame-preview"
                      src={"#{@video_data[:source_url]}#t=0.1"}
                    />
                  </div>

                  <div :if={!@cover_image && !@video_data[:source_url]} class="cover">
                    <div class="img-placeholder">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                        <path fill="none" d="M0 0h24v24H0z" /><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z" />
                      </svg>
                    </div>
                  </div>

                  <div class="row">
                    <div class="half">
                      <Input.number placeholder={@video_data[:width]} field={block_data[:width]} label={gettext("Width")} />
                    </div>
                    <div class="half">
                      <Input.number placeholder={@video_data[:height]} field={block_data[:height]} label={gettext("Height")} />
                    </div>
                  </div>

                  <div class="video-info">
                    <div class="video-info-item">
                      <span>{gettext("Video type")}</span>
                      {String.upcase(to_string(@type || ""))}
                    </div>
                    <div :if={@video_data[:source_url]} class="video-info-item">
                      <span>{gettext("Source URL")}</span>
                      <span class="video-info-url" title={@video_data[:source_url]}>{@video_data[:source_url]}</span>
                    </div>
                    <div :if={@video_data[:remote_id]} class="video-info-item">
                      <span>{gettext("Remote ID")}</span>
                      {@video_data[:remote_id]}
                    </div>
                  </div>
                </div>
                <div class="panel">
                  <Input.rich_text field={block_data[:title]} label={gettext("Caption")} opts={[]} />

                  <div class="button-group-vertical">
                    <button
                      type="button"
                      class="secondary"
                      phx-click={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
                    >
                      {gettext("Change video")}
                    </button>
                    <button
                      type="button"
                      class="secondary"
                      phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
                    >
                      {gettext("Select cover image")}
                    </button>
                    <button type="button" class="danger" phx-click={JS.push("reset_image", target: @myself)}>
                      {gettext("Reset cover image")}
                    </button>
                  </div>

                  <Input.input type={:hidden} field={block_data[:poster]} />
                  <%= if block_data[:cover].value in ["false", "svg"] do %>
                    <Input.input type={:hidden} field={block_data[:cover]} />
                  <% else %>
                    <Input.text field={block_data[:cover]} label={gettext("Cover")} />
                  <% end %>

                  <Input.toggle tiny field={block_data[:play_button]} label={gettext("Play button")} />
                  <Input.toggle tiny field={block_data[:autoplay]} label={gettext("Autoplay")} />
                  <Input.toggle tiny field={block_data[:preload]} label={gettext("Preload")} />
                  <Input.toggle tiny field={block_data[:controls]} label={gettext("Show native player controls")} />
                  <Input.toggle tiny field={block_data[:loop]} label={gettext("Loop")} />
                  <Input.toggle tiny field={block_data[:muted]} label={gettext("Muted")} />

                  <Input.text
                    field={block_data[:aspect_ratio]}
                    label={gettext("Aspect ratio override")}
                    placeholder="16:9"
                  />
                  
    <!-- playsinline is always true for better UX -->
                  <Input.input type={:hidden} field={block_data[:playsinline]} value="true" />

                  <div class="row">
                    <div class="half">
                      <Input.text
                        field={block_data[:video_class]}
                        label={gettext("Video CSS class")}
                        placeholder="my-video-class"
                      />
                    </div>
                    <div class="half">
                      <Input.text
                        field={block_data[:container_class]}
                        label={gettext("Container CSS class")}
                        placeholder="my-container-class"
                      />
                    </div>
                  </div>

                  <Input.number field={block_data[:opacity]} label={gettext("Opacity (0-100)")} step="1" min="0" max="100" />
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

                    <Form.map_inputs :let={%{value: value, name: name}} field={cover_image[:sizes]}>
                      <input type="hidden" name={"#{name}"} value={"#{value}"} />
                    </Form.map_inputs>

                    <Form.array_inputs :let={%{value: array_value, name: array_name}} field={cover_image[:formats]}>
                      <input type="hidden" name={array_name} value={array_value} />
                    </Form.array_inputs>
                  </.inputs_for>
                </div>
              </div>
            <% end %>
          </:config>
          <%= if is_nil(@video) do %>
            <div class="empty">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                  <path fill="none" d="M0 0H24V24H0z" /><path d="M16 4c.552 0 1 .448 1 1v4.2l5.213-3.65c.226-.158.538-.103.697.124.058.084.09.184.09.286v12.08c0 .276-.224.5-.5.5-.103 0-.203-.032-.287-.09L17 14.8V19c0 .552-.448 1-1 1H2c-.552 0-1-.448-1-1V5c0-.552.448-1 1-1h14zm-1 2H3v12h12V6zM8 8h2v3h3v2H9.999L10 16H8l-.001-3H5v-2h3V8zm13 .841l-4 2.8v.718l4 2.8V8.84z" />
                </svg>
              </figure>
              <div class="instructions">
                <button
                  type="button"
                  class="primary"
                  phx-click={JS.push("open_video_picker", target: @myself) |> toggle_drawer("#video-picker")}
                >
                  {gettext("Select or create video")}
                </button>
              </div>
            </div>
          <% else %>
            <%= case @type do %>
              <% :vimeo -> %>
                <div class="video-content">
                  <iframe
                    src={"https://player.vimeo.com/video/#{@video_data[:remote_id]}?title=0&byline=0"}
                    width="580"
                    height="320"
                    frameborder="0"
                  >
                  </iframe>
                </div>
              <% :youtube -> %>
                <div class="video-content">
                  <iframe
                    src={"https://www.youtube.com/embed/#{@video_data[:remote_id]}"}
                    width="580"
                    height="320"
                    frameborder="0"
                  >
                  </iframe>
                </div>
              <% _ -> %>
                <div class="preview compact" id={"block-#{@uid}-videoSize"}>
                  <div class={[
                    "video-content",
                    (@video_data[:width] > @video_data[:height] && "landscape") || "portrait"
                  ]}>
                    <video
                      class="villain-video-file"
                      muted="muted"
                      tabindex="-1"
                      loop
                      autoplay
                      src={@video_data[:source_url] || @video_data[:remote_id]}
                    >
                      <source src={@video_data[:source_url] || @video_data[:remote_id]} type="video/mp4" />
                    </video>
                  </div>
                  <div class="video-info" data-video-id={@video_data[:id]}>
                    <figcaption>
                      <div class="info-wrapper">
                        <div class="video-type">
                          <span>{gettext("Video type")}</span>
                          {gettext("External video URL")}
                        </div>
                        <div class="video-dimensions">
                          <span>{gettext("Dimensions")}</span>
                          {@video_data[:width]} &times; {@video_data[:height]}
                        </div>
                        <div class="video-configuration">
                          <span>{gettext("Configuration")}</span>
                          <.checklist tiny>
                            <.checklist_item cond={block_data[:autoplay].value in ["true", true]}>
                              {gettext("Autoplay")}
                            </.checklist_item>
                            <%= if block_data[:autoplay].value in ["false", false] do %>
                              <.checklist_item cond={block_data[:play_button].value in ["true", true]}>
                                {gettext("Play button")}
                              </.checklist_item>
                              <.checklist_item cond={block_data[:controls].value in ["true", true]}>
                                {gettext("Show native player controls")}
                              </.checklist_item>
                            <% else %>
                              <.checklist_item cond={block_data[:muted].value in ["true", true]}>
                                {gettext("Muted")}
                              </.checklist_item>
                              <.checklist_item cond={block_data[:loop].value in ["true", true]}>
                                {gettext("Loop video")}
                              </.checklist_item>
                            <% end %>
                          </.checklist>
                        </div>
                      </div>
                      <button class="tiny mt-1" type="button" phx-click={show_modal("#block-#{@uid}_config")}>
                        {gettext("Edit video")}
                      </button>
                    </figcaption>
                  </div>
                </div>
            <% end %>
          <% end %>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("set_target", _, socket) do
    myself = socket.assigns.myself

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: "default",
      event_target: myself,
      multi: false,
      selected_images: []
    )

    {:noreply, socket}
  end

  def handle_event("reset_image", _, socket) do
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    # Get current block data and only update cover_image override field
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    current_block_data = Changeset.apply_changes(block_data_cs)

    new_block_data =
      current_block_data
      |> Map.from_struct()
      |> Map.take(@video_override_fields)
      |> Map.put(:cover_image, nil)

    send_update(target, %{event: "update_ref_data", ref_data: new_block_data, ref_name: ref_name})

    {:noreply, assign(socket, :cover_image, nil)}
  end

  def handle_event("reset_video", _, socket) do
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    # Reset to the ref's template defaults (captured on first mount)
    # instead of a blank struct with all-false values
    new_block_data = socket.assigns.initial_override_defaults

    send_update(target, %{
      event: "update_ref_data",
      ref_data: new_block_data,
      ref_name: ref_name,
      video_id: nil,
      force_render: true
    })

    # Clear video assigns immediately for block editor display
    socket =
      socket
      |> assign(:video, nil)
      |> assign(:video_data, %{})
      |> assign(:type, :file)
      |> assign(:cover_image, nil)

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id}, socket) do
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    {:ok, image} = Brando.Images.get_image(id)

    # For cover images, we still embed the picture data in the video block
    picture_data =
      image
      |> Map.from_struct()
      |> Map.take(@picture_fields_to_take)

    # Get current block data and update cover_image
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    current_block_data = Changeset.apply_changes(block_data_cs)

    new_block_data =
      current_block_data
      |> Map.from_struct()
      |> Map.take(@video_override_fields)
      |> Map.put(:cover_image, picture_data)

    send_update(target, %{event: "update_ref_data", ref_data: new_block_data, ref_name: ref_name})

    {:noreply, assign(socket, :cover_image, picture_data)}
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
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    ref_form = socket.assigns.ref_form

    # Get the current block data to preserve override fields
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    current_block_data = Changeset.apply_changes(block_data_cs)

    ref_data =
      current_block_data
      |> Map.from_struct()
      |> Map.take(@video_override_fields)

    case Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail]}) do
      {:ok, video} ->
        # Update the ref to point to the selected video
        send_update(target, %{
          event: "update_ref_data",
          ref_name: ref_name,
          ref_data: ref_data,
          video_id: video_id,
          form: ref_form,
          force_render: true
        })

        video_data = Map.from_struct(video)

        socket =
          socket
          |> assign(:video, video)
          |> assign(:video_data, video_data)
          |> assign(:type, Map.get(video_data, :type, :file))
          |> assign(:cover_image, Map.get(video_data, :thumbnail))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end
end
