defmodule BrandoAdmin.Forms.FormListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Forms.Form
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace

  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list content-workspace forms-workspace">
      <Workspace.header title={gettext("Forms")} subtitle={gettext("Forms visitors fill in on the site")}>
        <.link
          :if={BrandoAdmin.Authorization.allowed?(:update, Brando.Forms.Messages)}
          navigate="/admin/forms/messages"
          class="workspace-button"
        >
          {gettext("Messages")}
        </.link>
        <.link
          :if={BrandoAdmin.Authorization.allowed?(:create, @schema)}
          navigate="/admin/forms/create"
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
        hidden_filters={[]}
        empty_title={gettext("No forms in this view")}
        empty_description={gettext("Adjust your search or create a new form.")}
      />
    </div>
    """
  end
end
