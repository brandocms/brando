defmodule BrandoAdmin.Videos.VideoFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Videos.Video
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Usage

  def render(assigns) do
    ~H"""
    <.live_component module={Form} id="video_form" entry_id={@entry_id} current_user={@current_user} schema={@schema}>
      <:header>
        <%= if @live_action == :create do %>
          {gettext("Create video")}
        <% else %>
          {gettext("Edit video")}
        <% end %>
      </:header>
    </.live_component>

    <Usage.list :if={@entry_id} usages={@usage} />
    """
  end

  def handle_params(%{"entry_id" => entry_id}, _url, socket) do
    id = String.to_integer(entry_id)
    {:noreply, assign(socket, :usage, Map.get(Brando.Content.Usage.list(:video, [id]), id, []))}
  end

  def handle_params(_params, _url, socket), do: {:noreply, assign(socket, :usage, [])}
end
