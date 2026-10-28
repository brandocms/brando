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
     |> assign_new(:superuser, fn -> false end)
     |> assign(:uid, assigns.ref_form[:uid].value)}
  end

  # SVG code is markup only a superuser changes (`Brando.Content.RefGuard`)
  def handle_event("drop_svg", _params, %{assigns: %{superuser: false}} = socket), do: {:noreply, socket}

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
          <:config :if={@superuser}>
            <Input.code id={"block-#{@uid}-svg-code"} field={block_data[:code]} label={gettext("Code")} />
            <Input.text field={block_data[:class]} label={gettext("Class")} />
          </:config>
          <div
            class="svg-block"
            phx-hook={@superuser && "Brando.SVGDrop"}
            id={"block-#{@uid}-svg-drop"}
            data-target={@myself}
          >
            <%= if block_data[:code].value do %>
              <div class="svg-block-preview" id={"block-#{@uid}-svg-preview"}>
                <img src={svg_preview_src(block_data[:code].value)} alt="" />
              </div>
            <% else %>
              <div class="empty">
                <figure>
                  <.icon name="code-xml" />
                </figure>
                <div class="instructions">
                  <button
                    :if={@superuser}
                    type="button"
                    class="btn btn--sm"
                    phx-click="open_block_config"
                    phx-value-uid={@uid}
                    phx-target={@target}
                  >
                    {gettext("Configure SVG block")}
                  </button>
                  <p :if={!@superuser}>{gettext("A superuser maintains this SVG.")}</p>
                </div>
              </div>
            <% end %>
          </div>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  # The code is an editor's markup. As an image the browser draws it without
  # running its scripts or handlers in the admin page. An image is a
  # standalone XML document, which needs the namespaces the HTML parser
  # supplies for inline code, so a root without them gets them.
  defp svg_preview_src(code), do: "data:image/svg+xml;base64," <> :base64.encode(with_namespaces(code))

  defp with_namespaces(code) do
    # The root's start tag: `>` inside a quoted value does not end it, and a
    # prefixed root (`<svg:svg>`) declares its own namespaces.
    case Regex.run(~r/<svg(?=[\s\/>])(?:"[^"]*"|'[^']*'|[^"'>])*>/i, code, return: :index) do
      [{start, length}] ->
        root = binary_part(code, start, length)
        svg = if root =~ ~r/\sxmlns\s*=/, do: "", else: ~s( xmlns="http://www.w3.org/2000/svg")
        xlink = if root =~ ~r/\sxmlns:xlink\s*=/, do: "", else: ~s( xmlns:xlink="http://www.w3.org/1999/xlink")
        at = start + 4
        binary_part(code, 0, at) <> svg <> xlink <> binary_part(code, at, byte_size(code) - at)

      nil ->
        code
    end
  end
end
