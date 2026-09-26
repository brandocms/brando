defmodule E2eProjectAdmin.SyncTest.ArticleFormLive do
  use BrandoAdmin.LiveView.Form, schema: E2eProject.SyncTest.Article
  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    >
      <:header>{if @live_action == :create, do: "Create article", else: "Update article"}</:header>
    </.live_component>
    """
  end
end
