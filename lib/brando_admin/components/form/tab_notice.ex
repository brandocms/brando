defmodule BrandoAdmin.Components.Form.TabNotice do
  @moduledoc """
  What a form says in a tab that does not edit the entry, because another of
  the editor's tabs does (`BrandoAdmin.LiveView.Form.Tabs`).

  A tab that opened while another one edits shows a notice with Edit here
  and Close; a tab that edited until another one took over shows a banner
  with Take editing back. Both say when the other tab has closed, and
  neither takes editing by itself. The buttons go to the form LiveView
  (`brando_tab_claim`); Close closes the browser tab where the browser lets
  a script do so, and goes to the listing where it doesn't.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Dates
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :access, :map, required: true, doc: "`LiveView.Form.Tabs.current/0`"
  attr :ready?, :boolean, default: true, doc: "false while the entry's blocks load: nothing to take over yet"
  attr :close_to, :string, default: nil, doc: "where Close goes when the browser keeps the tab open"

  def render(%{access: %{mode: :editing}} = assigns), do: ~H""

  def render(%{access: %{mode: :released}} = assigns) do
    ~H"""
    <div id={@id} class="tab-notice tab-notice--banner" role="status" data-testid="tab-notice" data-mode="released">
      <p class="tab-notice-text">
        <Brando.HTML.Icon.icon name="pencil-off" class="tab-notice-icon" />
        <span :if={!@access.closed?}>{gettext("You are editing this entry in another tab. This tab only shows it.")}</span>
        <span :if={@access.closed?}>{gettext("The tab you were editing this entry in was closed.")}</span>
      </p>
      <button type="button" class="btn" phx-click="brando_tab_claim" disabled={!@ready?}>
        {gettext("Take editing back")}
      </button>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="tab-notice" role="status" data-testid="tab-notice" data-mode={@access.mode}>
      <div class="tab-notice-content">
        <span class="tab-notice-heading-icon"><Brando.HTML.Icon.icon name="app-window" class="tab-notice-icon" /></span>
        <div>
          <h2 :if={!@access.closed?}>
            {gettext("You have this entry open in another tab (opened %{time})", time: opened(@access))}
          </h2>
          <h2 :if={@access.closed?}>{gettext("The other tab was closed")}</h2>
          <p :if={@access.mode == :taking}>{gettext("Taking over editing from the other tab…")}</p>
          <p :if={@access.mode != :taking and !@access.closed?}>
            {gettext("One tab edits at a time. Edit here, and the other tab stops editing; your unsaved changes come along.")}
          </p>
          <p :if={@access.mode != :taking and @access.closed?}>
            {gettext("Edit here to continue. If that tab had unsaved changes, they are offered as a recovery copy.")}
          </p>
        </div>
      </div>
      <div class="tab-notice-actions">
        <button
          type="button"
          class="btn btn--primary"
          phx-click="brando_tab_claim"
          disabled={@access.mode == :taking or !@ready?}
        >
          {gettext("Edit here")}
        </button>
        <button type="button" class="btn" phx-click={close(@close_to)}>
          {gettext("Close")}
        </button>
      </div>
    </div>
    """
  end

  defp opened(%{other: %{opened_at: at}}) when is_integer(at), do: at |> DateTime.from_unix!() |> Dates.clock()
  defp opened(_access), do: ""

  # `window.close()` only closes a tab a script opened, in most browsers;
  # otherwise the listing replaces the form.
  defp close(nil), do: JS.dispatch("brando:close-tab")
  defp close(to), do: "brando:close-tab" |> JS.dispatch() |> JS.navigate(to)
end
