defmodule E2eProjectWeb.ProjectHTML do
  use BrandoWeb, :html
  # use Gettext, backend: E2eProjectWeb.Gettext
  use Phoenix.Component
  embed_templates "project_html/*"

  def list_projects(assigns) do
    ~H"""
    <div class="projects">
      <div class="inner">
        <%= for project <- @projects do %>
        <a href={absolute_url(project)} class="project">
          <.picture src={project.cover} opts={[
            prefix: media_url(),
            lazyload: true,
            srcset: {E2eProject.Projects.Project, :cover},
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
