defmodule BrandoAdmin.Content.ModuleListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Module
  import Brando.Gettext
  alias BrandoAdmin.Components.Content
  alias Phoenix.LiveView.JS

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Content Modules")}
      subtitle={gettext("Overview")}>
      <button class="primary" phx-click={JS.push("create_module")}>
        <%= gettext "Create new" %>
      </button>
    </Content.header>

    <.live_component module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end

  def handle_event("create_module", _, %{assigns: %{current_user: user}} = socket) do
    params = %{
      name: "New module",
      class: "module new",
      namespace: "general",
      help_text: "Help text",
      code:
        "<article b-tpl=\"module\">\n  <div class=\"inner\">\n" <>
          "    <!-- \n    (!) reference refs by using {% ref refs.ref_name %} \n" <>
          "    (!) reference vars by using {{ var_name }}\n    -->\n" <>
          "  </div>\n</article>"
    }

    {:ok, new_module} = Brando.Content.create_module(params, user)

    {:noreply,
     push_redirect(socket,
       to:
         Brando.routes().admin_live_path(
           socket,
           BrandoAdmin.Content.ModuleUpdateLive,
           new_module.id
         )
     )}
  end
end
