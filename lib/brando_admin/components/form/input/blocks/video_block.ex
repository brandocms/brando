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
    :aspect_ratio
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

  def update(assigns, socket) do
    block_cs = assigns.block.source
    block_data = Changeset.get_field(block_cs, :data)
    _block_data_cs = Changeset.change(block_data)

    # For refs, we need to get video data from the video association
    video_data = if assigns.is_ref? do
      # Video data comes from the ref's video association
      case Changeset.get_field(assigns.block.source, :video) do
        nil -> %{}
        video -> Map.from_struct(video)
      end
    else
      # For regular blocks, video data is in the block data (legacy)
      Map.from_struct(block_data)
    end

    socket
    |> assign(assigns)
    |> assign(:uid, Changeset.get_field(block_cs, :uid))
    |> assign(:type, Map.get(video_data, :type, :file))
    |> assign(:video_data, video_data)
    |> assign_new(:cover_image, fn -> block_data.cover_image end)
    |> then(&{:ok, &1})
  end

  def render(assigns) do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} class="video-block" data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Block.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @type == :upload do %>
              {gettext("Direct video file")}
            <% else %>
              {@type}: {@video_data[:remote_id]}
            <% end %>
          </:description>
          <:config>
            <%= if @video_data[:remote_id] in [nil, ""] do %>
              <!-- Video association data is handled separately -->
              <Input.input type={:hidden} field={block_data[:title]} />
              <Input.input type={:hidden} field={block_data[:poster]} />
              <Input.input type={:hidden} field={block_data[:cover]} />
              <Input.input type={:hidden} field={block_data[:opacity]} />
              <Input.input type={:hidden} field={block_data[:autoplay]} />
              <Input.input type={:hidden} field={block_data[:preload]} />
              <Input.input type={:hidden} field={block_data[:play_button]} />

              <div id={"block-#{@uid}-videoUrl"} phx-hook="Brando.VideoURLParser" phx-update="ignore" data-target={@myself}>
                <div class="video-loading hidden">
                  {gettext("Fetching video information. Please wait...")}
                </div>
                <small>
                  {gettext(
                    "To embed a video in your content, please input the full URL of the video you want to use. You have a couple of options:"
                  )}
                  <br /><br />

                  <strong>YouTube</strong>: {gettext(
                    "Enter the URL of any YouTube video to use the YouTube embedded player. This allows you to easily integrate YouTube videos with all their features."
                  )}<br />
                  <strong>Vimeo</strong>: {gettext(
                    "Enter the URL of any Vimeo video to use the Vimeo embedded player, ensuring a smooth and high-quality video playback experience."
                  )}<br />
                  <strong><%= gettext("Direct Video File") %></strong>: {gettext(
                    "You can also provide a direct link to a video file (e.g., .mp4, .webm). This will utilize our customized player to embed the video directly into your content."
                  )}<br /><br />
                  {gettext(
                    "Make sure the URL is complete and correct. For YouTube and Vimeo, copy the URL directly from your browser's address bar. For direct video files, ensure the link is publicly accessible and points directly to the video file. Enter the URL in the input below and click 'Get video info'"
                  )}<br /><br />
                </small>
                <input id={"block-#{@uid}-url"} type="text" class="text" />
                <button id={"block-#{@uid}-button"} type="button" class="secondary small">
                  {gettext("Get video info")}
                </button>
              </div>
            <% else %>
              <div class="panels">
                <div class="panel">
                  <div :if={@cover_image} class="cover">
                    <small><strong>Cover:</strong></small> <br />
                    <Content.image image={@cover_image} size={:smallest} />
                  </div>

                  <div :if={!@cover_image} class="cover">
                    <div class="img-placeholder">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                        <path fill="none" d="M0 0h24v24H0z" /><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z" />
                      </svg>
                    </div>
                  </div>

                  <div class="information mb-1 mt-1">
                    <strong>Dimensions:</strong>
                    {@video_data[:width]}&times;{@video_data[:height]}
                  </div>
                </div>
                <div class="panel">
                  <!-- Video association fields are read-only in form -->
                  <div class="field-wrapper">
                    <label>{gettext("Remote ID")}</label>
                    <input type="text" value={@video_data[:remote_id]} class="text monospace" readonly />
                  </div>
                  <Input.rich_text field={block_data[:title]} label={gettext("Caption")} opts={[]} />

                  <div class="button-group-vertical">
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
                    <button type="button" class="danger" phx-click={JS.push("reset_video", target: @myself)}>
                      {gettext("Reset video")}
                    </button>
                  </div>

                  <Input.input type={:hidden} field={block_data[:poster]} />
                  <%= if block_data[:cover].value in ["false", "svg"] do %>
                    <Input.input type={:hidden} field={block_data[:cover]} />
                  <% else %>
                    <Input.text field={block_data[:cover]} label={gettext("Cover")} />
                  <% end %>

                  <Input.input type={:hidden} field={block_data[:opacity]} />

                  <div class="row">
                    <div class="half">
                      <Input.number field={block_data[:width]} label={gettext("Width")} />
                    </div>
                    <div class="half">
                      <Input.number field={block_data[:height]} label={gettext("Height")} />
                    </div>
                  </div>

                  <div class="row">
                    <div class="half">
                      <Input.toggle compact field={block_data[:play_button]} label={gettext("Play button")} />
                    </div>
                    <div class="half">
                      <Input.toggle compact field={block_data[:autoplay]} label={gettext("Autoplay")} />
                    </div>
                  </div>
                  <div class="row">
                    <div class="half">
                      <Input.toggle compact field={block_data[:preload]} label={gettext("Preload")} />
                    </div>
                    <div class="half">
                      <Input.toggle compact field={block_data[:controls]} label={gettext("Show native player controls")} />
                    </div>
                  </div>
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
          <%= if @video_data[:remote_id] in [nil, ""] do %>
            <div class="empty">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                  <path fill="none" d="M0 0H24V24H0z" /><path d="M16 4c.552 0 1 .448 1 1v4.2l5.213-3.65c.226-.158.538-.103.697.124.058.084.09.184.09.286v12.08c0 .276-.224.5-.5.5-.103 0-.203-.032-.287-.09L17 14.8V19c0 .552-.448 1-1 1H2c-.552 0-1-.448-1-1V5c0-.552.448-1 1-1h14zm-1 2H3v12h12V6zM8 8h2v3h3v2H9.999L10 16H8l-.001-3H5v-2h3V8zm13 .841l-4 2.8v.718l4 2.8V8.84z" />
                </svg>
              </figure>
              <div class="instructions">
                <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}>
                  {gettext("Configure video block")}
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
                  <div class="video-info">
                    <figcaption>
                      <div class="info-wrapper">
                        <div class="video-type">
                          <span>{gettext("Video type")}</span>
                          {gettext("Direct video file")}
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
                            <.checklist_item cond={block_data[:play_button].value in ["true", true]}>
                              {gettext("Play button")}
                            </.checklist_item>
                            <.checklist_item cond={block_data[:preload].value in ["true", true]}>
                              {gettext("Preload")}
                            </.checklist_item>
                            <.checklist_item cond={block_data[:controls].value in ["true", true]}>
                              {gettext("Show native player controls")}
                            </.checklist_item>
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

  def handle_event("url", params, socket) do
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    %{
      "height" => height,
      "remoteId" => remote_id,
      "source" => source,
      "url" => url,
      "width" => width
    } = params

    # Create video data that will go to the video association
    video_data = %{
      source_url: url,
      type: String.to_existing_atom(source),
      remote_id: remote_id,
      width: width,
      height: height
    }

    # Get additional metadata from OEmbed if available
    video_data =
      case Brando.OEmbed.get(source, url) do
        {:ok,
         %{
           "title" => title,
           "width" => width,
           "height" => height,
           "thumbnail_url" => thumbnail_url
         }} ->
          Map.merge(video_data, %{
            title: title,
            width: width,
            height: height,
            thumbnail_url: thumbnail_url
          })

        _ ->
          video_data
      end

    # Get current block data to preserve any existing overrides
    block_data_cs = Block.get_block_data_changeset(socket.assigns.block)
    current_block_data = Changeset.apply_changes(block_data_cs)
    
    # Only keep override fields in block data, video data goes to association
    new_block_data = 
      current_block_data
      |> Map.from_struct()
      |> Map.take(@video_override_fields)

    send_update(target, %{
      event: "update_ref_data", 
      ref_data: new_block_data,
      ref_name: ref_name,
      video_data: video_data
    })
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

    # Reset to empty video block data with no video association
    new_block_data =
      %Brando.Villain.Blocks.VideoBlock.Data{}
      |> Map.from_struct()
      |> Map.take(@video_override_fields)

    send_update(target, %{
      event: "update_ref_data", 
      ref_data: new_block_data, 
      ref_name: ref_name,
      video_id: nil
    })

    {:noreply, assign(socket, :cover_image, nil)}
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

end
