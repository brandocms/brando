defmodule BrandoAdmin.Components.Content do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Image

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
            {@title}
          </h1>
          <h3 :if={@subtitle}>
            {@subtitle}
          </h3>
        </section>
        <section class="actions">
          <%= if @inner_block do %>
            {render_slot(@inner_block)}
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
      |> assign_new(:wide, fn -> false end)
      |> assign_new(:info, fn -> nil end)
      |> assign_new(:dark, fn -> false end)
      |> assign_new(:light, fn -> false end)
      |> assign_new(:left, fn -> false end)
      |> assign_new(:hidden, fn -> true end)

    ~H"""
    <div
      id={@id}
      class={[
        "drawer",
        @hidden && "hidden",
        @narrow && "narrow",
        @wide && "wide",
        @dark && "dark",
        @light && "light",
        @left && "left"
      ]}
      style={"z-index: #{@z}"}
    >
      <div class="inner">
        <div class="drawer-header">
          <h2>
            {@title}
          </h2>
          <button phx-click={@close} type="button" class="drawer-close-button">
            {gettext("Close")}
          </button>
        </div>
        <div :if={@info} class="drawer-info">
          {render_slot(@info)}
        </div>
        <div class="drawer-form">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  attr :image, :any
  attr :size, :atom
  slot :inner_block

  @doc "Renders an image or its processing/empty placeholder."
  def image(assigns), do: Image.image(assigns)

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :show, :boolean, default: false
  attr :center_header, :boolean, default: false
  attr :narrow, :boolean, default: false
  attr :medium, :boolean, default: false
  attr :wide, :boolean, default: false
  attr :auto, :boolean, default: false
  attr :remember_scroll_position, :boolean, default: false
  attr :close, :any, default: nil
  attr :ok, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true
  slot :header
  slot :footer

  def modal(assigns) do
    assigns =
      assigns
      |> assign_new(:show, fn -> false end)
      |> assign_new(:center_header, fn -> false end)
      |> assign_new(:narrow, fn -> false end)
      |> assign_new(:medium, fn -> false end)
      |> assign_new(:wide, fn -> false end)
      |> assign_new(:auto, fn -> false end)
      |> assign_new(:remember_scroll_position, fn -> false end)
      |> assign_new(:close, fn -> hide_modal("##{assigns.id}") end)
      |> assign_new(:ok, fn -> nil end)

    ~H"""
    <div
      id={@id}
      class={[
        "modal",
        @narrow && "narrow",
        @medium && "medium",
        @wide && "wide",
        @auto && "auto",
        @show && "visible"
      ]}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-hook="Brando.Modal"
      phx-window-keydown={@close}
      phx-key="escape"
      {@rest}
    >
      <div class="modal-backdrop" phx-click={@close} />
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <header class={[
            "modal-header",
            @center_header && "centered"
          ]}>
            <h2 id={"#{@id}-title"}>{@title}</h2>
            <div class="header-wrap">
              <%= if @header != [] do %>
                {render_slot(@header)}
              <% end %>
              <button type="button" class="modal-close" phx-click={@close || hide_modal("##{@id}")}>
                <.icon name="hero-x-mark" />
              </button>
            </div>
          </header>
          <section
            id={"#{@id}-body"}
            class="modal-body"
            phx-hook={@remember_scroll_position && "Brando.RememberScrollPosition"}
          >
            {render_slot(@inner_block)}
          </section>
          <%= if @footer != [] do %>
            <footer class="modal-footer">
              {render_slot(@footer)}
              <button :if={@ok} class="primary" type="button" phx-click={@ok} phx-value-id={@id}>Ok</button>
            </footer>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
