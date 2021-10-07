defmodule BrandoAdmin.Components.Form.Input.Blocks.SvgBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block

  prop block, :form
  prop base_form, :form
  prop index, :integer
  prop block_count, :integer
  prop is_ref?, :boolean, default: false
  prop ref_description, :string
  prop belongs_to, :string
  prop data_field, :atom

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data text_type, :string
  data initial_props, :map
  data block_data, :map

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    block_data = List.first(inputs_for(assigns.block, :data))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:uid, v(assigns.block, :uid))}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-wrapper"}
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
        duplicate_block={@duplicate_block}>
        <:description>
          {#if @ref_description}
            {@ref_description}
          {/if}
        </:description>
        <:config>
          <Input.Code id={"#{@uid}-svg-code"} form={@block_data} field={:code} />
          <Input.Text form={@block_data} field={:class} />
        </:config>
        <div class="svg-block" phx-hook="Brando.SVGDrop" id={"#{@uid}-svg-drop"} data-target={@myself}>
          {#if v(@block_data, :code)}
            {v(@block_data, :code) |> raw}
          {#else}
            <div class="empty">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M24 12l-5.657 5.657-1.414-1.414L21.172 12l-4.243-4.243 1.414-1.414L24 12zM2.828 12l4.243 4.243-1.414 1.414L0 12l5.657-5.657L7.07 7.757 2.828 12zm6.96 9H7.66l6.552-18h2.128L9.788 21z"/></svg>
              </figure>
              <div class="instructions">
                <button type="button" class="tiny" :on-click="show_config">Configure SVG block</button>
              </div>
            </div>
          {/if}
        </div>
      </Block>
    </div>
    """
  end

  def handle_event("show_config", _, %{assigns: %{uid: uid}} = socket) do
    Modal.show("#{uid}_config")
    {:noreply, socket}
  end

  def handle_event(
        "drop_svg",
        %{"code" => code},
        %{assigns: %{uid: uid, data_field: data_field, base_form: form}} = socket
      ) do
    # replace block
    changeset = form.source

    new_data = %{
      code: code
    }

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, uid, %{data: new_data})

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
