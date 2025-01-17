defmodule BrandoAdmin.Sites.GlobalSetFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.GlobalSet
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="global_set_form"
      entry_id={@entry_id}
      current_user={@current_user}
      initial_params={%{language: @current_user.config.content_language}}
      schema={@schema}
    >
      <:header>
        {gettext("Edit global set")}
      </:header>
    </.live_component>
    """
  end

  def handle_event("add_select_var_option", %{"var_key" => var_key}, socket) do
    send_update(BrandoAdmin.Components.Form,
      id: "global_set_form",
      action: :add_select_var_option,
      var_key: var_key
    )

    {:noreply, socket}
  end
end
