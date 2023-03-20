defmodule BrandoAdmin.Sites.GlobalSetUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.GlobalSet
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="global_set_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Edit global set") %>
      </:header>
    </.live_component>
    """
  end

  def handle_event(
        "add_select_var_option",
        %{"var_key" => var_key},
        socket
      ) do
    send_update(BrandoAdmin.Components.Form,
      id: "global_set_form",
      action: :add_select_var_option,
      var_key: var_key
    )

    {:noreply, socket}
  end
end
