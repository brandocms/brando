defmodule BrandoAdmin.Components.Form.Input.Blocks.MapBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Modal

  prop base_form, :any
  prop data_field, :atom
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop is_ref?, :boolean, default: false
  prop belongs_to, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data block_data, :any
  data uid, :string

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def update(assigns, socket) do
    block_data =
      assigns.block
      |> inputs_for(:data)
      |> List.first()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(assigns.block, :uid))
     |> assign(:block_data, block_data)}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-wrapper"}
      class="map-block"
      data-block-index={@index}
      data-block-uid={@uid}>
      <Block
        id={"#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}
        wide_config>
        <:description>{v(@block_data, :source)}</:description>
        <:config>
          {hidden_input @block_data, :embed_url}
          {hidden_input @block_data, :source}

          <div id={"#{@uid}-mapUrl"} phx-hook="Brando.MapURLParser" phx-update="ignore" data-target={@myself}>
            {gettext("Enter the map's embed URL:")}
            <input id={"#{@uid}-url"} type="text" class="text">
            <button id={"#{@uid}-button"} type="button" class="secondary small">
              {gettext("Get map info")}
            </button>
          </div>
        </:config>
        {#if v(@block_data, :embed_url)}
          {#case v(@block_data, :source)}
            {#match :gmaps}
              <div class="map-content">
                <iframe
                  src={v(@block_data, :embed_url)}}
                  width="600"
                  height="450"
                  frameborder="0"
                  style="border:0"
                  allowfullscreen></iframe>
              </div>
          {/case}
        {#else}
          <div class="empty">
            <figure>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 20.9l4.95-4.95a7 7 0 1 0-9.9 0L12 20.9zm0 2.828l-6.364-6.364a9 9 0 1 1 12.728 0L12 23.728zM12 13a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm0 2a4 4 0 1 1 0-8 4 4 0 0 1 0 8z"/></svg>
            </figure>
            <div class="instructions">
              <button type="button" class="tiny" :on-click="show_config">{gettext "Configure map block"}</button>
            </div>
          </div>
        {/if}
      </Block>
    </div>
    """
  end

  def handle_event("show_config", _, socket) do
    Modal.show("#{socket.assigns.uid}_config")
    {:noreply, socket}
  end

  def handle_event("hide_config", _, socket) do
    Modal.hide("#{socket.assigns.uid}_config")
    {:noreply, socket}
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
      updated_changeset: updated_changeset
    )

    Modal.hide("#{socket.assigns.uid}_config")

    {:noreply, socket}
  end
end
