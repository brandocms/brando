defmodule BrandoAdmin.Components.Content do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Phoenix.LiveView.JS
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
  attr :subtitle, :string, default: nil
  attr :icon, :string, default: "hero-adjustments-horizontal"
  attr :layout, :string, default: nil
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
      |> assign(:close, assigns.close || hide_modal("##{assigns.id}"))
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
        @show && "visible",
        @layout && "modal--#{@layout}"
      ]}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-hook="Brando.Modal"
      data-modal-close={@close}
      {@rest}
    >
      <div class="modal-backdrop" phx-click={@close} />
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <header class={[
            "modal-header",
            @center_header && "centered"
          ]}>
            <div class="modal-heading">
              <span :if={@icon} class="modal-heading-icon" aria-hidden="true"><.icon name={@icon} /></span>
              <div class="heading-copy">
                <h2 id={"#{@id}-title"}>{@title}</h2>
                <p :if={@subtitle} class="modal-subtitle">{@subtitle}</p>
              </div>
            </div>
            <div class="header-wrap">
              <%= if @header != [] do %>
                {render_slot(@header)}
              <% end %>
              <button type="button" class="modal-close" aria-label={gettext("Close dialog")} phx-click={@close}>
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

  attr :id, :string, required: true
  attr :enabled, :boolean, default: true

  slot :section, required: true do
    attr :id, :string, required: true
    attr :label, :string, required: true
    attr :icon, :string
  end

  # Panels stay mounted so switching sections cannot drop pending form params.
  def modal_sections(assigns) do
    ~H"""
    <div id={@id} class={["modal-sections", !@enabled && "modal-sections--stacked"]}>
      <nav :if={@enabled} class="modal-section-nav" role="tablist" aria-label={gettext("Sections")}>
        <button
          :for={{section, index} <- Enum.with_index(@section)}
          type="button"
          id={"#{@id}-tab-#{section.id}"}
          role="tab"
          data-modal-tab
          aria-selected={to_string(index == 0)}
          aria-controls={"#{@id}-panel-#{section.id}"}
          tabindex={if index == 0, do: "0", else: "-1"}
          phx-click={modal_section(@id, section.id)}
        >
          <.icon :if={section[:icon]} name={section.icon} />
          <span>{section.label}</span>
        </button>
      </nav>
      <div class="modal-section-content">
        <section
          :for={{section, index} <- Enum.with_index(@section)}
          id={"#{@id}-panel-#{section.id}"}
          class="modal-section-panel"
          role={@enabled && "tabpanel"}
          aria-labelledby={@enabled && "#{@id}-tab-#{section.id}"}
          hidden={@enabled && index != 0}
        >
          {render_slot(section)}
        </section>
      </div>
    </div>
    """
  end

  defp modal_section(id, section) do
    JS.set_attribute({"hidden", ""}, to: "##{id} > .modal-section-content > .modal-section-panel")
    |> JS.remove_attribute("hidden", to: "##{id}-panel-#{section}")
    |> JS.set_attribute({"aria-selected", "false"}, to: "##{id} > nav > button")
    |> JS.set_attribute({"tabindex", "-1"}, to: "##{id} > nav > button")
    |> JS.set_attribute({"aria-selected", "true"}, to: "##{id}-tab-#{section}")
    |> JS.set_attribute({"tabindex", "0"}, to: "##{id}-tab-#{section}")
  end

  attr :user, :any, required: true
  attr :caption, :string, default: nil

  def modal_person(assigns) do
    avatar =
      case Map.get(assigns.user, :avatar) do
        %{status: :processed} = image -> image
        _ -> nil
      end

    assigns = assign(assigns, :avatar, avatar)

    ~H"""
    <span class="modal-person">
      <span class="modal-person-avatar">
        <img :if={@avatar} src={Brando.Utils.img_url(@avatar, :thumb, prefix: Brando.Utils.media_url())} alt="" />
        <span :if={!@avatar}>{String.first(@user.name || "?")}</span>
      </span>
      <span class="person-copy">
        <strong>{@user.name}</strong>
        <small :if={@caption}>{@caption}</small>
      </span>
    </span>
    """
  end
end
