defmodule BrandoAdmin.FrontendEdit.EditorLive do
  @moduledoc """
  The sidebar of frontend edit mode: one block or one field of an entry,
  opened from the published page (`priv/static/js/frontend_edit.js`) in an
  iframe.

  Mounted with the uid of a clicked block (`?uid=`) or the key of a clicked
  entry field (`?field=`, see `Brando.FrontendEdit.Fields`). It resolves what
  to edit and its entry (`Brando.FrontendEdit.Targets`), runs the same form
  hooks an entry's admin form does, and renders the entry form narrowed to
  it (`BrandoAdmin.Components.Form.FrontendEditor`).

  Selecting something else of the same entry moves the focus; something of
  another entry remounts the view for that entry. Preview HTML and editor state go
  to the page through the `Brando.FrontendEditBridge` hook.

  The editor is present at the entry's admin URL, marked as a frontend
  session, so the admin form and the sidebar each show who else is editing.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.FrontendEdit
  alias Brando.FrontendEdit.Manifest
  alias Brando.FrontendEdit.Targets
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.LiveView.Form.Compiler

  @doc false
  # Entry-level authorization is checked on mount (the entry is only known
  # from the block) and again by the context when saving.
  def __authorization__, do: {:access, :backend}

  @impl true
  def mount(params, session, socket) do
    socket =
      socket
      |> assign(:socket_connected, connected?(socket))
      |> assign(:dirty?, false)
      |> assign(:saved?, false)
      |> assign(:stale, nil)
      |> assign(:save_error, nil)
      |> assign(:expect_own_mutation, false)
      |> assign(:presences, %{})

    case resolve(target(params), socket.assigns.current_user) do
      {:ok, resolved} ->
        {:ok, socket |> assign_resolved(resolved) |> setup(session), layout: {BrandoAdmin.Layouts, :frontend_edit}}

      {:error, reason} ->
        {:ok, assign(socket, unavailable: reason, page_title: gettext("Edit block")),
         layout: {BrandoAdmin.Layouts, :frontend_edit}}
    end
  end

  defp target(%{"field" => key}) when is_binary(key), do: {:field, key}
  defp target(%{"uid" => uid}) when is_binary(uid), do: {:block, uid}
  defp target(_params), do: nil

  defp resolve(target, user) do
    with {:enabled, true} <- {:enabled, FrontendEdit.enabled?()},
         {:ok, resolved} <- resolve_target(target),
         true <- Manifest.editable?(resolved.owner, user) || {:error, :forbidden} do
      {:ok, resolved}
    else
      {:enabled, false} -> {:error, :disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_target({:block, uid}) do
    with {:ok, resolved} <- Targets.resolve(uid) do
      {_schema, _id, field} = resolved.owner

      {:ok,
       %{
         owner: resolved.owner,
         focus: %{target: resolved.target.uid, root: resolved.root.uid, path: resolved.path, field: field},
         title:
           Manifest.labels([resolved.target]) |> Map.get(resolved.target.uid) || block_type_label(resolved.target.type)
       }}
    end
  end

  defp resolve_target({:field, key}) do
    case FrontendEdit.Fields.parse_key(key) do
      {:ok, {schema, _id, field} = owner} ->
        {:ok,
         %{owner: owner, focus: %{target: key, input: field, field: nil}, title: FrontendEdit.Fields.label(schema, field)}}

      :error ->
        {:error, :not_found}
    end
  end

  defp resolve_target(nil), do: {:error, :not_found}

  defp assign_resolved(socket, resolved) do
    {schema, id, _field} = resolved.owner

    socket
    |> assign(:unavailable, nil)
    |> assign(:schema, schema)
    # The id the entry's own admin form has: asset delivery and image inputs
    # find the form by it.
    |> assign(:form_id, "#{schema.__naming__().singular}_form")
    |> assign(:owner, resolved.owner)
    |> assign(:focus, resolved.focus)
    |> assign(:title, resolved.title)
    # Present at the entry's admin form, as someone editing from the website.
    |> assign(:presence_path, schema.__admin_route__(:update, [id]))
    |> assign(:presence_meta, %{frontend: true})
  end

  # The hooks an entry's admin form runs, for the schema found on mount.
  defp setup(socket, session) do
    {schema, id, _field} = socket.assigns.owner

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.scoped("brando:mutations:#{inspect(schema)}"))
    end

    socket =
      socket
      |> assign_entry_details()
      |> assign(:last_mutation, nil)
      |> attach_hook(:frontend_edit_mutations, :handle_info, &mutation_hook/2)

    params = %{"entry_id" => to_string(id)}

    Enum.reduce_while(Compiler.hooks(), socket, fn hook, socket ->
      BrandoAdmin.LiveView.Form.on_mount({hook, schema}, params, session, socket)
    end)
  end

  defp assign_entry_details(socket) do
    {schema, id, _field} = socket.assigns.owner
    entry = Brando.Repo.get(schema, id)
    shared? = schema == Brando.Pages.Fragment

    socket
    |> assign(:kind, Brando.Blueprint.get_singular(schema))
    |> assign(:entry_title, entry && Manifest.title(schema, entry))
    |> assign(:shared?, shared?)
    |> assign(:usage, if(shared?, do: Manifest.fragment_usage(id), else: 0))
    |> assign(:scheduled?, FrontendEdit.scheduled_revision?(schema, id))
    |> assign(:admin_url, schema.__admin_route__(:update, [id]))
  end

  @impl true
  def handle_params(params, _uri, %{assigns: %{unavailable: nil, focus: %{target: current}}} = socket) do
    case target(params) do
      {_kind, value} = target when value != current ->
        # Something else. In this entry it moves the focus; in another entry
        # it needs a view set up for that entry.
        {schema, id, _field} = socket.assigns.owner

        case resolve(target, socket.assigns.current_user) do
          {:ok, %{owner: {^schema, ^id, _}} = resolved} ->
            {:noreply, socket |> assign_resolved(resolved) |> assign(:saved?, false)}

          _ ->
            {:noreply, push_navigate(socket, to: editor_path(target))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select", %{"uid" => uid}, socket) when is_binary(uid) do
    {:noreply, push_patch(socket, to: editor_path({:block, uid}))}
  end

  def handle_event("select", %{"field" => key}, socket) when is_binary(key) do
    {:noreply, push_patch(socket, to: editor_path({:field, key}))}
  end

  # The page reloads to drop this editor's changes and fetch someone else's,
  # then opens the block again.
  def handle_event("reload", _params, socket) do
    {:noreply, bridge(socket, :reload)}
  end

  @impl true
  def handle_info({:frontend_edit, message}, socket), do: {:noreply, frontend_edit(message, socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp frontend_edit({:update_block, payload}, socket),
    do: push_event(socket, "b:frontend-edit", Map.put(payload, :type, "update_block"))

  defp frontend_edit({:replace_field, payload}, socket),
    do: push_event(socket, "b:frontend-edit", Map.put(payload, :type, "replace_field"))

  defp frontend_edit({:entry_field, payload}, socket),
    do: push_event(socket, "b:frontend-edit", Map.put(payload, :type, "entry_field"))

  defp frontend_edit(:dirty, %{assigns: %{dirty?: true}} = socket), do: socket

  defp frontend_edit(:dirty, socket) do
    socket
    |> assign(dirty?: true, saved?: false)
    |> push_event("b:frontend-edit", %{type: "dirty", dirty: true})
  end

  defp frontend_edit(:saving, socket), do: assign(socket, :expect_own_mutation, true)

  defp frontend_edit({:saved, _entry}, socket) do
    socket
    |> assign(dirty?: false, saved?: true, save_error: nil)
    |> push_event("b:frontend-edit", %{type: "saved"})
  end

  defp frontend_edit({:save_failed, reason}, socket) do
    socket
    |> assign(expect_own_mutation: false, save_error: hidden_errors(reason, socket.assigns.focus))
    |> push_event("b:frontend-edit", %{type: "save_failed"})
  end

  defp frontend_edit(_message, socket), do: socket

  # A save of this entry from anywhere else makes this editor's copy stale.
  # Our own save broadcasts too; the form says one is coming first.
  # The form's own listeners can subscribe to the same topic, so one save may
  # arrive more than once; it is told apart by the entry it saved.
  defp mutation_hook({:mutation, schema, %{id: id} = entry, action}, %{assigns: %{owner: {schema, id, _}}} = socket) do
    mutation = {action, Map.get(entry, :updated_at)}

    socket =
      cond do
        mutation == socket.assigns.last_mutation ->
          socket

        socket.assigns.expect_own_mutation ->
          assign(socket, expect_own_mutation: false, last_mutation: mutation)

        true ->
          assign(socket, stale: %{name: saved_by(schema, id), deleted?: action == :deleted}, last_mutation: mutation)
      end

    {:cont, socket}
  end

  defp mutation_hook(_message, socket), do: {:cont, socket}

  defp saved_by(schema, id) do
    case Brando.Activity.for_entry(schema, id, limit: 1) do
      [%{user: %{name: name}} | _] when is_binary(name) -> name
      _ -> gettext("Someone")
    end
  rescue
    _ -> gettext("Someone")
  end

  defp bridge(socket, :reload),
    do: push_event(socket, "b:frontend-edit", %{type: "reload", uid: socket.assigns.focus.target})

  defp editor_path({:block, uid}), do: Brando.Plug.FrontendEdit.editor_path() <> "?" <> URI.encode_query(%{"uid" => uid})

  defp editor_path({:field, key}),
    do: Brando.Plug.FrontendEdit.editor_path() <> "?" <> URI.encode_query(%{"field" => key})

  @impl true
  def render(%{unavailable: reason} = assigns) when not is_nil(reason) do
    ~H"""
    <div id="frontend-editor" class="frontend-editor is-unavailable" phx-hook="Brando.FrontendEditBridge">
      <header class="frontend-editor-header">
        <div class="frontend-editor-heading">
          <h1>{gettext("Edit block")}</h1>
        </div>
        <button type="button" class="frontend-editor-close" data-frontend-edit-close aria-label={gettext("Close editor")}>
          <.icon name="x" />
        </button>
      </header>
      <div class="frontend-editor-unavailable" role="alert">
        <.icon name="ban" />
        <p>
          <%= case @unavailable do %>
            <% :forbidden -> %>
              {gettext("You don’t have permission to edit this content.")}
            <% :disabled -> %>
              {gettext("Frontend editing is switched off for this site.")}
            <% _ -> %>
              {gettext("This block could not be found. It may have been deleted since the page was loaded.")}
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id="frontend-editor"
      class="frontend-editor"
      phx-hook="Brando.FrontendEditBridge"
      data-target={@focus.target}
      data-submit-id={"#{@form_id}-submit"}
    >
      <header class="frontend-editor-header">
        <div class="frontend-editor-heading">
          <p class="frontend-editor-eyebrow">
            <span>{@kind}</span>
            <span :if={@entry_title} class="frontend-editor-entry">{@entry_title}</span>
          </p>
          <h1>{@title}</h1>
        </div>
        <.link
          href={full_editor_url(@admin_url, @focus)}
          target="_blank"
          class="frontend-editor-open"
          data-tooltip={gettext("Open in the full editor")}
          aria-label={gettext("Open in the full editor")}
        >
          <.icon name="external-link" />
        </.link>
        <button type="button" class="frontend-editor-close" data-frontend-edit-close aria-label={gettext("Close editor")}>
          <.icon name="x" />
        </button>
      </header>

      <div class="frontend-editor-notices">
        <div :if={@stale} class="frontend-editor-notice is-error" role="alert" data-testid="frontend-edit-stale">
          <.icon name="triangle-alert" />
          <div>
            <p :if={!@stale.deleted?}>
              {gettext("%{name} saved this page after you opened it. Reload to get their changes before you save.",
                name: @stale.name
              )}
            </p>
            <p :if={@stale.deleted?}>{gettext("%{name} deleted this page.", name: @stale.name)}</p>
            <button :if={!@stale.deleted?} type="button" class="frontend-editor-notice-action" phx-click="reload">
              {gettext("Reload")}
            </button>
          </div>
        </div>

        <div
          :if={@save_error == :invalid}
          class="frontend-editor-notice is-error"
          role="alert"
          data-testid="frontend-edit-invalid"
        >
          <.icon name="triangle-alert" />
          <div>
            <p>{gettext("Not saved: the entry has errors in fields not shown here.")}</p>
            <.link href={@admin_url} target="_blank" class="frontend-editor-notice-action">
              {gettext("Fix them in the full editor")}
            </.link>
          </div>
        </div>

        <div
          :for={{_id, user} <- others(@presences, @current_user)}
          class="frontend-editor-notice is-presence"
          data-testid="frontend-edit-presence"
        >
          <div class="frontend-editor-avatar">
            <Content.user_avatar user={user} />
          </div>
          <p :if={user[:frontend?]}>
            {gettext("%{name} is also editing this page on the website", name: user.name)}
          </p>
          <p :if={!user[:frontend?]}>
            {gettext("%{name} has this page open in the admin", name: user.name)}
          </p>
        </div>

        <div :if={@shared?} class="frontend-editor-notice is-shared" data-testid="frontend-edit-shared">
          <.icon name="link" />
          <p>
            <strong>{gettext("Shared fragment.")}</strong>
            <%= if @usage > 0 do %>
              {ngettext(
                "Changes show everywhere it is used, including %{count} page.",
                "Changes show everywhere it is used, including %{count} pages.",
                @usage
              )}
            <% else %>
              {gettext("Changes show everywhere it is used.")}
            <% end %>
          </p>
        </div>

        <div :if={@scheduled?} class="frontend-editor-notice is-warning" data-testid="frontend-edit-scheduled">
          <.icon name="calendar-days" />
          <p>{gettext("A version of this page is scheduled to be published. It will replace changes made here.")}</p>
        </div>
      </div>

      <div :if={@socket_connected} class="frontend-editor-body">
        <.live_component
          module={Form}
          id={@form_id}
          entry_id={elem(@owner, 1)}
          current_user={@current_user}
          presences={@presences}
          schema={@schema}
          frontend_edit={@focus}
          frontend_status={%{dirty?: @dirty?, saved?: @saved?, stale: @stale}}
        >
          <:header>{@title}</:header>
        </.live_component>
      </div>
    </div>
    """
  end

  # Errors in fields the sidebar does not show need the full editor; the
  # field it shows has its error inline.
  defp hidden_errors({:invalid, fields}, focus) do
    if Enum.any?(fields, &(&1 != focus[:input])), do: :invalid
  end

  defp hidden_errors(_reason, _focus), do: nil

  # The full editor opens at the block, or at the field's tab.
  defp full_editor_url(admin_url, %{input: field}) when not is_nil(field), do: "#{admin_url}?field=#{field}"
  defp full_editor_url(admin_url, %{target: uid}), do: "#{admin_url}?block=#{uid}"

  defp others(presences, current_user) do
    presences
    |> Enum.reject(fn {id, _} -> id == current_user.id end)
    |> Enum.sort_by(fn {_, user} -> user.name end)
  end

  defp block_type_label(:container), do: gettext("Container")
  defp block_type_label(:fragment), do: gettext("Fragment")
  defp block_type_label(_), do: gettext("Block")
end
