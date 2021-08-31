defmodule BrandoAdmin.Villain.ModuleListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Villain.Module

  alias BrandoAdmin.Components.Content
  alias Brando.Villain

  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Content Modules")}
      subtitle={gettext("Overview")}>
      <button class="primary" :on-click="create_module">
        Create new module
      </button>
    </Content.Header>

    <Content.List
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end

  def handle_event("create_module", _, %{assigns: %{current_user: user}} = socket) do
    # TODO: allow getting `code` from config here!
    # it's nice to be able to specify your own starting point
    params = %{
      name: "New module",
      class: "module new",
      namespace: "general",
      help_text: "Help text",
      code:
        "<article b-tpl=\"module\">\n  <div class=\"inner\">\n" <>
          "    <!-- \n    (!) reference refs by using %{ref_name} \n" <>
          "    (!) reference vars by using {{ var_name }}\n    -->\n" <>
          "  </div>\n</article>"
    }

    {:ok, new_module} = Villain.create_module(params, user)

    {:noreply,
     push_redirect(socket,
       to: Brando.routes().live_path(socket, BrandoAdmin.ConfigModulesUpdateLive, new_module.id)
     )}
  end
end
