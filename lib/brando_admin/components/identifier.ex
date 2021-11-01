defmodule BrandoAdmin.Components.Identifier do
  use Phoenix.Component
  use Phoenix.HTML

  # prop identifier, :map
  # prop identifier_form, :form
  # prop param, :any
  # prop select, :event
  # prop remove, :event
  # prop selected_identifiers, :list, default: []

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  def render(%{identifier: identifier} = assigns) when not is_nil(identifier) do
    ~H"""
    <article
      class={[identifier: true, selected: @identifier in @selected_identifiers]}
      :on-click={@select}
      phx-value-param={@param}>

      <section class="cover-wrapper">
        <div class="cover">
          <img src={@identifier.cover || "/images/admin/avatar.svg"}>
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            <%= @identifier.title %>
          </div>
          <div class="meta-info">
            <%= @identifier.type %>
          </div>
        </div>
      </section>
      <%= if @remove do %>
        <div class="remove">
          <button type="button" :on-click={@remove} phx-value-param={@param}>&times;</button>
        </div>
      <% end %>
    </article>
    """
  end

  def render(%{identifier_form: identifier_form} = assigns) when not is_nil(identifier_form) do
    ~H"""
    <article
      class={[identifier: true, selected: @identifier_form in @selected_identifiers]}
      :on-click={@select}
      phx-value-param={@param}>

      <section class="cover-wrapper">
        <div class="cover">
          <img src={input_value(@identifier_form, :cover) || "/images/admin/avatar.svg"}>
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            <%= input_value(@identifier_form, :title) %>
          </div>
          <div class="meta-info">
            <%= input_value(@identifier_form, :type) %>
          </div>
        </div>
      </section>
      <%= if @remove do %>
        <div class="remove">
          <button type="button" :on-click={@remove} phx-value-param={@param}>&times;</button>
        </div>
      <% end %>
    </article>
    """
  end
end
