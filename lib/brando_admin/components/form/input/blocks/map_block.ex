defmodule BrandoAdmin.Components.Form.Input.Blocks.MapBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks

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
    block_data =
      assigns.block
      |> inputs_for(:data)
      |> List.first()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, assigns.block[:uid].value)
     |> assign(:block_data, block_data)}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="map-block"
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
        duplicate_block={@duplicate_block}
        wide_config>
        <:description><%= v(@block_data, :source) %></:description>
        <:config>
          <Input.input type={:hidden} field={@block_data[:embed_url]} />
          <Input.input type={:hidden} field={@block_data[:source]} />

          <div id={"block-#{@uid}-mapUrl"} phx-hook="Brando.MapURLParser" phx-update="ignore" data-target={@myself}>
            <%= gettext("Enter the map's embed URL:") %>
            <input id={"block-#{@uid}-url"} type="text" class="text">
            <button id={"block-#{@uid}-button"} type="button" class="secondary small">
              <%= gettext("Get map info") %>
            </button>
          </div>
        </:config>
        <%= if v(@block_data, :embed_url) do %>
          <%= case v(@block_data, :source) do %>
            <% :gmaps -> %>
              <div class="map-content">
                <iframe
                  src={v(@block_data, :embed_url)}}
                  width="600"
                  height="450"
                  frameborder="0"
                  style="border:0"
                  allowfullscreen></iframe>
              </div>
          <% end %>
        <% else %>
          <div class="empty">
            <figure>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 20.9l4.95-4.95a7 7 0 1 0-9.9 0L12 20.9zm0 2.828l-6.364-6.364a9 9 0 1 1 12.728 0L12 23.728zM12 13a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm0 2a4 4 0 1 1 0-8 4 4 0 0 1 0 8z"/></svg>
            </figure>
            <div class="instructions">
              <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}><%= gettext "Configure map block" %></button>
            </div>
          </div>
        <% end %>
      </Blocks.block>
    </div>
    """
  end

  def handle_event(
        "url",
        %{"source" => source, "embedUrl" => embed_url},
        %{assigns: %{uid: uid, data_field: data_field, base_form: form}} = socket
      ) do
    # replace block
    changeset = form.source

    new_data = %{
      embed_url: embed_url,
      source: String.to_existing_atom(source)
    }

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, uid, %{data: new_data})

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
