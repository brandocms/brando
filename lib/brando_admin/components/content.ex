defmodule BrandoAdmin.Component.Content do
  use Phoenix.Component

  def header(assigns) do
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
          <%= render_slot @inner_block %>
        </section>
      </div>
    </header>
    """
  end
end
