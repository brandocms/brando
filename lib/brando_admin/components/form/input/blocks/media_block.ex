defmodule BrandoAdmin.Components.Form.Input.Blocks.MediaBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block

  # prop block, :form
  # prop base_form, :form
  # prop index, :integer
  # prop block_count, :integer
  # prop is_ref?, :boolean, default: false
  # prop ref_description, :string
  # prop belongs_to, :string
  # prop data_field, :atom

  # prop insert_block, :event, required: true
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
     |> assign(:uid, v(assigns.block, :uid))}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <.live_component module={Block}
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
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
                  <Input.input type={:hidden} form={tpl_data} field={:picture_class} />
                  <Input.input type={:hidden} form={tpl_data} field={:img_class} />
                  <Input.input type={:hidden} form={tpl_data} field={:placeholder} />

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
                  <Input.input type={:hidden} form={tpl_data} field={:opacity} />
                  <Input.input type={:hidden} form={tpl_data} field={:autoplay} />
                  <Input.input type={:hidden} form={tpl_data} field={:preload} />
                  <Input.input type={:hidden} form={tpl_data} field={:play_button} />
                <% end %>
              <% end %>

              <%= if "gallery" in @available_blocks do %>
                <button type="button" class="tiny" phx-click={JS.push("select_block", target: @myself)} phx-value-block="gallery"><%= gettext("Gallery") %></button>
                <%= for tpl_data <- inputs_for(@block_data, :template_gallery) do %>
                  <Input.input type={:hidden} form={tpl_data} field={:type} />
                  <Input.input type={:hidden} form={tpl_data} field={:display} />
                  <Input.input type={:hidden} form={tpl_data} field={:class} />
                  <Input.input type={:hidden} form={tpl_data} field={:series_slug} />
                  <Input.input type={:hidden} form={tpl_data} field={:lightbox} />
                  <Input.input type={:hidden} form={tpl_data} field={:placeholder} />
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
                  <Input.input type={:hidden} form={tpl_data} field={:class} label={gettext "Class"} />
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </.live_component>
    </div>
    """
  end

  def handle_event(
        "select_block",
        %{"block" => block},
        %{assigns: %{uid: uid, data_field: data_field, base_form: form, block_data: block_data}} =
          socket
      ) do
    # replace block
    changeset = form.source

    new_block =
      case block do
        "picture" ->
          data_tpl = input_value(block_data, :template_picture)

          %Brando.Blueprint.Villain.Blocks.PictureBlock{
            uid: Brando.Utils.generate_uid(),
            type: "picture",
            data: data_tpl
          }

        "video" ->
          data_tpl = input_value(block_data, :template_video)

          %Brando.Blueprint.Villain.Blocks.VideoBlock{
            uid: Brando.Utils.generate_uid(),
            type: "video",
            data: data_tpl
          }

        "gallery" ->
          data_tpl = input_value(block_data, :template_gallery)

          %Brando.Blueprint.Villain.Blocks.GalleryBlock{
            uid: Brando.Utils.generate_uid(),
            type: "gallery",
            data: data_tpl
          }

        "svg" ->
          data_tpl = input_value(block_data, :template_svg)

          %Brando.Blueprint.Villain.Blocks.SvgBlock{
            uid: Brando.Utils.generate_uid(),
            type: "svg",
            data: data_tpl
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
