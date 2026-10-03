defmodule BrandoAdmin.Forms.FormFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Forms.Form
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Usage

  def render(assigns) do
    ~H"""
    <div class="admin-workspace settings-workspace form-builder-workspace">
      <.live_component
        module={BrandoAdmin.Components.Form}
        id="form_form"
        entry_id={@entry_id}
        current_user={@current_user}
        schema={@schema}
        initial_params={%{language: @current_user.config.content_language, status: :draft}}
      >
        <:header>
          <%= if @live_action == :create do %>
            {gettext("Create form")}
          <% else %>
            {gettext("Edit form")}
          <% end %>
        </:header>
      </.live_component>

      <Usage.list :if={@entry_id} id="form-usage" usages={@usage} />
    </div>
    """
  end

  # The entries whose blocks hold the form, in any of its languages.
  def handle_params(%{"entry_id" => entry_id}, _url, socket) do
    usage =
      case Brando.Repo.get(Brando.Forms.Form, String.to_integer(entry_id)) do
        %{key: key} -> Brando.Forms.list_usage(key)
        nil -> []
      end

    {:noreply, assign(socket, :usage, usage)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, assign(socket, :usage, [])}
end
