defmodule BrandoAdmin.Components.Content do
  use BrandoAdmin, :component

  def header(assigns) do
    assigns = assign_new(assigns, :inner_block, fn -> nil end)

    ~H"""
    <header id="content-header" data-moonwalk-run="brandoHeader">
      <div class="content">
        <section class="main">
          <h1>
            <%= @title %>
          </h1>
          <h3>
            <%= @subtitle %>
          </h3>
        </section>
        <section class="actions">
          <%= if @inner_block do %>
            <%= render_slot @inner_block %>
          <% end %>
        </section>
      </div>
    </header>
    """
  end
end
