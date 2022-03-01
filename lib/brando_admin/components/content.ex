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

  def image(assigns) do
    path =
      if assigns.image do
        type = Brando.Images.Utils.image_type(assigns.image.path)

        Brando.Utils.img_url(
          assigns.image,
          (type == :svg && :original) || assigns.size,
          prefix: Brando.Utils.media_url()
        )
      end

    assigns = assign(assigns, :path, path)

    ~H"""
    <%= if @image do %>
      <img width={@image.width} height={@image.height} src={@path}>
    <% else %>
      <div class="img-placeholder">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>
      </div>
    <% end %>
    """
  end
end
