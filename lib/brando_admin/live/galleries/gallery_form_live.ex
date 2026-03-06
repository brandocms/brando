defmodule BrandoAdmin.Galleries.GalleryFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Galleries.Gallery
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Entries
  alias Phoenix.LiveView.JS

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="gallery_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    >
      <:header>
        {gettext("Edit gallery")}
      </:header>
    </.live_component>

    <div :if={@gallery_usage != %{}} class="shaded" style="margin-top: 15px;">
      <h2 class="subheader">{gettext("Where used")}</h2>
      <div :for={{schema, identifiers} <- @gallery_usage} :key={schema} class="usage-group">
        <h3 class="usage-schema-label">{Brando.Blueprint.get_plural(schema)}</h3>
        <div class="selected-entries">
          <Entries.dumb_identifier
            :for={identifier <- identifiers}
            :key={identifier.id}
            identifier={identifier}
            select={JS.navigate(edit_url(identifier))}
          />
        </div>
      </div>
    </div>
    """
  end

  def handle_params(%{"entry_id" => entry_id}, _url, socket) do
    gallery_usage = load_gallery_usage(entry_id)
    {:noreply, assign(socket, :gallery_usage, gallery_usage)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :gallery_usage, %{})}
  end

  defp load_gallery_usage(gallery_id) do
    usage_map = Brando.Galleries.list_gallery_usage(gallery_id)

    Enum.reduce(usage_map, %{}, fn {schema, entry_ids}, acc ->
      identifiers =
        from(i in Brando.Content.Identifier,
          where: i.schema == ^schema and i.entry_id in ^entry_ids
        )
        |> Brando.Repo.all()

      if identifiers == [] do
        acc
      else
        Map.put(acc, schema, identifiers)
      end
    end)
  end

  defp edit_url(identifier) do
    try do
      identifier.schema.__admin_route__(:update, [identifier.entry_id])
    rescue
      _ -> "#"
    end
  end
end
