defmodule E2eProjectAdmin.SyncTest.ArticleListLive do
  use BrandoAdmin.LiveView.Listing, schema: E2eProject.SyncTest.Article
  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title="Articles" subtitle="Synchronized translations" />

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end
