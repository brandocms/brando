defmodule BrandoAdmin.Sites.MarkdownSourcesLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext
  alias Brando.MarkdownSources
  alias Brando.MarkdownSources.{Connection, Source}
  alias BrandoAdmin.Components.Workspace

  def __authorization__, do: {:read, :markdown_sources}

  def mount(_, _, socket) do
    Gettext.put_locale(Brando.Gettext, to_string(socket.assigns.current_user.language))
    socket = assign(socket, :socket_connected, connected?(socket))

    if MarkdownSources.authorize(socket.assigns.current_user, :read) == :ok do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Brando.pubsub(), MarkdownSources.topic())
        scope = Brando.Authorization.Scope.current(socket.assigns.current_user)
        if scope.site_id, do: Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.SSG.Builds.topic(scope.site_id))
      end

      {:ok,
       socket
       |> assign(:connections, Connection.available())
       |> assign(:selected, nil)
       |> assign(:source_mode, "file")
       |> assign(:folder, "")
       |> assign(:folder_paths, nil)
       |> assign(:folder_selection, [])
       |> assign(:folder_connection, nil)
       |> assign(:folder_ref, nil)
       |> assign(:discovering, false)
       |> assign(:notice, nil)
       |> assign(:source, %Source{})
       |> assign(:form, to_form(Source.changeset(%Source{}, %{}), as: :source))
       |> refresh()}
    else
      {:ok, redirect(socket, to: "/admin")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace markdown-workspace">
      <span class="markdown-eyebrow">{gettext("Configuration")}</span>
      <Workspace.header
        title={gettext("Markdown sources")}
        subtitle={gettext("Connect repository documents to entry blocks.")}
      />
      <div :if={@notice} role="status" class="markdown-source-notice">{@notice}</div>
      <section :if={@connections == []} class="markdown-connection-notice">
        <Brando.HTML.Icon.icon name="hero-code-bracket" />
        <div>
          <h2>{gettext("A developer needs to connect your repository")}</h2>
          <p>
            {gettext(
              "GitHub connections are configured by a developer in the project's runtime.exs. Ask them to add a repository and enable it for this environment. The connection will then appear here."
            )}
          </p>
        </div>
      </section>
      <div class="markdown-sources-workspace">
        <section class="markdown-source-panel markdown-source-setup">
          <div class="markdown-panel-heading">
            <Brando.HTML.Icon.icon name="hero-document-plus" /><h2>
              {if @source.id, do: gettext("Edit source"), else: gettext("Add a source")}
            </h2>
          </div>
          <div :if={!@source.id} class="markdown-source-modes" role="group" aria-label={gettext("Add documents")}>
            <button
              type="button"
              phx-click="source_mode"
              phx-value-mode="file"
              aria-pressed={to_string(@source_mode == "file")}
            >{gettext("Single file")}</button>
            <button
              type="button"
              phx-click="source_mode"
              phx-value-mode="folder"
              aria-pressed={to_string(@source_mode == "folder")}
            >{gettext("From a folder")}</button>
          </div>
          <.form
            for={@form}
            id="markdown-source-form"
            phx-change="validate"
            phx-submit={if @source_mode == "folder", do: "discover_folder", else: "save"}
          >
            <fieldset disabled={@connections == [] || !@can_manage || @discovering}>
              <div :if={@source_mode == "file"} class="markdown-source-field">
                <label for="source_name">{gettext("Name")}</label>
                <input
                  id="source_name"
                  type="text"
                  name={@form[:name].name}
                  value={@form[:name].value}
                  required
                  maxlength="160"
                />
              </div>
              <div class="markdown-source-field">
                <label for="source_connection">{gettext("Repository connection")}</label>
                <select class="admin-select" id="source_connection" name={@form[:connection].name} required>
                  <option value="">{gettext("Choose a connection")}</option>
                  <option :for={key <- @connections} value={key} selected={key == @form[:connection].value}>{key}</option>
                </select>
              </div>
              <div class="markdown-source-field">
                <label for="source_ref">{gettext("Branch ref")}</label>
                <input
                  id="source_ref"
                  type="text"
                  name={@form[:ref].name}
                  value={@form[:ref].value}
                  placeholder="refs/heads/main"
                  required
                />
              </div>
              <div :if={@source_mode == "file"} class="markdown-source-field">
                <label for="source_path">{gettext("Markdown file")}</label>
                <input
                  id="source_path"
                  type="text"
                  name={@form[:path].name}
                  value={@form[:path].value}
                  placeholder="guides/installation.md"
                  required
                />
                <p>{gettext("Path from the repository root. Use From a folder to add several files at once.")}</p>
              </div>
              <div :if={@source_mode == "folder"} class="markdown-source-field">
                <label for="source_folder">{gettext("Folder")}</label>
                <input id="source_folder" type="text" name="folder" value={@folder} placeholder="guides" />
                <p>
                  {gettext(
                    "Includes subfolders. Leave blank for the repository root. Choose which files to add in the next step."
                  )}
                </p>
              </div>
              <label :if={@source_mode == "file"} class="markdown-source-checkbox">
                <input type="hidden" name={@form[:enabled].name} value="false" />
                <input type="checkbox" name={@form[:enabled].name} value="true" checked={@form[:enabled].value} />
                {gettext("Enable synchronization")}
              </label>
              <ul
                :if={@source_mode == "file" && @form.source.action && @form.errors != []}
                role="alert"
                class="markdown-source-errors"
              >
                <li :for={{field, {message, opts}} <- @form.errors} :if={Phoenix.Component.used_input?(@form[field])}>
                  {field_label(field)}: {translate_error(message, opts)}
                </li>
              </ul>
              <div class="markdown-source-actions">
                <button type="submit" class="primary" phx-disable-with={gettext("Please wait…")}>
                  {if @source_mode == "folder", do: gettext("Find Markdown files"), else: gettext("Save source")}
                </button>
              </div>
            </fieldset>
          </.form>
          <div :if={@source.id} class="markdown-source-actions">
            <button type="button" phx-click="new">{gettext("Add another source")}</button>
          </div>
          <p :if={@discovering} role="status" class="markdown-source-note">{gettext("Finding Markdown files…")}</p>
          <form
            :if={@source_mode == "folder" && @folder_paths != nil}
            id="markdown-folder-selection"
            phx-change="select_documents"
            phx-submit="add_documents"
          >
            <p class="markdown-source-note">
              {gettext(
                "One source is created per selected file. Existing sources are skipped. New files added to the folder later must be selected here again."
              )}
            </p>
            <p :if={@folder_paths == []} class="markdown-source-note">{gettext("No Markdown files found in this folder.")}</p>
            <div class="markdown-folder-files">
              <label :for={path <- @folder_paths} class="markdown-source-checkbox">
                <input type="checkbox" name="paths[]" value={path} checked={path in @folder_selection} /><span>{path}</span>
              </label>
            </div>
            <div class="markdown-source-actions">
              <button type="submit" class="primary" disabled={@folder_selection == [] || !@can_manage}>{ngettext(
                "Add %{count} document",
                "Add %{count} documents",
                length(@folder_selection)
              )}</button>
            </div>
          </form>
        </section>
        <section class="markdown-source-panel markdown-documents">
          <div class="markdown-panel-heading">
            <Brando.HTML.Icon.icon name="hero-document-text" /><h2>{gettext("Connected documents")}</h2><span class="workspace-badge">{length(
              @sources
            )}</span>
          </div>
          <div :if={@sources == []} class="workspace-empty">
            <Brando.HTML.Icon.icon name="hero-document-text" /><h3>{gettext("No documents connected yet")}</h3>
            <p>{gettext("Add a file or choose a folder. Each document becomes a source you can use in a content block.")}</p>
          </div>
          <article :for={source <- @sources} id={"markdown-source-#{source.id}"} class="markdown-source-row">
            <div class="markdown-document-info">
              <div class="markdown-document-title">
                <h3>{source.name}</h3><p class="markdown-source-path">{source.path}</p>
              </div>
              <dl class="markdown-source-meta">
                <div>
                  <dt>{gettext("Connection")}</dt><dd>{source.connection}</dd>
                </div>
                <div>
                  <dt>{gettext("Branch")}</dt><dd>{String.replace_prefix(source.ref, "refs/heads/", "")}</dd>
                </div>
                <div>
                  <dt>{gettext("Status")}</dt><dd>
                    {if source.enabled, do: publication_status(source), else: gettext("Synchronization disabled")}
                  </dd>
                </div>
                <div>
                  <dt>{gettext("Last checked")}</dt><dd>
                    {if source.last_checked_at,
                      do: Calendar.strftime(source.last_checked_at, "%Y-%m-%d %H:%M UTC"),
                      else: gettext("Never")}
                  </dd>
                </div>
              </dl>
              <a :if={source.build_id} href="/admin/config/publishing">{gettext("Open Publishing")}</a>
              <p :if={source.last_error} role="status" class="markdown-source-error">{source.last_error}</p>
            </div>
            <div class="markdown-source-actions">
              <button type="button" phx-click="edit" phx-value-id={source.id}>{gettext("Edit")}</button>
              <button type="button" phx-click="sync" phx-value-id={source.id} disabled={!@can_sync || !source.enabled}>{gettext(
                "Refresh from GitHub"
              )}</button>
              <button type="button" phx-click="history" phx-value-id={source.id}>{gettext("History")}</button>
            </div>
            <ol :if={@selected == source.id} class="markdown-source-history">
              <li :for={event <- @events}>
                {Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")} · {event_label(event.action)}{if event.message,
                  do: " · " <> event.message}
              </li>
            </ol>
          </article>
        </section>
      </div>
    </div>
    """
  end

  def handle_event("validate", %{"source" => params} = all_params, socket) do
    changeset = Source.changeset(socket.assigns.source, params) |> Map.put(:action, :validate)

    {:noreply,
     assign(socket,
       form: to_form(changeset, as: :source),
       folder: all_params["folder"] || "",
       folder_paths: nil,
       folder_selection: []
     )}
  end

  def handle_event("source_mode", %{"mode" => mode}, socket) when mode in ~w(file folder) do
    {:noreply, assign(socket, source_mode: mode, folder_paths: nil, folder_selection: [], notice: nil)}
  end

  def handle_event("discover_folder", %{"source" => params} = all_params, socket) do
    with :ok <- MarkdownSources.authorize(socket.assigns.current_user, :create),
         {:ok, connection} <- Connection.current(params["connection"]) do
      provider = Application.get_env(:brando, :markdown_sources_provider, Brando.MarkdownSources.GitHub)
      options = %{ref: params["ref"], folder: all_params["folder"] || ""}

      {:noreply,
       socket
       |> assign(
         discovering: true,
         folder_paths: nil,
         folder_selection: [],
         notice: nil,
         folder_connection: connection.key,
         folder_ref: params["ref"]
       )
       |> start_async(:discover_folder, fn -> provider.list_documents(connection, options) end)}
    else
      _ -> {:noreply, assign(socket, notice: gettext("Choose an available repository connection."))}
    end
  end

  def handle_event("select_documents", params, socket) do
    selected = Enum.filter(params["paths"] || [], &(&1 in (socket.assigns.folder_paths || [])))
    {:noreply, assign(socket, folder_selection: selected)}
  end

  def handle_event("add_documents", params, socket) do
    paths = Enum.filter(params["paths"] || [], &(&1 in (socket.assigns.folder_paths || [])))

    case MarkdownSources.add_documents(
           socket.assigns.folder_connection,
           socket.assigns.folder_ref,
           paths,
           socket.assigns.current_user
         ) do
      {:ok, count} ->
        {:noreply,
         socket
         |> refresh()
         |> assign(
           folder_paths: nil,
           folder_selection: [],
           notice:
             ngettext(
               "%{count} document added. Refresh it to import the content.",
               "%{count} documents added. Refresh them to import the content.",
               count
             )
         )}

      _ ->
        {:noreply,
         assign(socket, notice: gettext("The documents could not be added. Check the connection and try again."))}
    end
  end

  def handle_event("save", %{"source" => params}, socket) do
    case MarkdownSources.save_source(socket.assigns.source, params, socket.assigns.current_user) do
      {:ok, source} ->
        {:noreply,
         socket
         |> edit(source)
         |> refresh()
         |> assign(:notice, gettext("Source saved. Refresh it to import the document."))}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: :source))}

      {:error, _} ->
        {:noreply,
         assign(socket, :notice, gettext("The source could not be saved. Check your access and reload if it changed."))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, edit(socket, MarkdownSources.get_source(id) || %Source{})}
  end

  def handle_event("new", _, socket), do: {:noreply, edit(socket, %Source{})}

  def handle_event("sync", %{"id" => id}, socket) do
    case MarkdownSources.refresh(id, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, assign(socket, :notice, gettext("Refresh queued."))}

      _ ->
        {:noreply,
         assign(socket, :notice, gettext("Refresh is unavailable. Check the source connection and your permissions."))}
    end
  end

  def handle_event("history", %{"id" => id}, socket) do
    id = MarkdownSources.integer_id(id)
    {:noreply, assign(socket, selected: id, events: if(id, do: MarkdownSources.events(id), else: []))}
  end

  def handle_async(:discover_folder, {:ok, {:ok, paths}}, socket),
    do: {:noreply, assign(socket, discovering: false, folder_paths: paths, folder_selection: paths)}

  def handle_async(:discover_folder, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, discovering: false, notice: folder_error(reason))}

  def handle_async(:discover_folder, {:exit, _}, socket),
    do: {:noreply, assign(socket, discovering: false, notice: folder_error(:unavailable))}

  def handle_info({:ssg_build_updated, _}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:markdown_source_updated, _}, socket), do: {:noreply, refresh(socket)}

  defp edit(socket, source),
    do:
      assign(socket,
        source: source,
        source_mode: "file",
        folder_paths: nil,
        folder_selection: [],
        form: to_form(Source.changeset(source, %{}), as: :source),
        can_manage:
          MarkdownSources.authorize(socket.assigns.current_user, if(source.id, do: :update, else: :create)) == :ok
      )

  defp refresh(socket) do
    assign(socket,
      sources: MarkdownSources.list_sources(),
      can_manage:
        MarkdownSources.authorize(socket.assigns.current_user, if(socket.assigns.source.id, do: :update, else: :create)) ==
          :ok,
      can_sync: MarkdownSources.authorize(socket.assigns.current_user, :sync) == :ok,
      events: if(socket.assigns.selected, do: MarkdownSources.events(socket.assigns.selected), else: [])
    )
  end

  defp publication_status(%{build_id: id, publication_status: status, publication_sequence: sequence})
       when is_integer(id) do
    case Brando.SSG.Builds.get_build(id) do
      %{markdown_context: %{"source_revision" => old_sequence}} when old_sequence != sequence -> status_label(status)
      %{status: :deployed} -> gettext("Deployed")
      %{status: :failed} -> gettext("Build failed — see Publishing")
      %{status: :ready} -> gettext("Built — see Publishing for deployment")
      %{status: :queued} -> gettext("Build queued")
      %{status: :building} -> gettext("Building")
      %{status: :archived} -> gettext("Previous build archived")
      _ -> status_label(status)
    end
  end

  defp publication_status(source), do: status_label(source.publication_status)

  defp status_label("Not imported"), do: gettext("Not imported")
  defp status_label("Rendered"), do: gettext("Rendered")
  defp status_label("Build queued"), do: gettext("Build queued")
  defp status_label(status), do: status

  defp event_label("source.saved"), do: gettext("Source saved")
  defp event_label("source.refresh_requested"), do: gettext("Refresh requested")
  defp event_label("source.imported"), do: gettext("Document imported")
  defp event_label("source.unchanged"), do: gettext("Document unchanged")
  defp event_label("source.failed"), do: gettext("Document refresh failed")
  defp event_label("placement.saved"), do: gettext("Document placement saved")
  defp event_label("publication.queued"), do: gettext("Publication queued")
  defp event_label("publication.failed"), do: gettext("Publication failed")
  defp event_label(action), do: action

  defp folder_error(:too_many_documents),
    do: gettext("This folder is too large. Choose a smaller folder with up to 200 Markdown files.")

  defp folder_error(:response_too_large), do: folder_error(:too_many_documents)

  defp folder_error(_),
    do: gettext("Could not read this folder. Check the repository connection, branch and folder path, then try again.")

  defp field_label(:name), do: gettext("Name")
  defp field_label(:connection), do: gettext("Repository connection")
  defp field_label(:ref), do: gettext("Branch ref")
  defp field_label(:path), do: gettext("Markdown file")
  defp field_label(field), do: to_string(field)
  defp translate_error(message, opts), do: Gettext.gettext(Brando.Gettext, message, opts)
end
