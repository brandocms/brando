defmodule E2eProjectWeb.CategoryHTML do
  use BrandoWeb, :html
  # use Gettext, backend: E2eProjectWeb.Gettext
  use Phoenix.Component
  embed_templates "category_html/*"

  def list_categories(assigns) do
    ~H"""
    <div class="categories">
      <div class="inner">
        <%= for category <- @categories do %>
        <a href={absolute_url(category)} class="category">
          <.picture src={category.cover} opts={[
            prefix: media_url(),
            lazyload: true,
            srcset: {E2eProject.Projects.Category, :cover},
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
