defmodule BrandoAdmin.Galleries.GalleryFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Galleries.Gallery
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Usage

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

      <Usage.list :if={@entry_id} usages={@usage} />
    </div>
    """
  end

  def handle_params(%{"entry_id" => entry_id}, _url, socket) do
    id = String.to_integer(entry_id)
    {:noreply, assign(socket, :usage, Map.get(Brando.Content.Usage.list(:gallery, [id]), id, []))}
  end

  def handle_params(_params, _url, socket), do: {:noreply, assign(socket, :usage, [])}
end
