defmodule BrandoAdmin.Sites.MarkdownSourcesLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext
  alias Brando.MarkdownSources
  alias Brando.MarkdownSources.{Connection, Source}

  def __authorization__, do: {:read, :markdown_sources}

  def mount(_, _, socket) do
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
    <header class="markdown-sources-heading">
      <span>{gettext("Configuration")}</span>
      <h1>{gettext("Markdown sources")}</h1>
      <p>{gettext("Connect repository documents to entry blocks.")}</p>
    </header>
    <p :if={@notice} role="status" class="markdown-source-notice">{@notice}</p>
    <div class="markdown-sources-workspace">
      <section class="markdown-source-panel">
        <h2>{if @source.id, do: gettext("Edit source"), else: gettext("Add a source")}</h2>
        <p :if={@connections == []}>
          {gettext(
            "Configure a GitHub connection on the server to add sources. Connections contain the repository, webhook secret, and allowed environments."
          )}
        </p>
        <.form for={@form} id="markdown-source-form" phx-change="validate" phx-submit="save">
          <label for="source_name">{gettext("Name")}</label>
          <input id="source_name" type="text" name={@form[:name].name} value={@form[:name].value} required maxlength="160" />
          <label for="source_connection">{gettext("Repository connection")}</label>
          <select id="source_connection" name={@form[:connection].name} required>
            <option value="">{gettext("Choose a connection")}</option>
            <option :for={key <- @connections} value={key} selected={key == @form[:connection].value}>{key}</option>
          </select>
          <label for="source_ref">{gettext("Branch ref")}</label>
          <input
            id="source_ref"
            type="text"
            name={@form[:ref].name}
            value={@form[:ref].value}
            placeholder="refs/heads/main"
            required
          />
          <label for="source_path">{gettext("Markdown file")}</label>
          <input
            id="source_path"
            type="text"
            name={@form[:path].name}
            value={@form[:path].value}
            placeholder="guides/installation.md"
            required
          />
          <label class="markdown-source-checkbox">
            <input type="hidden" name={@form[:enabled].name} value="false" />
            <input type="checkbox" name={@form[:enabled].name} value="true" checked={@form[:enabled].value} />
            {gettext("Enable synchronization")}
          </label>
          <ul :if={@form.source.action && @form.errors != []} role="alert">
            <li :for={{field, {message, _}} <- @form.errors}>{field}: {message}</li>
          </ul>
          <div class="markdown-source-actions">
            <button type="submit" class="primary" disabled={!@can_manage} phx-disable-with={gettext("Saving…")}>{gettext(
              "Save source"
            )}</button>
            <button :if={@source.id} type="button" class="markdown-source-button" phx-click="new">{gettext(
              "Add another source"
            )}</button>
          </div>
        </.form>
      </section>
      <section class="markdown-source-panel">
        <h2>{gettext("Connected documents")}</h2>
        <p :if={@sources == []}>{gettext("No Markdown sources have been added to this environment.")}</p>
        <article :for={source <- @sources} id={"markdown-source-#{source.id}"} class="markdown-source-row">
          <div>
            <h3>{source.name}</h3>
            <p>{source.path}</p>
            <dl class="markdown-source-meta">
              <div>
                <dt>{gettext("Connection")}</dt><dd>{source.connection}</dd>
              </div>
              <div>
                <dt>{gettext("Branch")}</dt><dd>{source.ref}</dd>
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
            <p :if={source.last_error} role="status">{source.last_error}</p>
          </div>
          <div class="markdown-source-actions">
            <button type="button" class="markdown-source-button" phx-click="edit" phx-value-id={source.id}>{gettext("Edit")}</button>
            <button
              type="button"
              class="markdown-source-button"
              phx-click="sync"
              phx-value-id={source.id}
              disabled={!@can_sync || !source.enabled}
            >{gettext("Refresh from GitHub")}</button>
            <button type="button" class="markdown-source-button" phx-click="history" phx-value-id={source.id}>{gettext(
              "History"
            )}</button>
          </div>
          <ol :if={@selected == source.id} class="markdown-source-history">
            <li :for={event <- @events}>
              {Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")} · {event.action}{if event.message,
                do: " · " <> event.message}
            </li>
          </ol>
        </article>
      </section>
    </div>
    """
  end

  def handle_event("validate", %{"source" => params}, socket) do
    changeset = Source.changeset(socket.assigns.source, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :source))}
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

  def handle_info({:ssg_build_updated, _}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:markdown_source_updated, _}, socket), do: {:noreply, refresh(socket)}

  defp edit(socket, source),
    do:
      assign(socket,
        source: source,
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
      %{markdown_context: %{"source_revision" => old_sequence}} when old_sequence != sequence -> status
      %{status: :deployed} -> gettext("Deployed")
      %{status: :failed} -> gettext("Build failed — see Publishing")
      %{status: :ready} -> gettext("Built — see Publishing for deployment")
      %{status: :queued} -> gettext("Build queued")
      %{status: :building} -> gettext("Building")
      %{status: :archived} -> gettext("Previous build archived")
      _ -> status
    end
  end

  defp publication_status(source), do: source.publication_status
end
