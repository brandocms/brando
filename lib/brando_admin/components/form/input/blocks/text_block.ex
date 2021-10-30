defmodule BrandoAdmin.Components.Form.Input.Blocks.TextBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.Radios

  prop block, :form
  prop base_form, :form
  prop index, :integer
  prop block_count, :integer
  prop is_ref?, :boolean, default: false
  prop ref_description, :string
  prop belongs_to, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data text_type, :string
  data initial_props, :map

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(assigns.block, :uid))
     |> assign(:text_type, v(assigns.block, :data).type)
     |> assign_new(:initial_props, fn ->
       Jason.encode!(%{content: v(assigns.block, :data).text})
     end)}
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
              opts={options: [
                %{label: "Paragraph", value: "paragraph"},
                %{label: "Lede", value: "lede"},
              ]} />
          {/for}
        </:config>
        {#for block_data <- inputs_for(@block, :data)}
          <div class={"text-block", @text_type}>
            <div class="tiptap-wrapper" id={"#{@uid}-rich-text-wrapper"}>
              <div
                id={"#{@uid}-rich-text"}
                data-block-uid={@id}
                phx-hook="Brando.TipTap"
                data-name="TipTap"
                data-props={@initial_props}>
                <div
                  id={"#{@uid}-rich-text-target-wrapper"}
                  class="tiptap-target-wrapper"
                  phx-update="ignore">
                  <div
                    id={"#{@uid}-rich-text-target"}
                    class="tiptap-target">
                  </div>
                </div>
              </div>
            </div>
            {hidden_input block_data, :text, class: "tiptap-text", phx_debounce: 750}
            {hidden_input block_data, :extensions}
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
