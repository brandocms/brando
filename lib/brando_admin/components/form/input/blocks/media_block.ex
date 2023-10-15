defmodule BrandoAdmin.Components.Form.Input.Blocks.MediaBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks

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
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@block[:uid].value}-wrapper"}
      data-block-index={@index}
      data-block-uid={@block[:uid].value}>
      <.inputs_for field={@block[:data]} :let={block_data}>
        <Blocks.block
          id={"block-#{@block[:uid].value}-base"}
          index={@index}
          is_ref?={@is_ref?}
          block_count={@block_count}
          base_form={@base_form}
          block={@block}
          belongs_to={@belongs_to}
          insert_module={@insert_module}
          duplicate_block={@duplicate_block}>
          <:description>
            <%= if @ref_description do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <div class="media-block">
            <div class="empty">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M11.27 12.216L15 6l8 15H2L9 8l2.27 4.216zm1.12 2.022L14.987 19h4.68l-4.77-8.942-2.507 4.18zM5.348 19h7.304L9 12.219 5.348 19zM5.5 8a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z"/></svg>
              </figure>
              <div class="instructions">
                <%= gettext "Select media type:" %>
              </div>
              <div class="buttons">
                <Form.array_inputs
                  :let={%{value: array_value, name: array_name}}
                  field={@block_data[:available_blocks]}>
                  <input type="hidden" name={array_name} value={array_value} />
                </Form.array_inputs>

                <%= if "picture" in block_data[:available_blocks].value do %>
                  <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="picture">
                    <%= gettext("Picture") %>
                  </button>
                  <.inputs_for field={@block_data[:template_picture]} :let={tpl_data}>
                    <Input.input type={:hidden} field={tpl_data[:picture_class]} uid={@block[:uid].value} id_prefix="block_data_tpl_picture" />
                    <Input.input type={:hidden} field={tpl_data[:img_class]} uid={@block[:uid].value} id_prefix="block_data_tpl_picture" />
                    <Input.input type={:hidden} field={tpl_data[:placeholder]} uid={@block[:uid].value} id_prefix="block_data_tpl_picture" />

                    <Form.array_inputs
                      :let={%{value: array_value, name: array_name}}
                      field={@block_data[:formats]}>
                      <input type="hidden" name={array_name} value={array_value} />
                    </Form.array_inputs>
                  </.inputs_for>
                <% end %>

                <%= if "video" in block_data[:available_blocks].value do %>
                  <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="video">
                    <%= gettext("Video") %>
                  </button>
                  <.inputs_for field={@block_data[:template_video]} :let={tpl_data}>
                    <Input.input type={:hidden} field={tpl_data[:opacity]} uid={@block[:uid].value} id_prefix="block_data_tpl_video" />
                    <Input.input type={:hidden} field={tpl_data[:autoplay]} uid={@block[:uid].value} id_prefix="block_data_tpl_video" />
                    <Input.input type={:hidden} field={tpl_data[:preload]} uid={@block[:uid].value} id_prefix="block_data_tpl_video" />
                    <Input.input type={:hidden} field={tpl_data[:play_button]} uid={@block[:uid].value} id_prefix="block_data_tpl_video" />
                  </.inputs_for>
                <% end %>

                <%= if "gallery" in block_data[:available_blocks].value do %>
                  <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="gallery">
                    <%= gettext("Gallery") %>
                  </button>
                  <.inputs_for field={@block_data[:template_gallery]} :let={tpl_data}>
                    <Input.input type={:hidden} field={tpl_data[:type]} uid={@block[:uid].value} id_prefix="block_data_tpl_gallery" />
                    <Input.input type={:hidden} field={tpl_data[:display]} uid={@block[:uid].value} id_prefix="block_data_tpl_gallery" />
                    <Input.input type={:hidden} field={tpl_data[:class]} uid={@block[:uid].value} id_prefix="block_data_tpl_gallery" />
                    <Input.input type={:hidden} field={tpl_data[:series_slug]} uid={@block[:uid].value} id_prefix="block_data_tpl_gallery" />
                    <Input.input type={:hidden} field={tpl_data[:lightbox]} uid={@block[:uid].value} id_prefix="block_data_tpl_gallery" />
                    <Input.input type={:hidden} field={tpl_data[:placeholder]} uid={@block[:uid].value} id_prefix="block_data_tpl_gallery" />
                    <Form.array_inputs
                      :let={%{value: array_value, name: array_name}}
                      field={@block_data[:formats]}>
                      <input type="hidden" name={array_name} value={array_value} />
                    </Form.array_inputs>
                  </.inputs_for>
                <% end %>
                <%= if "svg" in block_data[:available_blocks].value do %>
                  <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="svg">
                    SVG
                  </button>
                  <.inputs_for field={@block_data[:template_svg]} :let={tpl_data}>
                    <Input.input type={:hidden} field={tpl_data[:class]} label={gettext "Class"} uid={@block[:uid].value} id_prefix="block_data_tpl_svg" />
                  </.inputs_for>
                <% end %>
              </div>
            </div>
          </div>
        </Blocks.block>
      </.inputs_for>
    </div>
    """
  end

  def handle_event(
        "select_block",
        %{"block" => block},
        %{assigns: %{uid: uid, data_field: data_field, base_form: form}} = socket
      ) do
    # replace block
    changeset = form.source
    block_data = socket.assigns.block[:data]

    new_block =
      case block do
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

    updated_changeset =
      Brando.Villain.replace_block_in_changeset(changeset, data_field, uid, new_block)

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
