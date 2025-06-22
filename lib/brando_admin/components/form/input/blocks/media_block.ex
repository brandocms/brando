defmodule BrandoAdmin.Components.Form.Input.Blocks.MediaBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias Ecto.Changeset

  # prop block, :form
  # prop base_form, :form
  # prop index, :integer
  # prop block_count, :integer
  # prop is_ref?, :boolean, default: false
  # prop ref_description, :string
  # prop belongs_to, :string
  # prop data_field, :atom

  # prop insert_module, :event, required: true
  # prop duplicate_block, :event, required: true

  # data uid, :string
  # data text_type, :string
  # data initial_props, :map
  # data block_data, :map
  # data available_blocks, :list

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(:uid, assigns.ref_form[:uid].value)
    |> assign_available_blocks_and_templates()
    |> then(&{:ok, &1})
  end

  def assign_available_blocks_and_templates(socket) do
    block_cs = socket.assigns.block.source
    block_data = Changeset.get_field(block_cs, :data)

    socket
    |> assign_new(:available_blocks, fn ->
      if block_data && block_data.available_blocks do
        block_data.available_blocks
      else
        ["picture", "video"]
      end
    end)
    |> assign_new(:block_templates, fn ->
      if block_data do
        %{
          picture: block_data.template_picture,
          svg: block_data.template_svg,
          video: block_data.template_video,
          gallery: block_data.template_gallery
        }
      else
        %{picture: nil, svg: nil, video: nil, gallery: nil}
      end
    end)
  end

  def render(%{block: %{data: %{type: type}}} = assigns) when type in ["media", :media] do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <!-- Hidden inputs to preserve template data during form validation -->
        <.inputs_for :let={template_picture} field={block_data[:template_picture]}>
          <input type="hidden" name={template_picture[:title].name} value={template_picture[:title].value || ""} />
          <input type="hidden" name={template_picture[:credits].name} value={template_picture[:credits].value || ""} />
          <input type="hidden" name={template_picture[:alt].name} value={template_picture[:alt].value || ""} />
          <input type="hidden" name={template_picture[:picture_class].name} value={template_picture[:picture_class].value || ""} />
          <input type="hidden" name={template_picture[:img_class].name} value={template_picture[:img_class].value || ""} />
          <input type="hidden" name={template_picture[:link].name} value={template_picture[:link].value || ""} />
          <input type="hidden" name={template_picture[:srcset].name} value={template_picture[:srcset].value || ""} />
          <input type="hidden" name={template_picture[:media_queries].name} value={template_picture[:media_queries].value || ""} />
          <input type="hidden" name={template_picture[:lazyload].name} value={to_string(template_picture[:lazyload].value)} />
          <input type="hidden" name={template_picture[:moonwalk].name} value={to_string(template_picture[:moonwalk].value)} />
          <input type="hidden" name={template_picture[:placeholder].name} value={to_string(template_picture[:placeholder].value)} />
          <input type="hidden" name={template_picture[:fetchpriority].name} value={to_string(template_picture[:fetchpriority].value)} />
        </.inputs_for>

        <.inputs_for :let={template_video} field={block_data[:template_video]}>
          <input type="hidden" name={template_video[:title].name} value={template_video[:title].value || ""} />
          <input type="hidden" name={template_video[:poster].name} value={template_video[:poster].value || ""} />
          <input type="hidden" name={template_video[:autoplay].name} value={to_string(template_video[:autoplay].value)} />
          <input type="hidden" name={template_video[:opacity].name} value={to_string(template_video[:opacity].value)} />
          <input type="hidden" name={template_video[:preload].name} value={to_string(template_video[:preload].value)} />
          <input type="hidden" name={template_video[:play_button].name} value={to_string(template_video[:play_button].value)} />
          <input type="hidden" name={template_video[:controls].name} value={to_string(template_video[:controls].value)} />
          <input type="hidden" name={template_video[:cover].name} value={to_string(template_video[:cover].value)} />
          <input type="hidden" name={template_video[:aspect_ratio].name} value={template_video[:aspect_ratio].value || ""} />
        </.inputs_for>

        <Block.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              {@ref_description}
            <% end %>
          </:description>
          <div class="media-block">
            <div class="empty">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M11.27 12.216L15 6l8 15H2L9 8l2.27 4.216zm1.12 2.022L14.987 19h4.68l-4.77-8.942-2.507 4.18zM5.348 19h7.304L9 12.219 5.348 19zM5.5 8a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z" />
                </svg>
              </figure>
              <div class="instructions">
                {gettext("Select media type:")}
              </div>
              <div class="buttons">
                <.select_block block_data={block_data} target={@myself} uid={@uid} available_blocks={@available_blocks} />
              </div>
            </div>
          </div>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def render(assigns) do
    # MediaBlock called with non-media type, render minimal placeholder
    assigns = assign(assigns, :block_type, assigns.block[:type].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid} style="display: none;">
      <!-- MediaBlock being replaced by <%= @block_type %> -->
    </div>
    """
  end

  attr :block_data, :any, required: true
  attr :target, :any, required: true
  attr :uid, :string, required: true
  attr :available_blocks, :list, required: true

  def select_block(assigns) do
    ~H"""
    <Form.array_inputs :let={%{value: array_value, name: array_name}} field={@block_data[:available_blocks]}>
      <input type="hidden" name={array_name} value={array_value} />
    </Form.array_inputs>

    <button
      :for={block_type <- @available_blocks}
      type="button"
      class="tiny"
      phx-click={JS.push("select_block", target: @target)}
      phx-value-block={block_type}
    >
      <.translate_block key={block_type} />
    </button>
    """
  end

  def translate_block(%{key: "picture"} = assigns) do
    ~H"""
    {gettext("Picture")}
    """
  end

  def translate_block(%{key: "svg"} = assigns) do
    ~H"""
    {gettext("SVG")}
    """
  end

  def translate_block(%{key: "gallery"} = assigns) do
    ~H"""
    {gettext("Gallery")}
    """
  end

  def translate_block(%{key: "video"} = assigns) do
    ~H"""
    {gettext("Video")}
    """
  end

  def handle_event("select_block", %{"block" => selected_block_type}, socket) do
    block_templates = socket.assigns.block_templates

    target = socket.assigns.target
    ref_name = socket.assigns.ref_name
    ref_description = socket.assigns.ref_description
    uid = Brando.Utils.generate_uid()

    ref_data =
      case selected_block_type do
        "picture" ->
          %Brando.Villain.Blocks.PictureBlock{
            type: "picture",
            data: block_templates.picture
          }

        "video" ->
          %Brando.Villain.Blocks.VideoBlock{
            type: "video",
            data: block_templates.video
          }

        "gallery" ->
          %Brando.Villain.Blocks.GalleryBlock{
            type: "gallery",
            data: block_templates.gallery
          }

        "svg" ->
          %Brando.Villain.Blocks.SvgBlock{
            type: "svg",
            data: block_templates.svg
          }
      end

    ref = %Brando.Content.Ref{
      name: ref_name,
      description: ref_description,
      uid: uid,
      data: ref_data
    }

    send_update(target, %{
      event: "update_ref",
      ref: ref
    })

    {:noreply, socket}
  end
end
