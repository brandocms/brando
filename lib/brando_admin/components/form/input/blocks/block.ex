defmodule BrandoAdmin.Components.Form.Input.Blocks.Block do
  @moduledoc """
  The base block
  """
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Label

  prop block, :any
  prop base_form, :any
  prop index, :integer
  prop block_count, :integer
  prop is_ref?, :boolean, default: false
  prop is_entry?, :boolean, default: false
  @doc "A slight hint of background color for the block. Often used with Containers/sections"
  prop bg_color, :string
  prop belongs_to, :string
  prop wide_config, :boolean, default: false

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data last_block?, :boolean, default: false
  data uid, :string
  data type, :string
  data hidden, :boolean
  data marked_as_deleted, :boolean

  slot default, required: true
  slot config
  slot config_footer
  slot description
  slot instructions
  slot render

  def update(assigns, socket) do
    uid = input_value(assigns.block, :uid) || Brando.Utils.generate_uid()
    type = input_value(assigns.block, :type) || (assigns.is_entry? && "entry")

    {:ok,
     socket
     |> assign(:bg_color, assigns[:bg_color])
     |> assign(:last_block?, last_block?(assigns))
     |> assign(:uid, uid)
     |> assign(:type, type)
     |> assign(:hidden, input_value(assigns.block, :hidden))
     |> assign(:marked_as_deleted, input_value(assigns.block, :marked_as_deleted))
     |> assign(assigns)}
  end

  def render(assigns) do
    ~F"""
    <div
      data-block-uid={@uid}
      class={
        "base-block",
        hidden: @hidden,
        deleted: @marked_as_deleted
      }>
      <Blocks.Plus
        :if={!@is_ref? and !@is_entry?}
        index={@index}
        click={@insert_block} />

      <Modal title="Configure" id={"#{@uid}_config"} wide={@wide_config}>
        <#slot name="config" />
        <:footer>
          <button type="button" class="primary" :on-click="hide_config_modal" phx-value-id={"#{@uid}_config"}>
            {gettext "Close"}
          </button>
          <#slot name="config_footer" />
        </:footer>
      </Modal>

      {hidden_input @block, :uid}
      {hidden_input @block, :type}

      <div
        id={@uid}
        data-block-uid={@uid}
        data-block-type={@type}
        style={"background-color": @bg_color}
        class={"block", ref_block: @is_ref?}
        phx-hook="Brando.Block">

        <div class="block-description" id={"#{@uid}-block-description"}>
          <Label form={@block} field={:hidden} class="switch small inverse">
            {checkbox @block, :hidden}
            <div class="slider round"></div>
          </Label>
          <span class="block-type">{@type}</span> &rarr; <#slot name="description" />
        </div>
        <div class="block-content" id={"#{@uid}-block-content"}>
          <#slot />
        </div>
        {#if slot_assigned?(:render)}
          <div class="block-render">
            <div class="block-render-preview">Preview &darr;</div>
            <#slot name="render" />
          </div>
        {/if}
        <div class="block-actions" id={"#{@uid}-block-actions"}>
          <div
            :if={!@is_ref?}
            class="block-action move"
            data-sortable-group={@belongs_to}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M11 11V5.828L9.172 7.657 7.757 6.243 12 2l4.243 4.243-1.415 1.414L13 5.828V11h5.172l-1.829-1.828 1.414-1.415L22 12l-4.243 4.243-1.414-1.415L18.172 13H13v5.172l1.828-1.829 1.415 1.414L12 22l-4.243-4.243 1.415-1.414L11 18.172V13H5.828l1.829 1.828-1.414 1.415L2 12l4.243-4.243 1.414 1.415L5.828 11z"/></svg>
          </div>
          <div
            :if={slot_assigned?(:instructions)}
            class="block-action help"
            :on-click="toggle_help">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16zm-1-5h2v2h-2v-2zm2-1.645V14h-2v-1.5a1 1 0 0 1 1-1 1.5 1.5 0 1 0-1.471-1.794l-1.962-.393A3.501 3.501 0 1 1 13 13.355z"/></svg>
          </div>

          <button
            :if={!@is_ref?}
            type="button"
            phx-value-block_uid={@uid}
            class="block-action duplicate"
            :on-click={@duplicate_block}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M7 6V3a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-3v3c0 .552-.45 1-1.007 1H4.007A1.001 1.001 0 0 1 3 21l.003-14c0-.552.45-1 1.007-1H7zM5.003 8L5 20h10V8H5.003zM9 6h8v10h2V4H9v2z"/></svg>
          </button>
          <button
            :if={slot_assigned?(:config)}
            type="button"
            class="block-action config"
            phx-value-id={"#{@uid}_config"}
            :on-click="show_config_modal">
            {#if @type == "module"}
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M8.595 12.812a3.51 3.51 0 0 1 0-1.623l-.992-.573 1-1.732.992.573A3.496 3.496 0 0 1 11 8.645V7.5h2v1.145c.532.158 1.012.44 1.405.812l.992-.573 1 1.732-.992.573a3.51 3.51 0 0 1 0 1.622l.992.573-1 1.732-.992-.573a3.496 3.496 0 0 1-1.405.812V16.5h-2v-1.145a3.496 3.496 0 0 1-1.405-.812l-.992.573-1-1.732.992-.572zM12 13.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM15 4H5v16h14V8h-4V4zM3 2.992C3 2.444 3.447 2 3.999 2H16l5 5v13.993A1 1 0 0 1 20.007 22H3.993A1 1 0 0 1 3 21.008V2.992z"/></svg>
            {#else}
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M8.686 4l2.607-2.607a1 1 0 0 1 1.414 0L15.314 4H19a1 1 0 0 1 1 1v3.686l2.607 2.607a1 1 0 0 1 0 1.414L20 15.314V19a1 1 0 0 1-1 1h-3.686l-2.607 2.607a1 1 0 0 1-1.414 0L8.686 20H5a1 1 0 0 1-1-1v-3.686l-2.607-2.607a1 1 0 0 1 0-1.414L4 8.686V5a1 1 0 0 1 1-1h3.686zM6 6v3.515L3.515 12 6 14.485V18h3.515L12 20.485 14.485 18H18v-3.515L20.485 12 18 9.515V6h-3.515L12 3.515 9.515 6H6zm6 10a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm0-2a2 2 0 1 0 0-4 2 2 0 0 0 0 4z"/></svg>
            {/if}
          </button>

          <Label
            :if={!@is_ref?}
            form={@block}
            field={:marked_as_deleted}
            class="block-action toggler">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z"/></svg>
            {checkbox @block, :marked_as_deleted}
          </Label>
        </div>
      </div>
      {#if @last_block?}
        <Blocks.Plus
          :if={!@is_ref? and !@is_entry?}
          index={@index + 1}
          click={@insert_block} />
      {/if}
    </div>
    """
  end

  def handle_event("show_config_modal", %{"id" => modal_id}, socket) do
    Modal.show(modal_id)
    {:noreply, socket}
  end

  def handle_event("hide_config_modal", %{"id" => modal_id}, socket) do
    Modal.hide(modal_id)
    {:noreply, socket}
  end

  defp last_block?(%{index: index, block_count: block_count}) when index + 1 == block_count do
    true
  end

  defp last_block?(_), do: false
end
