defmodule BrandoAdmin.Globals.GlobalsLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet, page_title: &__MODULE__.page_title/0
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Components.GlobalTabs

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :active_tab, nil)}
  end

  # The values screen is "Globals" in the menu and its heading, not the
  # schema's plural ("Global sets"), which names the setup screen.
  @doc false
  def page_title, do: gettext("Globals")

  def handle_event("focus", _, socket), do: {:noreply, socket}
  def handle_event("blur", _, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="admin-workspace settings-workspace globals-workspace">
      <Workspace.header title={gettext("Globals")} />

      <.live_component module={GlobalTabs} id="global_tabs" active_tab={@active_tab} current_user={@current_user}>
      </.live_component>
    </div>
    """
  end
end
