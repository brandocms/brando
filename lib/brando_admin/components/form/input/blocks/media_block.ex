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

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    block_data = List.first(inputs_for(assigns.block, :data))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:available_blocks, input_value(block_data, :available_blocks))
     |> assign(:uid, v(assigns.block, :uid))
     |> assign_new(:template_picture, fn -> input_value(block_data, :template_picture) end)
     |> assign_new(:template_gallery, fn -> input_value(block_data, :template_gallery) end)
     |> assign_new(:template_video, fn -> input_value(block_data, :template_video) end)
     |> assign_new(:template_svg, fn -> input_value(block_data, :template_svg) end)}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
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
                let={%{value: array_value, name: array_name}}
                form={@block_data}
                for={:available_blocks}>
                <input type="hidden" name={array_name} value={array_value} />
              </Form.array_inputs>

              <%= if "picture" in @available_blocks do %>
                <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="picture"><%= gettext("Picture") %></button>
                <%= for tpl_data <- inputs_for(@block_data, :template_picture) do %>
                  <Input.input type={:hidden} form={tpl_data} field={:picture_class} uid={@uid} id_prefix="block_data_tpl_picture" />
                  <Input.input type={:hidden} form={tpl_data} field={:img_class} uid={@uid} id_prefix="block_data_tpl_picture" />
                  <Input.input type={:hidden} form={tpl_data} field={:placeholder} uid={@uid} id_prefix="block_data_tpl_picture" />

                  <Form.array_inputs
                    let={%{value: array_value, name: array_name}}
                    form={@block_data}
                    for={:formats}>
                    <input type="hidden" name={array_name} value={array_value} />
                  </Form.array_inputs>
                <% end %>
              <% end %>

              <%= if "video" in @available_blocks do %>
                <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="video"><%= gettext("Video") %></button>
                <%= for tpl_data <- inputs_for(@block_data, :template_video) do %>
                  <Input.input type={:hidden} form={tpl_data} field={:opacity} uid={@uid} id_prefix="block_data_tpl_video" />
                  <Input.input type={:hidden} form={tpl_data} field={:autoplay} uid={@uid} id_prefix="block_data_tpl_video" />
                  <Input.input type={:hidden} form={tpl_data} field={:preload} uid={@uid} id_prefix="block_data_tpl_video" />
                  <Input.input type={:hidden} form={tpl_data} field={:play_button} uid={@uid} id_prefix="block_data_tpl_video" />
                <% end %>
              <% end %>

              <%= if "gallery" in @available_blocks do %>
                <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="gallery"><%= gettext("Gallery") %></button>
                <%= for tpl_data <- inputs_for(@block_data, :template_gallery) do %>
                  <Input.input type={:hidden} form={tpl_data} field={:type} uid={@uid} id_prefix="block_data_tpl_gallery" />
                  <Input.input type={:hidden} form={tpl_data} field={:display} uid={@uid} id_prefix="block_data_tpl_gallery" />
                  <Input.input type={:hidden} form={tpl_data} field={:class} uid={@uid} id_prefix="block_data_tpl_gallery" />
                  <Input.input type={:hidden} form={tpl_data} field={:series_slug} uid={@uid} id_prefix="block_data_tpl_gallery" />
                  <Input.input type={:hidden} form={tpl_data} field={:lightbox} uid={@uid} id_prefix="block_data_tpl_gallery" />
                  <Input.input type={:hidden} form={tpl_data} field={:placeholder} uid={@uid} id_prefix="block_data_tpl_gallery" />
                  <Form.array_inputs
                    let={%{value: array_value, name: array_name}}
                    form={@block_data}
                    for={:formats}>
                    <input type="hidden" name={array_name} value={array_value} />
                  </Form.array_inputs>
                <% end %>
              <% end %>
              <%= if "svg" in @available_blocks do %>
                <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="svg">SVG</button>
                <%= for tpl_data <- inputs_for(@block_data, :template_svg) do %>
                  <Input.input type={:hidden} form={tpl_data} field={:class} label={gettext "Class"} uid={@uid} id_prefix="block_data_tpl_svg" />
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </Blocks.block>
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

    new_block =
      case block do
        "picture" ->
          %Brando.Villain.Blocks.PictureBlock{
            uid: Brando.Utils.generate_uid(),
            type: "picture",
            data: socket.assigns.template_picture
          }
          |> IO.inspect(pretty: true)

        "video" ->
          %Brando.Villain.Blocks.VideoBlock{
            uid: Brando.Utils.generate_uid(),
            type: "video",
            data: socket.assigns.template_video
          }

        "gallery" ->
          %Brando.Villain.Blocks.GalleryBlock{
            uid: Brando.Utils.generate_uid(),
            type: "gallery",
            data: socket.assigns.template_gallery
          }

        "svg" ->
          %Brando.Villain.Blocks.SvgBlock{
            uid: Brando.Utils.generate_uid(),
            type: "svg",
            data: socket.assigns.template_svg
          }
      end

    updated_changeset =
      Brando.Villain.replace_block_in_changeset(changeset, data_field, uid, new_block)

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
