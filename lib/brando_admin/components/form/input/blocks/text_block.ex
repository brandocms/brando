defmodule BrandoAdmin.Components.Form.Input.Blocks.TextBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  import Ecto.Changeset
  import BrandoAdmin.ErrorHelpers
  alias Surface.Components.Form.TextInput
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.Radios

  prop block, :form
  prop base_form, :form
  prop index, :integer
  prop block_count, :integer
  prop is_ref?, :boolean, default: false
  prop ref_description, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data text_type, :string

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(assigns.block, :uid))
     |> assign(:text_type, v(assigns.block, :data).type)}
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
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>
          {#if @ref_description}
            {@ref_description}
          {#else}
            {@text_type}
          {/if}
        </:description>
        <:config>
          {#for block_data <- inputs_for(@block, :data)}
            <Radios
              form={block_data}
              field={:type}
              label="Type"
              options={[
                %{label: "Paragraph", value: "paragraph"},
                %{label: "Lede", value: "lede"},
              ]} />
          {/for}
        </:config>
        {#for block_data <- inputs_for(@block, :data)}
          <div class={"text-block", @text_type}>
            <div class="tiptap-wrapper">
              <HiddenInput
                class="tiptap-text"
                form={block_data}
                field={:text}
                opts={phx_debounce: 750}
              />
              <div
                id={"#{@uid}-text"}
                data-block-uid={@id}
                phx-update="ignore"
                phx-hook="Brando.TipTap"
                data-name="TipTap"
                data-props={Jason.encode!(%{content: v(block_data, :text)})}>
              </div>
            </div>
            <HiddenInput form={block_data} field={:extensions} />
          </div>
        {/for}
      </Block>
    </div>
    """
  end

  def handle_event("show_link_modal", %{"id" => id}, socket) do
    Modal.show(id)
    {:noreply, socket}
  end

  def handle_event("update_link", %{"id" => modal_id}, %{assigns: %{id: id}} = socket) do
    Modal.hide(modal_id)
    {:noreply, push_event(socket, "tiptap:link:#{id}", %{})}
  end

  def handle_event("show_button_modal", %{"id" => id}, socket) do
    Modal.show(id)
    {:noreply, socket}
  end

  def handle_event("update_button", %{"id" => modal_id}, %{assigns: %{id: id}} = socket) do
    Modal.hide(modal_id)
    {:noreply, push_event(socket, "tiptap:button:#{id}", %{})}
  end
end
