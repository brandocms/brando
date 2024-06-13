defmodule BrandoAdmin.Components.Form.Input.Blocks.MediaBlock do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
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
    |> assign(:uid, assigns.block[:uid].value)
    |> assign_available_blocks_and_templates()
    |> then(&{:ok, &1})
  end

  def assign_available_blocks_and_templates(socket) do
    block_cs = socket.assigns.block.source
    block_data = Changeset.get_field(block_cs, :data)

    socket
    |> assign_new(:available_blocks, fn ->
      block_data.available_blocks
    end)
    |> assign_new(:block_templates, fn ->
      %{
        picture: block_data.template_picture,
        svg: block_data.template_svg,
        video: block_data.template_video,
        gallery: block_data.template_gallery
      }
    end)
  end

  def render(assigns) do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Block.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          multi={false}
          target={@target}
        >
          <:description>
            <%= if @ref_description do %>
              <%= @ref_description %>
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
                <%= gettext("Select media type:") %>
              </div>
              <div class="buttons">
                <.select_block
                  block_data={block_data}
                  target={@myself}
                  uid={@uid}
                  available_blocks={@available_blocks}
                />
              </div>
            </div>
          </div>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  attr :block_data, :any, required: true
  attr :target, :any, required: true
  attr :uid, :string, required: true
  attr :available_blocks, :list, required: true

  def select_block(assigns) do
    ~H"""
    <Form.array_inputs
      :let={%{value: array_value, name: array_name}}
      field={@block_data[:available_blocks]}
    >
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
    <%= gettext("Picture") %>
    """
  end

  def translate_block(%{key: "svg"} = assigns) do
    ~H"""
    <%= gettext("SVG") %>
    """
  end

  def translate_block(%{key: "gallery"} = assigns) do
    ~H"""
    <%= gettext("Gallery") %>
    """
  end

  def translate_block(%{key: "video"} = assigns) do
    ~H"""
    <%= gettext("Video") %>
    """
  end

  def handle_event("select_block", %{"block" => selected_block_type}, socket) do
    block_templates = socket.assigns.block_templates

    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    new_ref_block =
      case selected_block_type do
        "picture" ->
          %Brando.Villain.Blocks.PictureBlock{
            uid: Brando.Utils.generate_uid(),
            type: "picture",
            data: block_templates.picture
          }

        "video" ->
          %Brando.Villain.Blocks.VideoBlock{
            uid: Brando.Utils.generate_uid(),
            type: "video",
            data: block_templates.video
          }

        "gallery" ->
          %Brando.Villain.Blocks.GalleryBlock{
            uid: Brando.Utils.generate_uid(),
            type: "gallery",
            data: block_templates.gallery
          }

        "svg" ->
          %Brando.Villain.Blocks.SvgBlock{
            uid: Brando.Utils.generate_uid(),
            type: "svg",
            data: block_templates.svg
          }
      end

    send_update(target, %{
      event: "update_ref",
      ref: new_ref_block,
      ref_name: ref_name
    })

    {:noreply, socket}
  end
end
