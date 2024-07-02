defmodule BrandoAdmin.Components.Form.Input.Blocks.SvgBlock do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  import Brando.Gettext
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
     |> assign(:uid, assigns.block[:uid].value)}
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
            <%= if @ref_description not in ["", nil] do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <:config>
            <Input.code
              id={"block-#{@uid}-svg-code"}
              field={block_data[:code]}
              label={gettext("Code")}
            />
            <Input.text field={block_data[:class]} label={gettext("Class")} />
          </:config>
          <div
            class="svg-block"
            phx-hook="Brando.SVGDrop"
            id={"block-#{@uid}-svg-drop"}
            data-target={@myself}
          >
            <%= if block_data[:code].value do %>
              <div class="svg-block-preview" id={"block-#{@uid}-svg-preview"}>
                <%= block_data[:code].value |> raw %>
              </div>
            <% else %>
              <div class="empty">
                <figure>
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                    <path fill="none" d="M0 0h24v24H0z" /><path d="M24 12l-5.657 5.657-1.414-1.414L21.172 12l-4.243-4.243 1.414-1.414L24 12zM2.828 12l4.243 4.243-1.414 1.414L0 12l5.657-5.657L7.07 7.757 2.828 12zm6.96 9H7.66l6.552-18h2.128L9.788 21z" />
                  </svg>
                </figure>
                <div class="instructions">
                  <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}>
                    <%= gettext("Configure SVG block") %>
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
