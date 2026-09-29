defmodule BrandoAdmin.Content.ModuleSetListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.ModuleSet, page_title: &__MODULE__.page_title/0
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Block module sets")} subtitle={gettext("Overview")}>
      <.link :if={BrandoAdmin.Authorization.allowed?(:create, @schema)} navigate={@admin_create_url} class="primary">
        {gettext("Create new")}
      </.link>
    </Content.header>

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

  @doc false
  def page_title, do: gettext("Block module sets")
end
