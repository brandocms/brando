defmodule E2eProjectWeb.ClientHTML do
  use BrandoWeb, :html
  # use Gettext, backend: E2eProjectWeb.Gettext
  use Phoenix.Component
  embed_templates "client_html/*"

  def list_clients(assigns) do
    ~H"""
    <div class="clients">
      <div class="inner">
        <%= for client <- @clients do %>
        <a href={absolute_url(client)} class="client">
          <.picture src={client.cover} opts={[
            prefix: media_url(),
            lazyload: true,
            srcset: {E2eProject.Projects.Client, :cover},
            placeholder: :dominant_color,
            moonwalk: true
          ]} />
          <div class="info">
            <section class="meta">
              <div class="time">
                <%= @entry.updated_at %>
              </div>
            </section>
            <h2>
              <%= @entry.title %>
            </h2>
            <section class="more">
              <p>Read more &rarr;</p>
            </section>
          </div>
        </a>
        <% end %>
      </div>
    </div>
    """
  end
end
