defmodule BrandoAdmin.Forms.InboxLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component

  alias Brando.Forms
  alias BrandoAdmin.Components.Workspace

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> BrandoAdmin.Hooks.assign_current_user(token)
       |> set_admin_locale()
       |> assign(:page_title, gettext("Forms"))
       |> assign(:can_configure, BrandoAdmin.Authorization.allowed?(:update, Brando.Forms.Form))
       |> assign(:forms, Forms.list_submission_summaries())}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  def render(%{socket_connected: false} = assigns), do: ~H""

  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list form-submissions-workspace">
      <Workspace.header title={gettext("Forms")} subtitle={gettext("What visitors have sent with the site's forms")}>
        <.link :if={@can_configure} navigate="/admin/config/forms" class="workspace-button">
          {gettext("Configure forms")}
        </.link>
      </Workspace.header>

      <section class="workspace-panel">
        <Workspace.empty
          :if={@forms == []}
          title={gettext("No forms yet")}
          description={gettext("Forms are built under Configuration → Forms.")}
        />

        <div :if={@forms != []} class="workspace-table-scroll" tabindex="0" role="region" aria-label={gettext("Forms")}>
          <table class="workspace-table form-inbox-table">
            <thead>
              <tr>
                <th>{gettext("Form")}</th>
                <th>{gettext("Submissions")}</th>
                <th>{gettext("Latest")}</th>
                <th><span class="workspace-sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={form <- @forms} id={"form-inbox-#{form.key}"}>
                <td>
                  {form.title}<br />
                  <small class="monospace">{form.key}</small>
                </td>
                <td class="monospace">{form.count}</td>
                <td class="monospace">{latest(form.latest)}</td>
                <td class="workspace-table-actions">
                  <.link navigate={"/admin/forms/#{form.key}/submissions"} class="workspace-button">
                    {gettext("Open")}
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  defp latest(nil), do: "—"
  defp latest(at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")

  defp set_admin_locale(%{assigns: %{current_user: user}} = socket) do
    Gettext.put_locale(to_string(user.language))
    socket
  end
end
