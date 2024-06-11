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
    |> then(&{:ok, &1})
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
                <Form.array_inputs
                  :let={%{value: array_value, name: array_name}}
                  field={block_data[:available_blocks]}
                >
                  <input type="hidden" name={array_name} value={array_value} />
                </Form.array_inputs>

                <%= if "picture" in block_data[:available_blocks].value do %>
                  <button
                    type="button"
                    class="tiny"
                    phx-click={JS.push("select_block", target: @myself)}
                    phx-value-block="picture"
                  >
                    <%= gettext("Picture") %>
                  </button>
                  <.inputs_for :let={tpl_data} field={block_data[:template_picture]}>
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:picture_class]}
                      uid={@uid}
                      id_prefix="block_data_tpl_picture"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:img_class]}
                      uid={@uid}
                      id_prefix="block_data_tpl_picture"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:placeholder]}
                      uid={@uid}
                      id_prefix="block_data_tpl_picture"
                    />

                    <Form.array_inputs
                      :let={%{value: array_value, name: array_name}}
                      field={block_data[:formats]}
                    >
                      <input type="hidden" name={array_name} value={array_value} />
                    </Form.array_inputs>
                  </.inputs_for>
                <% end %>

                <%= if "video" in block_data[:available_blocks].value do %>
                  <button
                    type="button"
                    class="tiny"
                    phx-click={JS.push("select_block", target: @myself)}
                    phx-value-block="video"
                  >
                    <%= gettext("Video") %>
                  </button>
                  <.inputs_for :let={tpl_data} field={block_data[:template_video]}>
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:opacity]}
                      uid={@uid}
                      id_prefix="block_data_tpl_video"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:autoplay]}
                      uid={@uid}
                      id_prefix="block_data_tpl_video"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:preload]}
                      uid={@uid}
                      id_prefix="block_data_tpl_video"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:play_button]}
                      uid={@uid}
                      id_prefix="block_data_tpl_video"
                    />
                  </.inputs_for>
                <% end %>

                <%= if "gallery" in block_data[:available_blocks].value do %>
                  <button
                    type="button"
                    class="tiny"
                    phx-click={JS.push("select_block", target: @myself)}
                    phx-value-block="gallery"
                  >
                    <%= gettext("Gallery") %>
                  </button>
                  <.inputs_for :let={tpl_data} field={block_data[:template_gallery]}>
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:type]}
                      uid={@uid}
                      id_prefix="block_data_tpl_gallery"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:display]}
                      uid={@uid}
                      id_prefix="block_data_tpl_gallery"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:class]}
                      uid={@uid}
                      id_prefix="block_data_tpl_gallery"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:series_slug]}
                      uid={@uid}
                      id_prefix="block_data_tpl_gallery"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:lightbox]}
                      uid={@uid}
                      id_prefix="block_data_tpl_gallery"
                    />
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:placeholder]}
                      uid={@uid}
                      id_prefix="block_data_tpl_gallery"
                    />
                    <Form.array_inputs
                      :let={%{value: array_value, name: array_name}}
                      field={block_data[:formats]}
                    >
                      <input type="hidden" name={array_name} value={array_value} />
                    </Form.array_inputs>
                  </.inputs_for>
                <% end %>
                <%= if "svg" in block_data[:available_blocks].value do %>
                  <button
                    type="button"
                    class="tiny"
                    phx-click={JS.push("select_block", target: @myself)}
                    phx-value-block="svg"
                  >
                    SVG
                  </button>
                  <.inputs_for :let={tpl_data} field={block_data[:template_svg]}>
                    <Input.input
                      type={:hidden}
                      field={tpl_data[:class]}
                      label={gettext("Class")}
                      uid={@uid}
                      id_prefix="block_data_tpl_svg"
                    />
                  </.inputs_for>
                <% end %>
              </div>
            </div>
          </div>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("select_block", %{"block" => selected_block_type}, socket) do
    block = socket.assigns.block
    block_data_cs = Block.get_block_data_changeset(block)
    block_data = Changeset.apply_changes(block_data_cs)

    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    require Logger

    Logger.error("""
    => selected [#{selected_block_type}]

    templates?: #{inspect(block_data, pretty: true)}

    transform!

    block

    #{inspect(block, pretty: true)}

    """)

    new_ref_block =
      case selected_block_type do
        "picture" ->
          %Brando.Villain.Blocks.PictureBlock{
            uid: Brando.Utils.generate_uid(),
            type: "picture",
            data: block_data.template_picture
          }

        "video" ->
          %Brando.Villain.Blocks.VideoBlock{
            uid: Brando.Utils.generate_uid(),
            type: "video",
            data: block_data.template_video
          }

        "gallery" ->
          %Brando.Villain.Blocks.GalleryBlock{
            uid: Brando.Utils.generate_uid(),
            type: "gallery",
            data: block_data.template_gallery
          }

        "svg" ->
          %Brando.Villain.Blocks.SvgBlock{
            uid: Brando.Utils.generate_uid(),
            type: "svg",
            data: block_data.template_svg
          }
      end

    send_update(target, %{
      event: "update_ref",
      ref: new_ref_block,
      ref_name: ref_name
    })

    # send_update(target, %{event: "update_ref_data", ref_data: new_ref_block, ref_name: ref_name})

    # {:ok, image} = Brando.Images.get_image(id)

    # new_data =
    #   block_data
    #   |> Map.merge(image)
    #   |> Map.from_struct()
    #   |> Map.take(@fields_to_take)

    # send_update(target, %{event: "update_ref_data", ref_data: new_data, ref_name: ref_name})
    # {:noreply, socket}

    # # replace block
    # changeset = form.source
    # uid = block_form[:uid].value
    # block_data = block_form[:data].value

    # new_block =
    #   case block do
    #     "picture" ->
    #       %Brando.Villain.Blocks.PictureBlock{
    #         uid: Brando.Utils.generate_uid(),
    #         type: "picture",
    #         data: block_data.template_picture
    #       }

    #     "video" ->
    #       %Brando.Villain.Blocks.VideoBlock{
    #         uid: Brando.Utils.generate_uid(),
    #         type: "video",
    #         data: block_data.template_video
    #       }

    #     "gallery" ->
    #       %Brando.Villain.Blocks.GalleryBlock{
    #         uid: Brando.Utils.generate_uid(),
    #         type: "gallery",
    #         data: block_data.template_gallery
    #       }

    #     "svg" ->
    #       %Brando.Villain.Blocks.SvgBlock{
    #         uid: Brando.Utils.generate_uid(),
    #         type: "svg",
    #         data: block_data.template_svg
    #       }
    #   end

    # updated_changeset =
    #   Brando.Villain.replace_block_in_changeset(changeset, data_field, uid, new_block)

    # schema = changeset.data.__struct__
    # form_id = "#{schema.__naming__().singular}_form"

    # send_update(BrandoAdmin.Components.Form,
    #   id: form_id,
    #   action: :update_changeset,
    #   changeset: updated_changeset
    # )

    {:noreply, socket}
  end
end
