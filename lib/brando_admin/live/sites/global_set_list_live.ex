defmodule BrandoAdmin.Sites.GlobalSetListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet, page_title: &__MODULE__.page_title/0
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.{Content, Workspace}

  def render(assigns) do
    ~H"""
    <div class="admin-workspace content-workspace workspace-list global-sets-workspace">
      <Workspace.header
        icon={@page_icon}
        title={gettext("Global fields (setup)")}
        subtitle={gettext("Which global fields exist and where. Their values are edited under Globals.")}
      >
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

  # The setup screen, apart from the values screen that "Globals" names.
  @doc false
  def page_title, do: gettext("Global fields (setup)")
end
