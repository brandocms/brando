defmodule BrandoAdmin.Forms.SubmissionsLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component

  alias Brando.Forms
  alias Brando.Forms.Display
  alias Brando.Forms.Field
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace

  @page 50

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def mount(%{"key" => key}, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> BrandoAdmin.Hooks.assign_current_user(token)
       |> set_admin_locale()
       |> assign(:key, key)
       |> assign(:language, nil)
       |> assign(:selected, nil)
       |> assign_forms()
       |> load_submissions()}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  # Every language of the form: the columns follow the first, which is the
  # source of a synchronized group; values are labelled in each submission's own.
  defp assign_forms(socket) do
    forms = Forms.list_forms_by_key(socket.assigns.key)

    columns =
      case forms do
        [first | _] ->
          first.fields |> Enum.filter(&(Field.input?(&1) and &1.type != :consent)) |> Enum.take(3)

        [] ->
          []
      end

    socket
    |> assign(:forms, Map.new(forms, &{to_string(&1.language), &1}))
    |> assign(:title, forms |> List.first() |> then(&(&1 && &1.title)) || socket.assigns.key)
    |> assign(:edit_url, forms |> List.first() |> then(&(&1 && "/admin/forms/update/#{&1.id}")))
    |> assign(:columns, columns)
    |> assign(:can_delete, BrandoAdmin.Authorization.allowed?(:update, Brando.Forms.Form))
  end

  defp load_submissions(socket, offset \\ 0) do
    %{key: key, language: language} = socket.assigns
    page = Forms.list_submissions(key, language: language, limit: @page, offset: offset)
    existing = if offset == 0, do: [], else: socket.assigns.submissions

    socket
    |> assign(:submissions, existing ++ page)
    |> assign(:count, Forms.count_submissions(key, language))
  end

  def render(%{socket_connected: false} = assigns), do: ~H""

  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list form-submissions-workspace">
      <Workspace.header title={gettext("Submissions")} subtitle={@title}>
        <.link :if={@edit_url} navigate={@edit_url} class="workspace-button">{gettext("Edit form")}</.link>
        <a
          :if={@count > 0}
          href={"/admin/forms/#{@key}/submissions/export" <> if(@language, do: "?language=#{@language}", else: "")}
          class="workspace-button primary"
          download
        >
          {gettext("Export CSV")}
        </a>
      </Workspace.header>

      <section class="workspace-panel">
        <header class="workspace-panel-heading">
          <div>
            <h2>{ngettext("1 submission", "%{count} submissions", @count)}</h2>
            <p>{gettext("Newest first. Open a submission to read all of it.")}</p>
          </div>
          <form :if={map_size(@forms) > 1} id="submissions-language" phx-change="filter_language">
            <label class="workspace-sr-only" for="submissions-language-select">{gettext("Language")}</label>
            <select id="submissions-language-select" name="language" class="admin-select">
              <option value="">{gettext("All languages")}</option>
              <option :for={language <- Map.keys(@forms)} value={language} selected={language == @language}>
                {String.upcase(language)}
              </option>
            </select>
          </form>
        </header>

        <Workspace.empty
          :if={@submissions == []}
          title={gettext("No submissions yet")}
          description={gettext("What visitors send with this form is listed here.")}
        />

        <div
          :if={@submissions != []}
          class="workspace-table-scroll"
          tabindex="0"
          role="region"
          aria-label={gettext("Submissions")}
        >
          <table class="workspace-table form-submissions-table">
            <thead>
              <tr>
                <th>{gettext("Received")}</th>
                <th :if={map_size(@forms) > 1}>{gettext("Language")}</th>
                <th :for={column <- @columns}>{column.label || column.key}</th>
                <th><span class="workspace-sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={submission <- @submissions} id={"submission-#{submission.id}"}>
                <td class="monospace">{received(submission)}</td>
                <td :if={map_size(@forms) > 1} class="monospace">{String.upcase(submission.language || "")}</td>
                <td :for={column <- @columns}>{Display.value(@forms, submission, column.key) |> truncate()}</td>
                <td class="workspace-table-actions">
                  <button type="button" class="workspace-button" phx-click="show" phx-value-id={submission.id}>
                    {gettext("Open")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={length(@submissions) < @count} class="form-submissions-more">
          <button type="button" class="workspace-button" phx-click="load_more">{gettext("Show more")}</button>
        </div>
      </section>

      <Content.modal
        :if={@selected}
        id="submission-detail"
        title={gettext("Submission")}
        subtitle={received(@selected)}
        icon="hero-inbox"
        show
        close={JS.push("close")}
        medium
      >
        <dl class="form-submission-detail">
          <%= for {key, label} <- Display.labels(@forms, @selected) do %>
            <dt>{label}</dt>
            <dd>{Display.value(@forms, @selected, key) || "—"}</dd>
          <% end %>
          <dt>{gettext("Page")}</dt>
          <dd class="monospace">{@selected.url || "—"}</dd>
        </dl>
        <:footer>
          <button type="button" class="secondary" phx-click="close">{gettext("Close")}</button>
          <button
            :if={@can_delete}
            type="button"
            class="primary danger"
            phx-click="delete"
            phx-value-id={@selected.id}
            data-confirm={gettext("Delete this submission? This cannot be undone.")}
          >
            {gettext("Delete")}
          </button>
        </:footer>
      </Content.modal>
    </div>
    """
  end

  def handle_event("filter_language", %{"language" => language}, socket) do
    language = if language in Map.keys(socket.assigns.forms), do: language

    {:noreply, socket |> assign(:language, language) |> load_submissions()}
  end

  def handle_event("load_more", _, socket) do
    {:noreply, load_submissions(socket, length(socket.assigns.submissions))}
  end

  def handle_event("show", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected, Forms.get_submission(socket.assigns.key, String.to_integer(id)))}
  end

  def handle_event("close", _, socket), do: {:noreply, assign(socket, :selected, nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    with true <- socket.assigns.can_delete,
         :ok <- Brando.Authorization.Boundary.authorize(socket.assigns.current_user, :update, Brando.Forms.Form),
         {:ok, _} <- Forms.delete_submission(socket.assigns.key, String.to_integer(id)) do
      send(self(), {:toast, gettext("Submission deleted")})
      {:noreply, socket |> assign(:selected, nil) |> load_submissions()}
    else
      _ -> {:noreply, socket}
    end
  end

  defp truncate(nil), do: "—"
  defp truncate(text) when byte_size(text) > 60, do: String.slice(text, 0, 60) <> "…"
  defp truncate(text), do: text

  defp set_admin_locale(%{assigns: %{current_user: user}} = socket) do
    Gettext.put_locale(to_string(user.language))
    socket
  end

  defp received(submission), do: Calendar.strftime(submission.inserted_at, "%Y-%m-%d %H:%M")
end
