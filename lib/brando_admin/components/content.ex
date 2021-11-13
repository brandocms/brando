defmodule BrandoAdmin.Components.Content do
  use BrandoAdmin, :component
  import Brando.Gettext

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

  def drawer(assigns) do
    assigns =
      assigns
      |> assign_new(:z, fn -> 999 end)
      |> assign_new(:narrow, fn -> false end)
      |> assign_new(:info, fn -> nil end)
      |> assign_new(:dark, fn -> false end)

    ~H"""
    <div id={@id} class={render_classes(["drawer", "hidden", narrow: @narrow, dark: @dark])} style={"z-index: #{@z}"}>
      <div class="inner">
        <div class="drawer-header">
          <h2>
            <%= @title %>
          </h2>
          <button
            phx-click={@close}
            type="button"
            class="drawer-close-button">
            <%= gettext "Close" %>
          </button>
        </div>
        <%= if @info do %>
          <div class="drawer-info">
            <%= render_slot(@info) %>
          </div>
        <% end %>
        <div class="drawer-form">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end
end
