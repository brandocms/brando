defmodule BrandoAdmin.Components.ImagePicker do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Content
  import Brando.Gettext

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:z_index, fn -> 1100 end)}
  end

  def update(
        %{
          config_target: config_target,
          event_target: event_target,
          multi: multi,
          selected_images: selected_images
        },
        socket
      ) do
    {:ok,
     socket
     |> assign(:config_target, config_target)
     |> assign(:event_target, event_target)
     |> assign(:multi, multi)
     |> assign(:selected_images, selected_images)
     |> assign_images()}
  end

  def update(%{selected_images: selected_images}, socket) do
    {:ok, assign(socket, :selected_images, selected_images)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:multi, fn -> false end)
     |> assign_new(:images, fn -> [] end)
     |> assign_new(:config_target, fn -> nil end)
     |> assign_new(:event_target, fn -> nil end)
     |> assign_new(:deselect_image, fn -> nil end)
     |> assign_new(:selected_images, fn -> [] end)}
  end

  def assign_images(socket) do
    {:ok, images} =
      Brando.Images.list_images(%{
        select: [:id, :width, :height, :formats, :status, :path, :sizes, :cdn],
        filter: %{config_target: socket.assigns.config_target},
        order: "desc id"
      })

    assign(socket, :images, images)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext "Select image"} close={toggle_drawer("##{@id}")} z={@z_index} dark>
        <:info>
          <%= if @config_target do %>
            <div class="mb-2">
              <%= gettext "Select similarly typed image from library" %>
            </div>
          <% end %>
          <div class="button-group-horizontal mb-1">
            <button class="secondary" type="button" phx-click={show_grid(@id)}>
              Grid
            </button>
            <button class="secondary" type="button" phx-click={show_list(@id)}>
              List
            </button>
          </div>
        </:info>

        <div class="image-picker grid" id={"image-picker-drawer-#{@id}"}>
          <%= for image <- @images do %>
          <div
            class={render_classes(["image-picker__image": true, selected: image.path in @selected_images])}
            phx-click={if @multi, do: JS.push("select_image", target: @event_target), else: JS.push("select_image", target: @event_target) |> toggle_drawer("#image-picker")}
            phx-value-id={image.id}
            phx-value-selected={image.path in @selected_images && "true" || "false"}
            phx-page-loading>
            <Content.image image={image} size={:smallest} />
            <div class="image-picker__info">
              <div class="image-picker__filename"><%= image.path %></div>
              <div class="image-picker__dims">
                Dimensions....: <%= image.width %>&times;<%= image.height %>
              </div>
              <div class="image-picker__formats">
                Formats.......: <%= inspect image.formats %>
              </div>
              <div class="image-picker__processed">
                Status........: <%= inspect image.status %>
              </div>
            </div>
          </div>
          <% end %>
        </div>
      </Content.drawer>
    </div>
    """
  end

  def show_grid(js \\ %JS{}, id) do
    js
    |> JS.add_class("grid", to: "#image-picker-drawer-#{id}")
    |> JS.remove_class("list", to: "#image-picker-drawer-#{id}")
  end

  def show_list(js \\ %JS{}, id) do
    js
    |> JS.add_class("list", to: "#image-picker-drawer-#{id}")
    |> JS.remove_class("grid", to: "#image-picker-drawer-#{id}")
  end
end
