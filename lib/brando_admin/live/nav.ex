defmodule BrandoAdmin.Nav do
  @moduledoc false
  use BrandoAdmin, :child_live_view
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  on_mount {BrandoAdmin.UserAuth, :mount_current_user}

  def mount(_, %{"user_token" => _token, "current_url" => url}, socket) do
    if connected?(socket) do
      socket
      |> assign(:socket_connected, true)
      |> subscribe()
      |> assign(:current_url, url)
      |> put_locale()
      |> assign(:menu_sections, BrandoAdmin.Menu.get_menu())
      |> then(&{:ok, &1})
    else
      socket
      |> assign(:socket_connected, false)
      |> assign(:current_user, nil)
      |> assign(:current_url, url)
      |> assign(:menu_sections, [])
      |> then(&{:ok, &1})
    end
  end

  def put_locale(socket) do
    current_user = socket.assigns.current_user

    if current_user do
      current_user.language
      |> to_string()
      |> Gettext.put_locale()
    end

    socket
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def subscribe(%{assigns: %{current_user: user}} = socket) when not is_nil(user) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "user:#{user.id}")
    socket
  end

  def subscribe(socket) do
    socket
  end

  def render(assigns) do
    ~H"""
    <div class="sidebar-wrapper">
      <button
        type="button"
        phx-click={JS.toggle_class("hidden", to: "#sidebar") |> JS.toggle_class("minimized")}
        class="fullscreen-toggle"
      >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 12 12" width="12" height="12">
          <path d="M291.36 414.51h12v12h-12Z" transform="translate(-291.36 -414.51)" style="fill:none" /><path d="M1.5 9h9v1h-9z" /><path
            id="chevron"
            d="m3.3 1.95.7.71-1.59 1.59L4 5.84l-.7.71L1 4.25l2.3-2.3z"
          /><path d="M6 5.5h4.5v1H6zM6 2h4.5v1H6z" />
        </svg>
      </button>
      <div
        class="sidebar"
        id="sidebar"
        data-js-hide={JS.add_class("hidden", to: "#sidebar")}
        data-js-show={JS.remove_class("hidden", to: "#sidebar")}
      >
        <section id="navigation">
          <div id="navigation-content">
            <header class="navigation-header">
              <div class="logo">
                <%= if Brando.config(:client_brand) do %>
                  {Phoenix.HTML.raw(Brando.config(:client_brand))}
                <% else %>
                  <svg
                    version="1.1"
                    xmlns="http://www.w3.org/2000/svg"
                    x="0"
                    y="0"
                    viewBox="0 0 560 559.4"
                    xml:space="preserve"
                  >
                    <path
                      d="M280 559.4C125.1 559.5-.9 433.5 0 277.7.9 123.9 126.3-1.6 282-.6c153.7 1 279.2 126.4 278 282.3-1.2 153.3-125.8 277.7-280 277.7zm74.6-289.8c1.2-.2 1.6-.3 2.1-.4l1.5-.3c13.6-2.8 25.7-8.7 35.7-18.4 14.3-13.9 20-31.1 18.5-50.8-1.7-22.7-13.2-38.3-34.3-47-12.6-5.2-25.8-7.3-39.3-7.3-40.8-.2-81.6-.1-122.5-.2-2.8 0-3.7.8-4.4 3.5-19.7 79.4-39.5 158.7-59.3 238.1-1.1 4.5-2.2 9-3.3 13.6h2.3c43.8 0 87.6.1 131.5 0 19.3-.1 38.1-2.8 56.3-9.5 14.8-5.5 28.2-13.2 38.6-25.4 13.2-15.4 18-33.5 15.8-53.5-1.5-13.3-7.4-24.4-18.1-32.7-6.1-4.6-13-7.6-21.1-9.7z"
                      fill="#002992"
                    /><path
                      d="M354.6 269.6c8.1 2.1 15 5 21.1 9.8 10.7 8.3 16.7 19.4 18.1 32.7 2.2 19.9-2.6 38-15.8 53.5-10.4 12.2-23.8 19.9-38.6 25.4-18.2 6.7-37.1 9.4-56.3 9.5-43.8.1-87.6 0-131.5 0h-2.3c1.1-4.7 2.2-9.1 3.3-13.6 19.8-79.4 39.6-158.7 59.3-238.1.7-2.7 1.6-3.5 4.4-3.5 40.8.1 81.6 0 122.5.2 13.5.1 26.7 2.2 39.3 7.3 21.1 8.6 32.6 24.3 34.3 47 1.5 19.6-4.2 36.9-18.5 50.8-10 9.7-22.1 15.6-35.7 18.4l-1.5.3c-.5 0-.9.1-2.1.3zm-125.1 75.7c.6 0 .9.1 1.3.1 17.6 0 35.1.1 52.7 0 7.5 0 14.9-.9 22.1-3.4 13.1-4.6 19.9-14.5 19-27.7-.4-5.7-3.1-9.9-8.2-12.6-5.4-2.9-11.2-3.7-17.1-3.7-18.6-.1-37.1 0-55.7 0-.6 0-1.3.1-1.9.1-4.1 15.8-8.1 31.4-12.2 47.2zM266 200c-3.9 15.4-7.8 30.8-11.7 46.4 1 0 1.7.1 2.4.1 15.2 0 30.5 0 45.7-.1 8.5-.1 16.8-1 24.7-4.4 6.2-2.6 10.9-6.7 13.2-13.2 3.3-9.1 1.3-18.3-5.2-23.5-4.6-3.7-10.1-5.2-15.8-5.3-17.7-.1-35.3 0-53.3 0z"
                      fill="#f9eee9"
                    /><path
                      d="M229.5 345.3c4.1-15.8 8.1-31.4 12.1-47.2.7-.1 1.3-.1 1.9-.1 18.6 0 37.1-.1 55.7 0 5.9 0 11.8.8 17.1 3.7 5 2.7 7.7 6.9 8.2 12.6 1 13.2-5.8 23.1-19 27.7-7.2 2.5-14.6 3.4-22.1 3.4-17.6.1-35.1 0-52.7 0-.2 0-.5-.1-1.2-.1z"
                      fill="#012a92"
                    /><path
                      d="M266 200c18 0 35.7-.1 53.3.1 5.7.1 11.2 1.5 15.8 5.3 6.4 5.2 8.4 14.4 5.2 23.5-2.3 6.5-7 10.6-13.2 13.2-7.9 3.4-16.2 4.3-24.7 4.4-15.2.1-30.5.1-45.7.1-.7 0-1.5-.1-2.4-.1 3.9-15.7 7.8-31.1 11.7-46.5z"
                      fill="#012992"
                    />
                  </svg>
                <% end %>
              </div>
            </header>
            <div :if={@current_user} id="current-user" class="current-user" tabindex="0" data-testid="current-user">
              <section class="button">
                <section class="avatar-wrapper">
                  <div class="avatar">
                    <Content.image image={@current_user.avatar} size={:thumb} />
                  </div>
                </section>
                <section class="content">
                  <div class="info">
                    <div class="name">
                      {@current_user.name}
                    </div>
                    <div class="role">
                      {@current_user.role}
                    </div>
                  </div>
                  <div class="dropdown-icon">
                    <svg width="13" height="10" viewBox="0 0 13 10" fill="none" xmlns="http://www.w3.org/2000/svg">
                      <path d="M6.5 10L0.00480841 0.624999L12.9952 0.624998L6.5 10Z" fill="black" />
                    </svg>
                  </div>
                </section>
              </section>
              <section class="dropdown-content">
                <ul>
                  <li>
                    <.link href="/admin/logout" data-testid="logout" tabindex="0">
                      {gettext("Log out")}
                    </.link>
                  </li>
                </ul>
              </section>
            </div>

            <nav :if={@socket_connected} phx-hook="Brando.Navigation" id="nav">
              <div id="nav-circle" class="nav-circle"></div>
              <div class="nav-sections" id="nav-sections">
                <section :for={section <- @menu_sections} class="navigation-section">
                  <header>
                    <h3>{section.name}</h3>
                    <div class="line"></div>
                  </header>
                  <dl :for={item <- section.items}>
                    <dt>
                      <.link :if={item.url} navigate={item.url} class={Brando.HTML.active(@current_url, item.url)}>
                        {item.name}
                      </.link>
                      <span :if={item[:items]} data-nav-expand>
                        {item.name} <.icon name="hero-plus-circle" />
                      </span>
                    </dt>
                    <dd :if={item[:items]}>
                      <ul>
                        <li :for={sub_item <- item.items}>
                          <.link navigate={sub_item.url}>
                            {sub_item.name}
                          </.link>
                        </li>
                      </ul>
                    </dd>
                  </dl>
                </section>
              </div>
            </nav>
          </div>
        </section>
      </div>
    </div>
    """
  end

  def handle_info({:user_update, user}, socket) do
    {:noreply, assign(socket, :current_user, user)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle", _, %{assigns: %{fields: child_fields, singular: singular, entry: %{id: id}}} = socket) do
    id = "list-row-#{singular}-#{id}"

    send_update(BrandoAdmin.Components.Content.List.Row,
      id: id,
      show_children: !socket.assigns.active,
      child_fields: child_fields
    )

    {:noreply, assign(socket, :active, !socket.assigns.active)}
  end

  def handle_event("toggle_nav", %{"minimized" => status}, socket) do
    {:noreply, assign(socket, :minimized, status)}
  end
end
