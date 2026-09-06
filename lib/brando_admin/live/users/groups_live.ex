defmodule BrandoAdmin.Users.GroupsLive do
  use BrandoAdmin, :live_view
  alias Brando.Authorization.{Catalog, Engine, Group, Groups, Scope}

  def mount(_params, _session, socket) do
    if Engine.enabled?() do
      scope = socket.assigns.authorization_scope
      catalog = Enum.filter(Catalog.all(), &(scope.kind in &1.scopes))

      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:catalog, catalog)
       |> assign(:installation_access?, Engine.can?(Scope.installation(socket.assigns.current_user), :read, :groups))
       |> assign(:search, "")
       |> assign(:group_search, "")
       |> assign(:selected, nil)
       |> assign(:draft, %{})
       |> assign(:permissions, MapSet.new())
       |> assign(:people_search, "")
       |> assign(:preview, nil)
       |> assign(:effective, nil)
       |> assign(:message, nil)
       |> assign(:error, nil)
       |> assign(:tab, "permissions")
       |> assign(:tabs, [{"permissions", "Permissions"}, {"members", "Members"}, {"activity", "Activity"}])
       |> assign(:stale?, false)
       |> assign(:adding_member?, false)
       |> assign(:effective_person, nil)
       |> refresh()
       |> select_initial()}
    else
      {:ok, redirect(socket, to: "/admin")}
    end
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:dirty?, dirty?(assigns.selected, assigns.draft, assigns.permissions))
      |> assign(:sections, permission_sections(assigns.catalog, assigns.search))

    ~H"""
    <div
      class="authorization-workspace"
      id="authorization-workspace"
      phx-hook="Brando.Authorization"
      data-dirty={to_string(@dirty?)}
    >
      <header class="authorization-page-heading">
        <div>
          <h1>Permissions</h1><p>Manage your team’s access with groups.</p>
        </div>
        <div class="authorization-scope">
          <span>Managing access for</span><strong>{scope_label(@authorization_scope, @current_site)}</strong>
          <a
            :if={@installation_access? && @authorization_scope.kind != :installation}
            href="/admin/groups?scope=installation"
          >Installation groups →</a>
          <a :if={@authorization_scope.kind == :installation} href="/admin/groups">Workspace groups →</a>
        </div>
      </header>
      <div class="authorization-layout">
        <aside class="authorization-groups" aria-label="User groups">
          <div class="authorization-heading">
            <h2>
              Groups
              <.count_badge>{length(@groups)}</.count_badge>
            </h2>
            <button
              :if={Engine.can?(@authorization, :create, :groups)}
              type="button"
              class="access-button pastel-action"
              phx-click="new"
              data-confirm={discard_confirmation(@selected, @draft, @permissions)}
            >New group</button>
          </div>
          <form id="authorization-group-search" phx-change="search_groups">
            <input
              name="search"
              type="search"
              value={@group_search}
              phx-debounce="150"
              aria-label="Find a group"
              placeholder="Find a group…"
            />
          </form>
          <nav class="authorization-group-list" aria-label="Choose a group">
            <button
              :for={group <- filter_groups(@groups, @group_search)}
              type="button"
              phx-click="select"
              phx-value-id={group.id}
              data-confirm={
                if !@selected || @selected.id != group.id, do: discard_confirmation(@selected, @draft, @permissions)
              }
              class={if @selected && @selected.id == group.id, do: "selected"}
              aria-current={@selected && @selected.id == group.id && "true"}
            >
              <span><strong>{group.name}</strong><small class="authorization-member-count"><.count_badge tone="mint">
                {length(group.memberships)}
              </.count_badge>
              {plural_label(length(group.memberships), "member")}</small></span>
              <span :if={group.preset == :superuser} class="access-tag">Protected</span>
            </button>
          </nav>
          <p :if={filter_groups(@groups, @group_search) == []} class="authorization-hint">No matching groups.</p>
          <p class="authorization-hint">A person can belong to several groups. Their permissions add together.</p>
        </aside>
        <section class="authorization-editor" aria-label="Group details">
          <%= if @selected do %>
            <%= if @preview do %>
              <section class="authorization-review" aria-label="Review permission changes">
                <button type="button" class="access-button quiet" phx-click="cancel_review">← Back to editing</button>
                <h2
                  id="authorization-review-title"
                  data-access-return="#authorization-review-button"
                  tabindex="-1"
                  data-access-focus
                >
                  Review changes
                </h2>
                <p class="authorization-lead">
                  {if @selected.id, do: "Update", else: "Create"} <strong>{@draft["name"]}</strong>.
                </p>
                <dl class="authorization-review-details">
                  <div :if={normalize(@selected.name) != normalize(@draft["name"])}>
                    <dt>Group name</dt><dd><s :if={@selected.name}>{@selected.name}</s> {@draft["name"]}</dd>
                  </div>
                  <div :if={normalize(@selected.description) != normalize(@draft["description"])}>
                    <dt>Description</dt><dd>{@draft["description"] |> normalize() |> empty_label()}</dd>
                  </div>
                </dl>
                <div class="authorization-diff">
                  <section>
                    <h3>
                      <.count_badge tone="mint">{length(@preview.added)}</.count_badge>
                      {plural_label(length(@preview.added), "permission")} added
                    </h3>
                    <p :if={@preview.added == []} class="authorization-hint">No new permissions.</p>
                    <ul>
                      <li :for={key <- @preview.added}>{permission_label(@catalog, key)}</li>
                    </ul>
                  </section>
                  <section>
                    <h3>
                      <.count_badge tone="peach">{length(@preview.removed)}</.count_badge>
                      {plural_label(length(@preview.removed), "permission")} removed
                    </h3>
                    <p :if={@preview.removed == []} class="authorization-hint">No permissions removed.</p>
                    <ul>
                      <li :for={key <- @preview.removed}>{permission_label(@catalog, key)}</li>
                    </ul>
                  </section>
                </div>
                <p class="authorization-impact">
                  <strong><.count_badge tone="mint">{@preview.members}</.count_badge>
                  {plural_label(@preview.members, "member")} affected.</strong>
                  Changes apply immediately. Permissions from other groups are retained.
                </p>
                <p :if={"brando.admin.access" in @preview.removed} class="authorization-notice">
                  Members who receive backend access only from this group will no longer be able to sign in to the admin.
                </p>
                <p :if={@error} class="authorization-notice error" role="alert">{@error}</p>
                <div class="authorization-review-actions">
                  <button type="button" class="access-button primary-action" phx-click="save" phx-disable-with="Saving…">Confirm &amp; save</button>

                  <button
                    :if={@stale?}
                    type="button"
                    class="access-button"
                    phx-click="reload"
                    data-confirm="Discard your draft and load the latest saved version?"
                  >Load latest version</button>
                </div>
              </section>
            <% else %>
              <header class="authorization-editor-heading">
                <div>
                  <div class="authorization-group-kind">
                    {if @selected.preset, do: "Built-in group", else: "Custom group"}<span
                      :if={@dirty?}
                      class="authorization-unsaved"
                    >Unsaved changes</span>
                  </div>
                  <h2>{if @selected.id, do: @selected.name, else: "New group"}</h2>
                  <p :if={@message} class="authorization-feedback" role="status">{@message}</p>
                </div>
                <button
                  :if={@selected.preset != :superuser && can_save?(@authorization, @selected)}
                  type="submit"
                  form="group-permissions"
                  id="authorization-review-button"
                  class="access-button primary-action"
                  disabled={!@dirty?}
                  phx-disable-with="Preparing review…"
                >Review changes</button>
              </header>
              <p :if={@error} class="authorization-notice error" role="alert">{@error}</p>
              <div class="authorization-tabs module-editor-tabs" role="group" aria-label="Group sections">
                <button
                  :for={{key, label} <- @tabs}
                  type="button"
                  phx-click="tab"
                  phx-value-tab={key}
                  class={["module-editor-tab", @tab == key && "is-active"]}
                  aria-pressed={@tab == key}
                  disabled={!@selected.id && key != "permissions"}
                >{label}
                <.count_badge :if={key == "members"} tone="mint">{length(@members)}</.count_badge></button>
              </div>
              <div hidden={@tab != "permissions"}>
                <%= if @selected.preset == :superuser do %>
                  <div class="authorization-protected">
                    <span class="access-tag">Protected</span><h3>Full installation access</h3>
                    <p>
                      Superusers can manage every active site and all installation settings. These permissions are maintained automatically.
                    </p>
                    <p>Manage who has this access in Members. At least one active superuser must remain.</p>
                  </div>
                <% else %>
                  <form id="group-permissions" phx-change="change" phx-submit="review">
                    <fieldset class="authorization-fields" disabled={!can_save?(@authorization, @selected)}>
                      <label>Group name<input
                        name="group[name]"
                        value={@draft["name"]}
                        required
                        maxlength="100"
                        phx-debounce="250"
                      /></label>
                      <label>Description
                      <span>Optional</span><input
                        name="group[description]"
                        aria-label="Description"
                        value={@draft["description"]}
                        maxlength="500"
                        phx-debounce="250"
                        placeholder="What is this group for?"
                      /></label>
                    </fieldset>
                    <div class="authorization-permission-heading">
                      <h3>
                        Permissions
                        <span class="authorization-selected-count"><.count_badge>{MapSet.size(@permissions)}</.count_badge>
                        selected</span>
                      </h3>
                    </div>
                    <div class="authorization-filter">
                      <input
                        type="search"
                        name="search"
                        value={@search}
                        aria-label="Find a permission"
                        phx-debounce="150"
                        placeholder="Find a resource or action…"
                      />
                      <span>Only checked permissions are granted.</span>
                    </div>
                    <p :if={!@authorization.superuser? && can_save?(@authorization, @selected)} class="authorization-hint">
                      You can grant permissions you hold in this scope. Unavailable permissions are locked.
                    </p>
                    <div :if={retired_permissions(@catalog, @permissions) != []} class="authorization-notice">
                      <strong>Retired permissions</strong><p>
                        These permissions are no longer registered and grant no access.
                      </p>
                      <p :for={key <- retired_permissions(@catalog, @permissions)}>{key}</p>
                      <button :if={@authorization.superuser?} type="button" class="access-button" phx-click="remove_retired">Remove retired permissions</button>
                    </div>
                    <div class="authorization-permissions">
                      <.permission_section
                        :for={{section, resources} <- @sections}
                        section={section}
                        resources={resources}
                        permissions={@permissions}
                        authorization={@authorization}
                        selected={@selected}
                        search={@search}
                      />
                    </div>
                    <div :if={@sections == []} class="authorization-empty compact">
                      <h3>No matching permissions</h3><p>
                        Try a resource name, such as Pages, or an action, such as Publish.
                      </p>
                    </div>
                    <p
                      :if={!MapSet.member?(@permissions, "brando.admin.access")}
                      class="authorization-hint authorization-backend-hint"
                    >
                      Backend access is not selected. Members need it from another group to use the admin.
                    </p>
                  </form>
                  <footer class="authorization-editor-footer">
                    <div>
                      <button
                        :if={@selected.id && Engine.can?(@authorization, :create, :groups)}
                        type="button"
                        class="access-button quiet"
                        phx-click="clone"
                        data-confirm={discard_confirmation(@selected, @draft, @permissions)}
                      >Duplicate group</button>
                      <button
                        :if={@dirty?}
                        type="button"
                        class="access-button quiet"
                        phx-click="discard"
                        data-confirm="Discard your unsaved group changes?"
                      >Discard changes</button>
                    </div>
                    <button
                      :if={@selected.id && is_nil(@selected.preset) && Engine.can?(@authorization, :delete, :groups)}
                      type="button"
                      class="access-button quiet destructive"
                      phx-click="delete"
                      data-confirm={"Delete #{@selected.name}? #{count_label(length(@selected.memberships), "member")} will lose the permissions granted by this group."}
                    >Delete group</button>
                  </footer>
                <% end %>
              </div>
              <div :if={@tab == "members"} class="authorization-members">
                <%= if @effective do %>
                  <section class="authorization-effective">
                    <button type="button" class="access-button quiet" phx-click="close_effective">← All members</button>
                    <h3
                      id="authorization-effective-title"
                      data-access-return={"#member-access-#{@effective_person.id}"}
                      tabindex="-1"
                      data-access-focus
                    >
                      {@effective_person.name}
                    </h3>
                    <p class="authorization-lead">Combined access .</p>
                    <%= if Enum.any?(@effective, & &1.explanation.superuser?) do %>
                      <div class="authorization-protected">
                        <span class="access-tag">Superuser</span><h3>Full access</h3><p>
                          Protected Superuser access covers this scope. Individual content policies still apply.
                        </p>
                      </div>
                    <% else %>
                      <p :if={!Enum.any?(@effective, & &1.explanation.allowed?)} class="authorization-notice">
                        No effective permissions in this scope. Check that the account is active and has backend access.
                      </p>
                      <div
                        :for={
                          {section, resources} <- permission_sections(Enum.filter(@effective, & &1.explanation.allowed?), "")
                        }
                        class="authorization-access-section"
                      >
                        <h4>{section}</h4><dl>
                          <div :for={{_, permissions} <- resources}>
                            <dt>{hd(permissions).label}</dt><dd>
                              {Enum.map_join(permissions, ", ", &action_label(&1.action))}<small>From {permissions
                              |> Enum.flat_map(& &1.explanation.groups)
                              |> Enum.uniq_by(& &1.id)
                              |> Enum.map_join(", ", & &1.name)}</small>
                            </dd>
                          </div>
                        </dl>
                      </div>
                    <% end %>
                  </section>
                <% else %>
                  <div class="authorization-section-heading">
                    <div>
                      <h3>Group members</h3><p>Membership changes take effect immediately.</p>
                    </div>
                    <button
                      :if={Engine.can?(@authorization, :assign, :groups) && !@adding_member?}
                      type="button"
                      class="access-button"
                      phx-click="show_add_member"
                    >Add member</button>
                  </div>
                  <section :if={@adding_member?} class="authorization-member-picker" aria-label="Add a member">
                    <div class="authorization-heading">
                      <h4>Add a member</h4><button type="button" class="access-button quiet" phx-click="cancel_add_member">Cancel</button>
                    </div>
                    <form id="group-people-search" phx-change="search_people">
                      <input
                        type="search"
                        name="search"
                        value={@people_search}
                        aria-label="Find a person"
                        phx-debounce="200"
                        placeholder="Search people by name…"
                      />
                    </form>
                    <p class="authorization-hint">Choose an existing person with access to this workspace.</p>
                    <div class="authorization-picker-results">
                      <div :for={person <- available_people(@directory, @members)}>
                        <span>{person.name}</span><button
                          type="button"
                          class="access-button"
                          phx-click="add_member"
                          phx-value-user_id={person.id}
                          aria-label={"Add #{person.name}"}
                          phx-disable-with="Adding…"
                        >Add<span class="access-sr-only">{person.name}</span></button>
                      </div>
                      <p :if={available_people(@directory, @members) == []} class="authorization-hint">
                        No available people match. Existing members are excluded.
                      </p>
                    </div>
                  </section>
                  <div :if={@members == []} class="authorization-empty">
                    <h3>No members yet</h3><p>Add someone to give them this group’s permissions.</p>
                  </div>
                  <div :for={person <- @members} class="authorization-person">
                    <span class="authorization-avatar" aria-hidden="true">{initials(person.name)}</span>
                    <div><strong>{person.name}</strong><small :if={!person.active}>Disabled account</small></div>
                    <button
                      type="button"
                      class="access-button quiet"
                      phx-click="effective"
                      id={"member-access-#{person.id}"}
                      phx-value-id={person.id}
                    >View access</button>
                    <button
                      :if={Engine.can?(@authorization, :assign, :groups)}
                      type="button"
                      class="access-button quiet"
                      phx-click="remove_member"
                      phx-value-id={person.id}
                      data-confirm={"Remove #{person.name} from #{@selected.name}? Permissions from other groups will be retained."}
                    >Remove</button>
                  </div>
                <% end %>
              </div>
              <div :if={@tab == "activity"} class="authorization-activity">
                <div class="authorization-section-heading">
                  <div>
                    <h3>Recent activity</h3><p>The latest 20 changes to this group.</p>
                  </div>
                </div>
                <div :if={@history == []} class="authorization-empty">
                  <h3>No recorded changes</h3><p>Changes to permissions and membership will appear here.</p>
                </div>
                <article :for={event <- @history}>
                  <div>
                    <strong>{event.action |> String.replace(".", " ") |> String.capitalize()}</strong><small>{event.actor_name ||
                      "Deleted account"}<span :if={event.subject_user_id}> · {event.subject_name || "Deleted member"}</span></small>
                  </div>
                  <time datetime={DateTime.to_iso8601(event.inserted_at)}>{Calendar.strftime(
                    event.inserted_at,
                    "%d %b %Y · %H:%M UTC"
                  )}</time>
                </article>
              </div>
            <% end %>
          <% else %>
            <div class="authorization-empty">
              <h2>Choose a group</h2><p>Review its permissions and members, or create a group for your team.</p>
            </div>
          <% end %>
        </section>
      </div>
    </div>
    """
  end

  attr :tone, :string, default: "blue", values: ["blue", "mint", "peach"]
  slot :inner_block, required: true

  defp count_badge(assigns) do
    ~H"""
    <span class={["access-count-badge", "access-count-#{@tone}"]}>{render_slot(@inner_block)}</span>
    """
  end

  defp permission_section(assigns) do
    assigns =
      assigns
      |> assign(:actions, section_actions(assigns.resources))
      |> assign(:total, Enum.reduce(assigns.resources, 0, fn {_, permissions}, n -> n + length(permissions) end))

    ~H"""
    <details
      id={"permissions-section-#{@section}"}
      class="authorization-permission-section"
      open={@search != "" || @section in ["Workspace", "Content"]}
    >
      <summary>
        <span>{@section}</span><small class="authorization-selected-count"><.count_badge>
          {selected_count(@resources, @permissions)} / {@total}
        </.count_badge>
        selected</small>
      </summary>
      <div class="authorization-table-scroll" tabindex="0" role="region" aria-label={"#{@section} permissions"}>
        <table class="authorization-matrix">
          <thead>
            <tr>
              <th scope="col">Resource</th><th :for={action <- @actions} scope="col">{action_label(action)}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{resource, permissions} <- @resources}>
              <th scope="row">
                <.row_toggle
                  resource={resource}
                  row_permissions={permissions}
                  permissions={@permissions}
                  authorization={@authorization}
                  selected={@selected}
                />
              </th>
              <td :for={action <- @actions}>
                <%= if permission = Enum.find(permissions, &(&1.action == action)) do %>
                  <label class="authorization-cell" title={permission_hint(@authorization, @selected, permission)}>
                    <input
                      type="checkbox"
                      name={"permissions[#{permission.key}]"}
                      value="true"
                      aria-label={"#{permission.label}: #{action_label(action)}"}
                      checked={MapSet.member?(@permissions, permission.key)}
                      disabled={!editable_permission?(@authorization, @selected, permission)}
                    />
                    <span class="access-mobile-label">{action_label(action)}</span>
                  </label>
                <% else %>
                  <span
                    class="authorization-unavailable"
                    aria-label={"#{action_label(action)} is not available for #{hd(permissions).label}"}
                  >—</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </details>
    """
  end

  defp row_toggle(assigns) do
    keys = editable_keys(assigns.authorization, assigns.selected, assigns.row_permissions)
    display_keys = if MapSet.size(keys) == 0, do: MapSet.new(assigns.row_permissions, & &1.key), else: keys

    assigns =
      assigns
      |> assign(:disabled?, MapSet.size(keys) == 0)
      |> assign(:state, selection_state(display_keys, assigns.permissions))
      |> assign(:label, hd(assigns.row_permissions).label)

    ~H"""
    <button
      type="button"
      role="checkbox"
      class="authorization-row-toggle"
      aria-label={"All permissions for #{@label}"}
      aria-checked={@state}
      disabled={@disabled?}
      title={
        if @disabled?,
          do: "You cannot change permissions in this row.",
          else:
            "Select or clear all permissions you can change in this row. Search limits the selection to visible permissions."
      }
      phx-click="toggle_resource"
      phx-value-resource={@resource}
    >
      <span class="authorization-row-check" aria-hidden="true">
        <svg :if={@state == "true"} viewBox="0 0 16 16"><path d="m3 8 3 3 7-7" /></svg>
        <svg :if={@state == "mixed"} viewBox="0 0 16 16"><path d="M3 8h10" /></svg>
      </span><span>{@label}</span>
    </button>
    """
  end

  def handle_event("toggle_resource", %{"resource" => resource}, %{assigns: %{selected: %Group{}}} = socket) do
    a = socket.assigns

    row =
      permission_sections(a.catalog, a.search)
      |> Enum.flat_map(fn {_, rows} -> rows end)
      |> Enum.find_value([], fn {key, permissions} -> if key == resource, do: permissions end)

    keys = editable_keys(a.authorization, a.selected, row)

    permissions =
      if MapSet.subset?(keys, a.permissions),
        do: MapSet.difference(a.permissions, keys),
        else: MapSet.union(a.permissions, keys)

    {:noreply,
     socket |> assign(:permissions, permissions) |> assign(:preview, nil) |> assign(:message, nil) |> assign(:error, nil)}
  end

  def handle_event("toggle_resource", _, socket), do: {:noreply, socket}

  def handle_event("select", %{"id" => id}, socket) do
    case Groups.get(socket.assigns.authorization_scope, id) do
      {:ok, group} ->
        if socket.assigns.selected && socket.assigns.selected.id == group.id,
          do: {:noreply, socket},
          else: {:noreply, select(socket, group)}

      error ->
        {:noreply, failure(socket, error)}
    end
  end

  def handle_event("reload", _, socket) do
    case Groups.get(socket.assigns.authorization_scope, socket.assigns.selected.id) do
      {:ok, group} -> {:noreply, select(socket, group)}
      error -> {:noreply, failure(socket, error)}
    end
  end

  def handle_event("discard", _, socket), do: {:noreply, select(socket, socket.assigns.selected)}
  def handle_event("show_add_member", _, socket), do: {:noreply, assign(socket, :adding_member?, true)}
  def handle_event("cancel_add_member", _, socket), do: {:noreply, assign(socket, :adding_member?, false)}

  def handle_event("new", _, socket),
    do: {:noreply, socket |> select(%Group{grants: [], memberships: []}) |> assign(:tab, "permissions")}

  def handle_event("clone", _, socket) do
    group = socket.assigns.selected

    {:noreply,
     socket
     |> select(%Group{name: "#{group.name} copy", description: group.description, grants: group.grants, memberships: []})
     |> assign(:tab, "permissions")}
  end

  def handle_event("search_groups", %{"search" => search}, socket), do: {:noreply, assign(socket, :group_search, search)}

  def handle_event("search_people", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:people_search, search)
     |> assign(:directory, result_list(Groups.directory(socket.assigns.authorization_scope, search)))}
  end

  def handle_event("remove_retired", _, socket) do
    if socket.assigns.authorization.superuser? do
      retired = MapSet.new(retired_permissions(socket.assigns.catalog, socket.assigns.permissions))

      {:noreply,
       socket |> assign(:permissions, MapSet.difference(socket.assigns.permissions, retired)) |> assign(:preview, nil)}
    else
      {:noreply, failure(socket, {:error, :forbidden})}
    end
  end

  def handle_event("change", params, socket) do
    # Keep hidden/search-filtered and non-editable grants intact. Only visible,
    # editable checkboxes participate in this form event.
    visible =
      permission_sections(socket.assigns.catalog, socket.assigns.search)
      |> Enum.flat_map(fn {_, rows} -> Enum.flat_map(rows, &elem(&1, 1)) end)
      |> Enum.filter(&editable_permission?(socket.assigns.authorization, socket.assigns.selected, &1))
      |> Enum.map(& &1.key)
      |> MapSet.new()

    submitted = params |> Map.get("permissions", %{}) |> Map.keys() |> MapSet.new()

    permissions =
      socket.assigns.permissions |> MapSet.difference(visible) |> MapSet.union(MapSet.intersection(submitted, visible))

    {:noreply,
     socket
     |> assign(:message, nil)
     |> assign(:error, nil)
     |> assign(:draft, params["group"] || socket.assigns.draft)
     |> assign(:permissions, permissions)
     |> assign(:search, params["search"] || "")
     |> assign(:preview, nil)}
  end

  def handle_event("review", params, socket) do
    # Submit is authoritative even when a debounced field change is still pending.
    {:noreply, socket} =
      if Map.has_key?(params, "group"), do: handle_event("change", params, socket), else: {:noreply, socket}

    a = socket.assigns
    changeset = Group.changeset(a.selected, a.draft)

    if changeset.valid? && dirty?(a.selected, a.draft, a.permissions) do
      group = if a.selected.id, do: a.selected, else: %{a.selected | grants: []}
      {:noreply, socket |> assign(:preview, Groups.changes(group, Enum.sort(a.permissions))) |> assign(:error, nil)}
    else
      {:noreply, if(changeset.valid?, do: socket, else: failure(socket, {:error, changeset}))}
    end
  end

  def handle_event("cancel_review", _, socket), do: {:noreply, assign(socket, :preview, nil)}
  def handle_event("save", _, %{assigns: %{preview: nil}} = socket), do: {:noreply, socket}

  def handle_event("save", _, socket) do
    a = socket.assigns
    keys = MapSet.to_list(a.permissions)

    result =
      if a.selected.id,
        do: Groups.update(a.authorization_scope, a.selected.id, a.draft, keys, a.selected.lock_version),
        else: Groups.create(a.authorization_scope, a.draft, keys)

    case result do
      {:ok, group} ->
        {:noreply,
         socket |> refresh() |> select(group) |> assign(:message, "Group saved. Access changes apply immediately.")}

      error ->
        {:noreply, failure(socket, error)}
    end
  end

  def handle_event("delete", _, socket) do
    a = socket.assigns

    case Groups.delete(a.authorization_scope, a.selected.id, a.selected.lock_version) do
      {:ok, _} -> {:noreply, socket |> assign(:selected, nil) |> refresh() |> assign(:message, "Group deleted.")}
      error -> {:noreply, failure(socket, error)}
    end
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ["permissions", "members", "activity"],
    do: {:noreply, assign(socket, :tab, tab)}

  def handle_event(event, %{"user_id" => id}, socket) when event == "add_member",
    do: change_member(socket, :add_member, id)

  def handle_event("remove_member", %{"id" => id}, socket), do: change_member(socket, :remove_member, id)

  def handle_event("effective", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.members, &(&1.id == id)),
         {:ok, permissions} <- Groups.effective(socket.assigns.authorization_scope, id) do
      {:noreply,
       socket
       |> assign(:effective, permissions)
       |> assign(:effective_person, Enum.find(socket.assigns.members, &(&1.id == id)))}
    else
      error -> {:noreply, failure(socket, error)}
    end
  end

  def handle_event("close_effective", _, socket), do: {:noreply, assign(socket, :effective, nil)}

  defp select_initial(socket) do
    group = Enum.find(socket.assigns.groups, &(&1.preset == :editor)) || List.first(socket.assigns.groups)
    if group, do: select(socket, group), else: socket
  end

  defp refresh(socket) do
    groups =
      case Groups.list(socket.assigns.authorization_scope) do
        {:ok, groups} -> groups
        _ -> []
      end

    assign(socket, :groups, groups)
  end

  defp select(socket, group) do
    scope = socket.assigns.authorization_scope
    members = if group.id, do: result_list(Groups.members(scope, group.id)), else: []
    history = if group.id, do: result_list(Groups.history(scope, group.id)), else: []

    socket
    |> assign(:selected, group)
    |> assign(:draft, %{"name" => group.name, "description" => group.description})
    |> assign(:permissions, MapSet.new(group.grants, & &1.permission_key))
    |> assign(:preview, nil)
    |> assign(:members, members)
    |> assign(:history, history)
    |> assign(:directory, result_list(Groups.directory(scope)))
    |> assign(:effective, nil)
    |> assign(:search, "")
    |> assign(:message, nil)
    |> assign(:error, nil)
    |> assign(:people_search, "")
    |> assign(:stale?, false)
    |> assign(:adding_member?, false)
  end

  defp change_member(socket, action, id) do
    with {id, ""} <- Integer.parse(id),
         {:ok, :ok} <- apply(Groups, action, [socket.assigns.authorization_scope, socket.assigns.selected.id, id]),
         {:ok, group} <- Groups.get(socket.assigns.authorization_scope, socket.assigns.selected.id) do
      scope = socket.assigns.authorization_scope

      {:noreply,
       socket
       |> refresh()
       |> assign(:selected, %{socket.assigns.selected | memberships: group.memberships})
       |> assign(:members, result_list(Groups.members(scope, group.id)))
       |> assign(:history, result_list(Groups.history(scope, group.id)))
       |> assign(:effective, nil)
       |> assign(:preview, nil)
       |> assign(:message, "Membership updated.")
       |> assign(:adding_member?, false)}
    else
      error -> {:noreply, failure(socket, error)}
    end
  end

  defp failure(socket, error) do
    message =
      case error do
        {:error, :stale} ->
          "This group changed while you were editing. Load the latest version before saving. Your draft has been kept."

        {:error, :last_superuser} ->
          "Keep at least one active superuser. Add another before removing this person."

        {:error, :protected_group} ->
          "This built-in group is protected."

        {:error, %Ecto.Changeset{}} ->
          "Enter a group name (up to 100 characters) and a description up to 500 characters."

        _ ->
          "You cannot make this change. Your permissions may have changed; reload the group to review its current access."
      end

    socket |> assign(:error, message) |> assign(:stale?, error == {:error, :stale})
  end

  defp result_list({:ok, list}), do: list
  defp result_list(_), do: []

  defp filter_groups(groups, search),
    do: Enum.filter(groups, &String.contains?(String.downcase(&1.name), String.downcase(search)))

  defp retired_permissions(catalog, permissions),
    do: MapSet.difference(permissions, MapSet.new(catalog, & &1.key)) |> Enum.sort()

  defp dirty?(nil, _, _), do: false

  defp dirty?(group, draft, permissions) do
    (is_nil(group.id) && (normalize(draft["name"]) != "" || MapSet.size(permissions) > 0)) ||
      normalize(draft["name"]) != normalize(group.name) ||
      normalize(draft["description"]) != normalize(group.description) ||
      permissions != MapSet.new(group.grants, & &1.permission_key)
  end

  defp normalize(value), do: String.trim(value || "")
  defp empty_label(""), do: "No description"
  defp empty_label(value), do: value

  defp discard_confirmation(group, draft, permissions),
    do: if(dirty?(group, draft, permissions), do: "Discard your unsaved group changes?")

  defp plural_label(1, label), do: label
  defp plural_label(_, label), do: "#{label}s"
  defp count_label(1, label), do: "1 #{label}"
  defp count_label(count, label), do: "#{count} #{label}s"
  defp available_people(directory, members), do: Enum.reject(directory, fn p -> Enum.any?(members, &(&1.id == p.id)) end)
  defp initials(name), do: name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)

  defp permission_sections(catalog, search) do
    catalog
    |> Enum.filter(
      &String.contains?(
        String.downcase("#{&1.label} #{action_label(&1.action)} #{&1.action} #{&1.section} #{&1.key}"),
        String.downcase(search)
      )
    )
    |> Enum.group_by(& &1.section)
    |> Enum.sort_by(fn {section, _} ->
      {Enum.find_index(["Workspace", "Content", "Media", "Settings", "Access", "Installation"], &(&1 == section)) || 6,
       section}
    end)
    |> Enum.map(fn {section, permissions} ->
      {section,
       permissions |> Enum.group_by(& &1.resource) |> Enum.sort_by(fn {_, ps} -> String.downcase(hd(ps).label) end)}
    end)
  end

  defp editable_keys(snapshot, group, permissions),
    do: permissions |> Enum.filter(&editable_permission?(snapshot, group, &1)) |> MapSet.new(& &1.key)

  defp selection_state(keys, selected) do
    count = MapSet.size(MapSet.intersection(keys, selected))

    cond do
      count == 0 -> "false"
      count == MapSet.size(keys) -> "true"
      true -> "mixed"
    end
  end

  defp editable_permission?(snapshot, group, p),
    do:
      group.preset != :superuser and can_save?(snapshot, group) and
        (snapshot.superuser? or (p.delegable and Map.has_key?(snapshot.grants, p.key)))

  defp can_save?(snapshot, group), do: Engine.can?(snapshot, if(group.id, do: :update, else: :create), :groups)

  defp section_actions(resources) do
    order = [
      :access,
      :read,
      :create,
      :update,
      :delete,
      :duplicate,
      :publish,
      :schedule,
      :restore,
      :export,
      :assign,
      :build,
      :deploy,
      :promote
    ]

    resources
    |> Enum.flat_map(fn {_, ps} -> Enum.map(ps, & &1.action) end)
    |> Enum.uniq()
    |> Enum.sort_by(&{Enum.find_index(order, fn action -> action == &1 end) || 99, &1})
  end

  defp selected_count(resources, selected),
    do: resources |> Enum.flat_map(&elem(&1, 1)) |> Enum.count(&MapSet.member?(selected, &1.key))

  defp permission_hint(snapshot, group, permission) do
    if editable_permission?(snapshot, group, permission),
      do: permission.key,
      else: "You cannot change this permission. Only permissions you hold in this scope can be granted."
  end

  defp action_label(:read), do: "View"
  defp action_label(:update), do: "Edit"
  defp action_label(:assign), do: "Members"
  defp action_label(action), do: action |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp permission_label(catalog, key) do
    case Enum.find(catalog, &(&1.key == key)) do
      nil -> key
      p -> "#{p.label} · #{action_label(p.action)}"
    end
  end

  defp scope_label(%{kind: :installation}, _), do: "Entire installation"
  defp scope_label(%{kind: :standalone}, _), do: "This workspace"
  defp scope_label(_, %{name: name}), do: name
  defp scope_label(_, _), do: "Selected site"
end
