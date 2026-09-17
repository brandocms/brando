defmodule BrandoAdmin.Sites.GlobalSetListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.{Content, Workspace}

  def render(assigns) do
    ~H"""
    <div class="admin-workspace content-workspace workspace-list global-sets-workspace">
      <Workspace.header title={gettext("Global sets")} subtitle={gettext("Shared values available across your site.")}>
        <.link
          :if={BrandoAdmin.Authorization.allowed?(:create, @schema)}
          navigate="/admin/config/global_sets/create"
          class="workspace-button primary"
        >
          {gettext("Create new")}
        </.link>
      </Workspace.header>

      <.live_component
        module={Content.List}
        id={"content_listing_#{@schema}_default"}
        schema={@schema}
        current_user={@current_user}
        uri={@uri}
        params={@params}
        listing={:default}
      />
    </div>
    """
  end
end
