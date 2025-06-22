defmodule BrandoAdmin.Components.Form.Input.Blocks.MapBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias Ecto.Changeset

  # prop base_form, :any
  # prop data_field, :atom
  # prop block, :any
  # prop block_count, :integer
  # prop index, :any
  # prop is_ref?, :boolean, default: false
  # prop belongs_to, :string

  # prop insert_module, :event, required: true
  # prop duplicate_block, :event, required: true

  # data block_data, :any
  # data uid, :string

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(:uid, assigns.ref_form[:uid].value)
    |> then(&{:ok, &1})
  end

  def render(assigns) do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Block.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>{block_data[:source].value}</:description>
          <:config>
            <Input.input type={:hidden} field={block_data[:embed_url]} />
            <Input.input type={:hidden} field={block_data[:source]} />

            <div id={"block-#{@uid}-mapUrl"} phx-hook="Brando.MapURLParser" phx-update="ignore" data-target={@myself}>
              <small>
                {gettext("To embed a map in your content, please follow these steps:")}<br /><br />
                <strong><%= gettext "Enter the Embed URL" %></strong>: {gettext(
                  "Input the full URL of the map you want to embed. This could be from services like Google Maps or any other map provider that supports embedding."
                )}<br />
                <strong><%= gettext "Get Map Info" %></strong>: {gettext(
                  "Click the 'Get map info' button to fetch the map details and render it within your block."
                )}<br /><br />
                {gettext(
                  "Ensure the URL is correct and fully formatted. This will enable a seamless integration and accurate display of the map in your content."
                )}<br /><br />
              </small>
              <textarea id={"block-#{@uid}-url"} type="text" class="text monospace" rows="3"></textarea>
              <button id={"block-#{@uid}-button"} type="button" class="secondary small">
                {gettext("Get map info")}
              </button>
            </div>
          </:config>
          <div class="map-block">
            <%= if block_data[:embed_url].value do %>
              <%= case block_data[:source].value do %>
                <% :gmaps -> %>
                  <div class="map-content">
                    <iframe
                      src={block_data[:embed_url].value}
                      width="600"
                      height="450"
                      frameborder="0"
                      style="border:0"
                      allowfullscreen
                    >
                    </iframe>
                  </div>
              <% end %>
            <% else %>
              <div class="empty">
                <figure>
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                    <path fill="none" d="M0 0h24v24H0z" /><path d="M12 20.9l4.95-4.95a7 7 0 1 0-9.9 0L12 20.9zm0 2.828l-6.364-6.364a9 9 0 1 1 12.728 0L12 23.728zM12 13a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm0 2a4 4 0 1 1 0-8 4 4 0 0 1 0 8z" />
                  </svg>
                </figure>
                <div class="instructions">
                  <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}>
                    {gettext("Configure map block")}
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

  def handle_event("url", %{"source" => source, "embedUrl" => embed_url}, socket) do
    target = socket.assigns.target
    ref_name = socket.assigns.ref_name

    new_data = %{
      embed_url: embed_url,
      source: String.to_existing_atom(source)
    }

    updated_data = update_block_data(socket, new_data)
    send_update(target, %{event: "update_ref_data", ref_data: updated_data, ref_name: ref_name})

    {:noreply, socket}
  end

  defp update_block_data(socket, new_data) do
    block = socket.assigns.block
    block_data_cs = Block.get_block_data_changeset(block)
    block_data = Changeset.apply_changes(block_data_cs)
    data_map = Map.from_struct(block_data)
    Map.merge(data_map, new_data)
  end
end
