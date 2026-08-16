defmodule BrandoAdmin.Content.SharedLibraryLive do
  @moduledoc false

  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.SharedLibrary
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry
  alias BrandoAdmin.Components.Content

  @kinds [:module, :container, :palette]
  @global_events ~w(select_site set_access enable_all disable_all create update delete)

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    global_manager? = socket.assigns.current_user.role == :superuser

    site_access? =
      not is_nil(socket.assigns.current_site) and
        Access.can_access?(socket.assigns.current_user, socket.assigns.current_site)

    cond do
      Tenant.mode() != :multi or (not global_manager? and not site_access?) ->
        {:ok, redirect(socket, to: "/admin")}

      connected?(socket) ->
        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> assign(:global_manager?, global_manager?)
         |> assign(:selected_site_id, socket.assigns.current_site && socket.assigns.current_site.id)
         |> assign(
           :selected_environment_id,
           socket.assigns.current_environment && socket.assigns.current_environment.id
         )
         |> refresh()}

      true ->
        {:ok,
         socket
         |> assign(:socket_connected, false)
         |> assign(:global_manager?, global_manager?)}
    end
  end

  @impl Phoenix.LiveView
  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Shared content library")}
      subtitle={gettext("Curate reusable modules, containers, and palettes across sites")}
    >
      <button type="button" class="secondary" phx-click="refresh">{gettext("Refresh")}</button>
    </Content.header>

    <div class="environment-management-live shared-library-live">
      <section class="environment-panel">
        <header>
          <div>
            <h2>
              {if @global_manager?, do: gettext("Site access and overrides"), else: gettext("Site library")}
            </h2>
            <p>
              {gettext("Access controls what appears when creating content. Disabling an item never breaks existing blocks.")}
            </p>
          </div>
        </header>

        <div :if={@sites == []} class="empty">{gettext("Create a site before assigning library access.")}</div>

        <div :if={@selected_site} class="environment-grid">
          <label :if={@global_manager?}>
            <span>{gettext("Site")}</span>
            <select name="site_id" phx-change="select_site">
              <option :for={site <- @sites} value={site.id} selected={site.id == @selected_site.id}>
                {site.name}
              </option>
            </select>
          </label>

          <div :if={!@global_manager?}>
            <span>{gettext("Site")}</span>
            <strong>{@selected_site.name}</strong>
          </div>

          <label>
            <span>{gettext("Environment for overrides")}</span>
            <select name="environment_id" phx-change="select_environment">
              <option
                :for={environment <- @selected_site.environments}
                value={environment.id}
                selected={@selected_environment && environment.id == @selected_environment.id}
              >
                {environment.name}{if environment.live, do: " · live", else: ""}
              </option>
            </select>
          </label>
        </div>

        <div :if={@selected_site && @global_manager?} class="environment-grid">
          <.access_form
            :for={kind <- @kinds}
            kind={kind}
            entries={Map.fetch!(@libraries, kind)}
            enabled={Map.fetch!(@enabled, kind)}
          />
        </div>
      </section>

      <section :for={kind <- @kinds} class="environment-panel" id={"shared-library-#{kind}"}>
        <header>
          <div>
            <h2>{kind_title(kind)}</h2>
            <p>{kind_description(kind)}</p>
          </div>
          <span class="badge">{length(Map.fetch!(@libraries, kind))}</span>
        </header>

        <.create_form :if={@global_manager?} kind={kind} />

        <div :if={Map.fetch!(@libraries, kind) == []} class="empty">
          {gettext("No shared entries yet.")}
        </div>

        <article
          :for={entry <- Map.fetch!(@libraries, kind)}
          class="environment-panel shared-library-entry"
          id={"shared-#{kind}-#{entry.id}"}
        >
          <% usage = Map.get(@usage, {kind, entry.id}, []) %>
          <% effective = Map.get(@effective, {kind, entry.id}) %>
          <% overridden? = effective && Map.get(effective, source_field(kind)) %>

          <header>
            <div>
              <h3>{entry_label(entry)}</h3>
              <p>
                <span class="badge">v{entry.version || 1}</span>
                <span :if={entry.version_note not in [nil, ""]}>{entry.version_note}</span>
              </p>
            </div>
            <div :if={@global_manager?} class="environment-actions">
              <.link
                :if={kind == :module}
                navigate={"/admin/config/content/shared_library/modules/update/#{entry.id}"}
                class="secondary button"
              >
                {gettext("Edit")}
              </.link>
              <button
                type="button"
                class="danger"
                phx-click="delete"
                phx-value-kind={kind}
                phx-value-id={entry.id}
                phx-confirm={gettext("Delete this shared entry? This is blocked while any site uses it.")}
              >
                {gettext("Delete")}
              </button>
            </div>
          </header>

          <div class="environment-grid">
            <section :if={@global_manager?}>
              <h4>{gettext("Impact")}</h4>
              <p :if={usage == []}>{gettext("No sites currently use this entry.")}</p>
              <ul :if={usage != []}>
                <li :for={item <- usage}>
                  <strong>{item.site.name}</strong>
                  <span :if={item.enabled}> · {gettext("enabled")}</span>
                  <span :if={item.overridden_environments != []}>
                    · {gettext("customized in %{envs}", envs: Enum.join(item.overridden_environments, ", "))}
                  </span>
                  <span :if={item.referenced_environments != []}>
                    · {gettext("used in %{envs}", envs: Enum.join(item.referenced_environments, ", "))}
                  </span>
                </li>
              </ul>
            </section>

            <section :if={@selected_site && @selected_environment}>
              <h4>{gettext("Selected environment")}</h4>
              <p>
                {@selected_site.name} · {@selected_environment.name}
                <span :if={overridden?} class="badge">{gettext("customized")}</span>
                <span :if={effective && effective.update_available} class="badge warning">
                  {gettext("update available")}
                </span>
              </p>

              <div class="environment-actions">
                <.link
                  :if={overridden? && @can_customize?}
                  navigate={override_route(kind, effective, @selected_site, @selected_environment)}
                  class="secondary button"
                >
                  {gettext("Edit customization")}
                </.link>
                <button
                  :if={@can_customize? && enabled?(@enabled, kind, entry.id) && !overridden?}
                  type="button"
                  class="secondary"
                  phx-click="customize"
                  phx-value-kind={kind}
                  phx-value-id={entry.id}
                >
                  {gettext("Customize")}
                </button>
                <button
                  :if={@can_customize? && overridden?}
                  type="button"
                  class="secondary"
                  phx-click="reset"
                  phx-value-kind={kind}
                  phx-value-id={entry.id}
                  phx-confirm={gettext("Discard this environment's customization and use shared again?")}
                >
                  {gettext("Reset to shared")}
                </button>
                <button
                  :if={@can_customize? && effective && effective.update_available}
                  type="button"
                  class="primary"
                  phx-click="accept_update"
                  phx-value-kind={kind}
                  phx-value-id={entry.id}
                  phx-confirm={gettext("Replace the customized version with the current shared version?")}
                >
                  {gettext("Accept update")}
                </button>
                <button
                  :if={@can_customize? && effective && effective.update_available}
                  type="button"
                  class="secondary"
                  phx-click="dismiss_update"
                  phx-value-kind={kind}
                  phx-value-id={entry.id}
                >
                  {gettext("Dismiss")}
                </button>
              </div>

              <details :if={Map.has_key?(@diffs, {kind, entry.id})}>
                <summary>{gettext("View changes")}</summary>
                <dl>
                  <div :for={{field, change} <- Map.fetch!(@diffs, {kind, entry.id})}>
                    <dt>{field}</dt>
                    <dd>
                      <small>{gettext("Shared")}</small> {format_value(change.shared)}<br />
                      <small>{gettext("Customized")}</small> {format_value(change.override)}
                    </dd>
                  </div>
                </dl>
              </details>
            </section>
          </div>

          <.inline_edit_form :if={@global_manager? && kind != :module} kind={kind} entry={entry} />
        </article>
      </section>
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :entries, :list, required: true
  attr :enabled, MapSet, required: true

  defp access_form(assigns) do
    ~H"""
    <section>
      <h3>{kind_title(@kind)}</h3>
      <form phx-submit="set_access" id={"access-#{@kind}"}>
        <input type="hidden" name="access[kind]" value={@kind} />
        <input type="hidden" name="access[ids][]" value="" />
        <label :for={entry <- @entries} class="checkbox">
          <input
            type="checkbox"
            name="access[ids][]"
            value={entry.id}
            checked={MapSet.member?(@enabled, entry.id)}
          />
          <span>{entry_label(entry)} · v{entry.version || 1}</span>
        </label>
        <div class="environment-actions">
          <button type="submit" class="primary">{gettext("Save access")}</button>
          <button type="button" class="secondary" phx-click="enable_all" phx-value-kind={@kind}>
            {gettext("Enable all")}
          </button>
          <button type="button" class="secondary" phx-click="disable_all" phx-value-kind={@kind}>
            {gettext("Disable all")}
          </button>
        </div>
      </form>
    </section>
    """
  end

  attr :kind, :atom, required: true

  defp create_form(assigns) do
    ~H"""
    <details class="shared-library-create">
      <summary>{gettext("Create shared %{kind}", kind: kind_singular(@kind))}</summary>
      <form phx-submit="create" id={"create-shared-#{@kind}"}>
        <input type="hidden" name="entry[kind]" value={@kind} />
        <div class="environment-grid">
          <label><span>{gettext("Name")}</span><input name="entry[name]" required /></label>
          <label><span>{gettext("Namespace")}</span><input name="entry[namespace]" value="general" required /></label>
          <label :if={@kind == :palette}><span>{gettext("Key")}</span><input name="entry[key]" required /></label>
          <label :if={@kind == :container}>
            <span>{gettext("Template type")}</span>
            <select name="entry[type]"><option value="liquid">Liquid</option><option value="heex">HEEx</option></select>
          </label>
        </div>
        <label :if={@kind in [:module, :container]}>
          <span>{gettext("Code")}</span>
          <textarea name="entry[code]" rows="6" required>{default_code(@kind)}</textarea>
        </label>
        <label :if={@kind == :palette}>
          <span>{gettext("Colors (JSON)")}</span>
          <textarea name="entry[colors_json]" rows="4">[]</textarea>
        </label>
        <button type="submit" class="primary">{gettext("Create")}</button>
      </form>
    </details>
    """
  end

  attr :kind, :atom, required: true
  attr :entry, :any, required: true

  defp inline_edit_form(assigns) do
    ~H"""
    <details>
      <summary>{gettext("Edit and publish a new version")}</summary>
      <form phx-submit="update" id={"update-shared-#{@kind}-#{@entry.id}"}>
        <input type="hidden" name="entry[kind]" value={@kind} />
        <input type="hidden" name="entry[id]" value={@entry.id} />
        <div class="environment-grid">
          <label><span>{gettext("Name")}</span><input name="entry[name]" value={entry_label(@entry)} required /></label>
          <label><span>{gettext("Namespace")}</span><input name="entry[namespace]" value={@entry.namespace} required /></label>
          <label :if={@kind == :palette}><span>{gettext("Key")}</span><input name="entry[key]" value={@entry.key} required /></label>
          <label><span>{gettext("Changelog note")}</span><input name="entry[version_note]" required /></label>
        </div>
        <label :if={@kind == :container}>
          <span>{gettext("Code")}</span>
          <textarea name="entry[code]" rows="8" required>{@entry.code}</textarea>
        </label>
        <label :if={@kind == :palette}>
          <span>{gettext("Colors (JSON)")}</span>
          <textarea name="entry[colors_json]" rows="5">{colors_json(@entry)}</textarea>
        </label>
        <button type="submit" class="primary">{gettext("Publish version")}</button>
      </form>
    </details>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket), do: {:noreply, refresh(socket)}

  def handle_event(event, _params, %{assigns: %{global_manager?: false}} = socket)
      when event in @global_events do
    {:noreply, notify_error(socket, error_message(:not_authorized))}
  end

  def handle_event("select_site", %{"site_id" => site_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_site_id, parse_id!(site_id))
     |> assign(:selected_environment_id, nil)
     |> refresh()}
  end

  def handle_event("select_environment", %{"environment_id" => environment_id}, socket) do
    {:noreply, socket |> assign(:selected_environment_id, parse_id!(environment_id)) |> refresh()}
  end

  def handle_event("set_access", %{"access" => %{"kind" => kind, "ids" => ids}}, socket) do
    with {:ok, kind} <- parse_kind(kind),
         site when not is_nil(site) <- socket.assigns.selected_site,
         :ok <- SharedLibrary.set_enabled(site, kind, Enum.reject(ids, &(&1 == ""))) do
      {:noreply, socket |> notify(gettext("Shared library access updated.")) |> refresh()}
    else
      error -> {:noreply, notify_error(socket, error_message(error))}
    end
  end

  def handle_event("enable_all", %{"kind" => kind}, socket) do
    with {:ok, kind} <- parse_kind(kind),
         site when not is_nil(site) <- socket.assigns.selected_site do
      ids = Enum.map(Map.fetch!(socket.assigns.libraries, kind), & &1.id)
      update_access(socket, site, kind, ids)
    else
      error -> {:noreply, notify_error(socket, error_message(error))}
    end
  end

  def handle_event("disable_all", %{"kind" => kind}, socket) do
    with {:ok, kind} <- parse_kind(kind),
         site when not is_nil(site) <- socket.assigns.selected_site do
      update_access(socket, site, kind, [])
    else
      error -> {:noreply, notify_error(socket, error_message(error))}
    end
  end

  def handle_event("create", %{"entry" => params}, socket) do
    with {:ok, kind} <- parse_kind(params["kind"]),
         {:ok, attrs} <- entry_attrs(kind, params),
         {:ok, _entry} <- SharedLibrary.create_shared(kind, attrs, socket.assigns.current_user) do
      {:noreply, socket |> notify(gettext("Shared entry created.")) |> refresh()}
    else
      error -> {:noreply, notify_error(socket, error_message(error))}
    end
  end

  def handle_event("update", %{"entry" => params}, socket) do
    with {:ok, kind} <- parse_kind(params["kind"]),
         {:ok, attrs} <- entry_attrs(kind, params),
         {:ok, _entry} <-
           SharedLibrary.update_shared(kind, params["id"], attrs, socket.assigns.current_user) do
      {:noreply, socket |> notify(gettext("Shared version published.")) |> refresh()}
    else
      error -> {:noreply, notify_error(socket, error_message(error))}
    end
  end

  def handle_event("delete", params, socket) do
    with {:ok, kind} <- parse_kind(params["kind"]),
         {:ok, _entry} <- SharedLibrary.delete_shared(kind, params["id"]) do
      {:noreply, socket |> notify(gettext("Shared entry deleted.")) |> refresh()}
    else
      error -> {:noreply, notify_error(socket, error_message(error))}
    end
  end

  for {event, function} <- [
        {"customize", :customize},
        {"reset", :reset},
        {"accept_update", :accept_update},
        {"dismiss_update", :dismiss_update}
      ] do
    def handle_event(unquote(event), params, socket) do
      run_override_action(socket, unquote(function), params)
    end
  end

  defp run_override_action(socket, function, params) do
    with :ok <- authorize_customize(socket),
         {:ok, kind} <- parse_kind(params["kind"]),
         site when not is_nil(site) <- socket.assigns.selected_site,
         environment when not is_nil(environment) <- socket.assigns.selected_environment do
      prefix = Tenant.prefix(site, environment)

      result =
        case function do
          :customize ->
            SharedLibrary.customize(kind, params["id"], site, prefix, socket.assigns.current_user)

          :reset ->
            SharedLibrary.reset(kind, params["id"], site, prefix)

          :accept_update ->
            SharedLibrary.accept_update(kind, params["id"], site, prefix, socket.assigns.current_user)

          :dismiss_update ->
            SharedLibrary.dismiss_update(kind, params["id"], site, prefix)
        end

      case result do
        :ok -> {:noreply, socket |> notify(gettext("Library override updated.")) |> refresh()}
        {:ok, _entry} -> {:noreply, socket |> notify(gettext("Library override updated.")) |> refresh()}
        error -> {:noreply, notify_error(socket, error_message(error))}
      end
    else
      error -> {:noreply, notify_error(socket, error_message(error))}
    end
  end

  defp update_access(socket, site, kind, ids) do
    case SharedLibrary.set_enabled(site, kind, ids) do
      :ok -> {:noreply, socket |> notify(gettext("Shared library access updated.")) |> refresh()}
      error -> {:noreply, notify_error(socket, error_message(error))}
    end
  end

  defp refresh(socket) do
    sites =
      if socket.assigns.global_manager? do
        Registry.list_sites()
      else
        case socket.assigns.current_site do
          nil -> []
          site -> [Registry.get_site(site.id)]
        end
      end

    selected_site = select_site(sites, socket.assigns[:selected_site_id])

    selected_environment =
      select_environment(selected_site, socket.assigns[:selected_environment_id])

    all_libraries = Map.new(@kinds, &{&1, SharedLibrary.list_shared(&1)})

    enabled =
      Map.new(@kinds, fn kind ->
        {kind, if(selected_site, do: SharedLibrary.enabled_ids(selected_site, kind), else: MapSet.new())}
      end)

    libraries =
      visible_libraries(
        all_libraries,
        enabled,
        selected_site,
        selected_environment,
        socket.assigns.global_manager?
      )

    usage =
      for kind <- @kinds,
          entry <- Map.fetch!(libraries, kind),
          into: %{},
          do: {{kind, entry.id}, usage_for_view(kind, entry.id, selected_site, socket.assigns.global_manager?)}

    {effective, diffs} = context_entries(libraries, selected_site, selected_environment)

    assign(socket,
      sites: sites,
      kinds: @kinds,
      can_customize?: selected_site && Access.can_manage?(socket.assigns.current_user, selected_site),
      selected_site: selected_site,
      selected_site_id: selected_site && selected_site.id,
      selected_environment: selected_environment,
      selected_environment_id: selected_environment && selected_environment.id,
      libraries: libraries,
      enabled: enabled,
      usage: usage,
      effective: effective,
      diffs: diffs
    )
  end

  defp visible_libraries(libraries, _enabled, _site, _environment, true), do: libraries
  defp visible_libraries(_libraries, _enabled, nil, _environment, false), do: empty_libraries()

  defp visible_libraries(libraries, enabled, site, environment, false) do
    prefix = environment && Tenant.prefix(site, environment)

    Map.new(@kinds, fn kind ->
      visible =
        Enum.filter(Map.fetch!(libraries, kind), fn entry ->
          MapSet.member?(Map.fetch!(enabled, kind), entry.id) or
            overridden_in_environment?(kind, entry.id, site, prefix)
        end)

      {kind, visible}
    end)
  end

  defp empty_libraries, do: Map.new(@kinds, &{&1, []})

  defp overridden_in_environment?(_kind, _id, _site, nil), do: false

  defp overridden_in_environment?(kind, id, site, prefix) do
    case SharedLibrary.get(kind, id, :shared, site, prefix) do
      nil -> false
      effective -> not is_nil(Map.get(effective, source_field(kind)))
    end
  end

  defp usage_for_view(kind, id, _site, true), do: SharedLibrary.usage(kind, id)

  defp usage_for_view(kind, id, site, false) do
    kind
    |> SharedLibrary.usage(id)
    |> Enum.filter(&(&1.site.id == site.id))
  end

  defp context_entries(_libraries, nil, _environment), do: {%{}, %{}}
  defp context_entries(_libraries, _site, nil), do: {%{}, %{}}

  defp context_entries(libraries, site, environment) do
    prefix = Tenant.prefix(site, environment)

    Enum.reduce(@kinds, {%{}, %{}}, fn kind, {effective_acc, diff_acc} ->
      Enum.reduce(Map.fetch!(libraries, kind), {effective_acc, diff_acc}, fn entry, {entries, diffs} ->
        effective = SharedLibrary.get(kind, entry.id, :shared, site, prefix)
        entries = Map.put(entries, {kind, entry.id}, effective)

        diffs =
          case SharedLibrary.diff(kind, entry.id, site, prefix) do
            {:ok, diff} -> Map.put(diffs, {kind, entry.id}, diff)
            {:error, :not_found} -> diffs
          end

        {entries, diffs}
      end)
    end)
  end

  defp select_site([], _selected_id), do: nil
  defp select_site(sites, selected_id), do: Enum.find(sites, hd(sites), &(&1.id == selected_id))

  defp select_environment(nil, _selected_id), do: nil
  defp select_environment(%{environments: []}, _selected_id), do: nil

  defp select_environment(site, selected_id) do
    Enum.find(site.environments, Enum.find(site.environments, hd(site.environments), & &1.live), fn environment ->
      environment.id == selected_id
    end)
  end

  defp entry_attrs(:module, params) do
    {:ok,
     params
     |> Map.take(["name", "namespace", "code", "version_note"])
     |> Map.put_new("help_text", "Shared module")
     |> Map.put_new("class", "module")}
  end

  defp entry_attrs(:container, params) do
    {:ok, Map.take(params, ["name", "namespace", "code", "type", "version_note"])}
  end

  defp entry_attrs(:palette, params) do
    with {:ok, colors} <- Jason.decode(params["colors_json"] || "[]") do
      {:ok,
       params
       |> Map.take(["name", "namespace", "key", "version_note"])
       |> Map.put("status", "published")
       |> Map.put("colors", colors)}
    else
      _error -> {:error, :invalid_colors_json}
    end
  end

  defp parse_kind(kind) when kind in ["module", "container", "palette"],
    do: {:ok, String.to_existing_atom(kind)}

  defp parse_kind(kind) when kind in @kinds, do: {:ok, kind}
  defp parse_kind(_kind), do: {:error, :invalid_library_kind}

  defp parse_id!(id) when is_integer(id), do: id
  defp parse_id!(id), do: String.to_integer(id)

  defp enabled?(enabled, kind, id), do: enabled |> Map.fetch!(kind) |> MapSet.member?(id)

  defp authorize_customize(%{assigns: %{can_customize?: true}}), do: :ok
  defp authorize_customize(_socket), do: {:error, :not_authorized}

  defp source_field(:module), do: :source_module_id
  defp source_field(:container), do: :source_container_id
  defp source_field(:palette), do: :source_palette_id

  defp override_route(kind, effective, site, environment) do
    base =
      case kind do
        :module -> "/admin/config/content/modules/update/#{effective.override_id}"
        :container -> "/admin/config/content/containers/update/#{effective.override_id}"
        :palette -> "/admin/config/content/palettes/update/#{effective.override_id}"
      end

    query = URI.encode_query(%{"brando_site_key" => site.key, "brando_environment_key" => environment.key})
    "#{base}?#{query}"
  end

  defp kind_title(:module), do: gettext("Modules")
  defp kind_title(:container), do: gettext("Containers")
  defp kind_title(:palette), do: gettext("Palettes")
  defp kind_singular(kind), do: kind |> to_string() |> String.replace("_", " ")

  defp kind_description(:module), do: gettext("Templates, variables, and references used by content blocks.")
  defp kind_description(:container), do: gettext("Shared wrappers for groups of blocks.")
  defp kind_description(:palette), do: gettext("Shared color systems for container blocks.")

  defp entry_label(%{name: name}) when is_map(name) do
    Map.get(name, Gettext.get_locale(Brando.Gettext)) || name |> Map.values() |> List.first() || "—"
  end

  defp entry_label(%{name: name}), do: name || "—"

  defp default_code(:module), do: "<section>{{ content }}</section>"
  defp default_code(:container), do: "<section>{{ content }}</section>"

  defp colors_json(%{colors: colors}) do
    colors
    |> Enum.map(fn color ->
      color
      |> Map.from_struct()
      |> Map.take([:name, :key, :hex_value, :instructions])
    end)
    |> Jason.encode!()
  end

  defp format_value(value) do
    value
    |> inspect(limit: 10, printable_limit: 160)
    |> String.slice(0, 240)
  end

  defp notify(socket, message) do
    send(self(), {:toast, message})
    socket
  end

  defp notify_error(socket, message) do
    BrandoAdmin.Toast.send_to(socket.assigns.current_user, message, %{level: :error, type: :notification})
    socket
  end

  defp error_message({:error, reason}), do: error_message(reason)

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
    |> Enum.join(", ")
  end

  defp error_message({:shared_item_in_use, usages}) do
    names = usages |> Enum.map(& &1.site.name) |> Enum.uniq() |> Enum.join(", ")
    gettext("This entry is still enabled, customized, or referenced by: %{sites}", sites: names)
  end

  defp error_message(reason) when is_atom(reason), do: reason |> Atom.to_string() |> String.replace("_", " ")
  defp error_message(reason), do: inspect(reason)
end
