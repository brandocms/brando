defmodule BrandoAdmin.Galleries.GalleryFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Galleries.Gallery
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <div class="admin-workspace settings-workspace gallery-workspace">
      <.live_component
        module={Form}
        id="gallery_form"
        entry_id={@entry_id}
        current_user={@current_user}
        schema={@schema}
      >
        <:header>
          <%= if @entry_id do %>
            {gettext("Gallery #%{id}", id: @entry_id)}
          <% else %>
            {gettext("New gallery")}
          <% end %>
        </:header>
      </.live_component>

      <section :if={@gallery_usage != []} class="gallery-usage" aria-labelledby="gallery-usage-title">
        <h2 id="gallery-usage-title">{gettext("Used in")}</h2>
        <ul>
          <li :for={identifier <- @gallery_usage} :key={"#{identifier.schema}-#{identifier.entry_id}"}>
            <.link navigate={edit_url(identifier)}>
              <span class="gallery-usage-cover">
                <img :if={identifier.cover} src={identifier.cover} alt="" loading="lazy" />
              </span>
              <span class="gallery-usage-title">{identifier.title}</span>
              <span class="gallery-usage-type">{Brando.Blueprint.get_singular(identifier.schema)}</span>
              <span class={["gallery-usage-status", "status-#{identifier.status}"]} title={to_string(identifier.status)}></span>
              <.icon name="hero-arrow-right" />
            </.link>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  def handle_params(%{"entry_id" => entry_id}, _url, socket) do
    gallery_usage = load_gallery_usage(entry_id)
    {:noreply, assign(socket, :gallery_usage, gallery_usage)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :gallery_usage, [])}
  end

  # The entries using the gallery, as one list sorted by title.
  defp load_gallery_usage(gallery_id) do
    gallery_id
    |> Brando.Galleries.list_gallery_usage()
    |> Enum.flat_map(fn {schema, entry_ids} ->
      from(i in Brando.Content.Identifier, where: i.schema == ^schema and i.entry_id in ^entry_ids)
      |> Brando.Repo.all()
    end)
    |> Enum.sort_by(&String.downcase(&1.title || ""))
  end

  defp edit_url(identifier) do
    identifier.schema.__admin_route__(:update, [identifier.entry_id])
  rescue
    _ -> "#"
  end
end
