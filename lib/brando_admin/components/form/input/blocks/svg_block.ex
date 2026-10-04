defmodule BrandoAdmin.Components.Form.Input.Blocks.SvgBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input

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

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, assigns.ref_form[:uid].value)}
  end

  def handle_event("drop_svg", %{"code" => code}, socket) do
    new_data = Block.current_block_data_map(socket.assigns.block, nil, %{code: code})

    socket
    |> Block.commit_ref_data(ref_data: new_data, force_render: true)
    |> then(&{:noreply, &1})
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
          ref_form={@ref_form}
          config_open={@config_open}
          carried_config={[block_data[:code], block_data[:class]]}
        >
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              {@ref_description}
            <% end %>
          </:description>
          <:config>
            <Input.code id={"block-#{@uid}-svg-code"} field={block_data[:code]} label={gettext("Code")} />
            <Input.text field={block_data[:class]} label={gettext("Class")} />
          </:config>
          <div class="svg-block" phx-hook="Brando.SVGDrop" id={"block-#{@uid}-svg-drop"} data-target={@myself}>
            <%= if block_data[:code].value do %>
              <div class="svg-block-preview" id={"block-#{@uid}-svg-preview"}>
                {block_data[:code].value |> raw}
              </div>
            <% else %>
              <div class="empty">
                <figure>
                  <.icon name="code-xml" />
                </figure>
                <div class="instructions">
                  <button type="button" class="tiny" phx-click="open_block_config" phx-value-uid={@uid} phx-target={@target}>
                    {gettext("Configure SVG block")}
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end
end
