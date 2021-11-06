defmodule BrandoAdmin.Components.Content do
  use BrandoAdmin, :component

  def header(assigns) do
    assigns =
      assigns
      |> assign_new(:inner_block, fn -> nil end)
      |> assign_new(:subtitle, fn -> nil end)

    ~H"""
    <header id="content-header" data-moonwalk-run="brandoHeader">
      <div class="content">
        <section class="main">
          <h1>
            <%= @title %>
          </h1>
          <%= if @subtitle do %>
            <h3>
              <%= @subtitle %>
            </h3>
          <% end %>
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
