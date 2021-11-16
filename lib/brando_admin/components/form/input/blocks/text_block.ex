defmodule BrandoAdmin.Components.Form.Input.Blocks.TextBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.Radios

  # prop block, :form
  # prop base_form, :form
  # prop index, :integer
  # prop block_count, :integer
  # prop is_ref?, :boolean, default: false
  # prop ref_description, :string
  # prop belongs_to, :string

  # prop insert_block, :event, required: true
  # prop duplicate_block, :event, required: true

  # data uid, :string
  # data text_type, :string
  # data initial_props, :map

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
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <.live_component
        module={Block}
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
          <% else %>
            <%= @text_type %>
          <% end %>
        </:description>
        <:config>
          <%= for block_data <- inputs_for(@block, :data) do %>
            <Radios.render
              form={block_data}
              field={:type}
              label="Type"
              opts={[options: [
                %{label: "Paragraph", value: "paragraph"},
                %{label: "Lede", value: "lede"},
              ]]} />
          <% end %>
        </:config>
        <%= for block_data <- inputs_for(@block, :data) do %>
          <div class={render_classes(["text-block", @text_type])}>
            <div class="tiptap-wrapper" id={"block-#{@uid}-rich-text-wrapper"}>
              <div
                id={"block-#{@uid}-rich-text"}
                data-block-uid={@id}
                phx-hook="Brando.TipTap"
                data-name="TipTap"
                data-props={@initial_props}>
                <div
                  id={"block-#{@uid}-rich-text-target-wrapper"}
                  class="tiptap-target-wrapper"
                  phx-update="ignore">
                  <div
                    id={"block-#{@uid}-rich-text-target"}
                    class="tiptap-target">
                  </div>
                </div>
              </div>
            </div>
            <%= hidden_input block_data, :text, class: "tiptap-text", phx_debounce: 750 %>
            <%= hidden_input block_data, :extensions %>
          </div>
        <% end %>
      </.live_component>
    </div>
    """
  end
end
