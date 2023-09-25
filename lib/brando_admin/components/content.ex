defmodule BrandoAdmin.Components.Content do
  use BrandoAdmin, :component
  import Brando.Gettext

  def header(assigns) do
    assigns =
      assigns
      |> assign_new(:inner_block, fn -> nil end)
      |> assign_new(:subtitle, fn -> nil end)

    ~H"""
    <header id="content-header">
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
          prefix: Brando.Utils.media_url(),
          cache: Map.get(assigns.image, :updated_at)
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

  def modal(assigns) do
    assigns =
      assigns
      |> assign_new(:header, fn -> nil end)
      |> assign_new(:footer, fn -> nil end)
      |> assign_new(:show, fn -> false end)
      |> assign_new(:center_header, fn -> false end)
      |> assign_new(:narrow, fn -> false end)
      |> assign_new(:medium, fn -> false end)
      |> assign_new(:wide, fn -> false end)
      |> assign_new(:remember_scroll_position, fn -> false end)
      |> assign_new(:close, fn -> nil end)
      |> assign_new(:ok, fn -> nil end)

    ~H"""
    <div
      id={@id}
      class={render_classes([modal: true, narrow: @narrow, medium: @medium, wide: @wide])}
      phx-window-keydown={hide_modal("##{@id}")}
      phx-key="escape">
      <div class="modal-backdrop" phx-click={hide_modal("##{@id}")} />
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <header class={render_classes(["modal-header": true, centered: @center_header])}>
            <h2><%= @title %></h2>
            <div class="header-wrap">
              <%= if @header do %>
                <%= render_slot @header %>
              <% end %>
              <button
                type="button"
                class="modal-close"
                phx-click={@close || hide_modal("##{@id}")}>
                <.icon name="hero-x-mark" />
              </button>
            </div>
          </header>
          <section
            id={"#{@id}-body"}
            class="modal-body"
            phx-hook={@remember_scroll_position && "Brando.RememberScrollPosition"}>
            <%= render_slot @inner_block %>
          </section>
          <%= if @footer do %>
            <footer class="modal-footer">
              <%= render_slot @footer %>
              <%= if @ok do %>
                <button class="primary" type="button" phx-click={@ok} phx-value-id={@id}>Ok</button>
              <% end %>
            </footer>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
