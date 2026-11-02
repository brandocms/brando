defmodule BrandoAdmin.Authorization do
  @moduledoc """
  Server-side LiveView authorization. Generated listings and forms declare their
  resource automatically. Custom admin views declare `__authorization__/0`, returning
  `{action, resource}`; mutations still authorize at their context boundary.

  Authority can change while a view is open. In group mode every event, patch and
  message checks the requirement again. In legacy mode every event and patch reads
  the account and its site (`Brando.Tenant.Access.legacy_standing/2`), as does the
  `authorization_changed` broadcast, which is what reaches a LiveComponent's events:

    * a role lowered ends the view's process. The client rejoins, as after a deploy:
      the view mounts at the stored role and its forms recover what was typed;
    * a site that may no longer be entered sends the view to the access-denied page.
      Installation screens and the user's own password do not depend on a site. The
      layout's sticky views (navigation, chrome, command palette), which cannot tell
      what screen they sit beside and outlive a `navigate`, do nothing about their site
      on the broadcast, so a site suspended and activated again leaves them on it. An
      event of their own while it may not be entered ends their process as for a
      lowered role, and they rejoin on the site the session resolves to now, or none.
      While this node's cache still holds the site enterable, they refuse the event
      instead;
    * otherwise, nothing happens: an editor whose authority did not change is left
      alone, and a role raised takes effect for the view's next check.

  An event the check lets through then goes to `BrandoAdmin.Authorization.Events`,
  which refuses a `:user` account's writes.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, redirect: 2, put_flash: 3]
  alias Brando.Authorization.{Administration, Boundary, Engine, Scope}
  alias Brando.Tenant.{Access, Cache}
  alias BrandoAdmin.Authorization.Events

  @legacy_actor_key {__MODULE__, :legacy_actor}

  # View names are registry data, not dependencies of the authorization engine.
  # Module aliases here would close compile-connected cycles through LiveView macros.
  @views %{
    "Elixir.BrandoAdmin.Sites.SiteLive" => {:read, :sites},
    "Elixir.BrandoAdmin.Sites.EnvironmentLive" => {:read, :environments},
    "Elixir.BrandoAdmin.Sites.PublishingLive" => {:read, :publishing},
    "Elixir.BrandoAdmin.Sites.AssetLive" => {:read, :frontend_assets},
    "Elixir.BrandoAdmin.Content.SharedLibraryLive" => {:read, :shared_library},
    "Elixir.BrandoAdmin.Sites.IdentityLive" => {:update, Brando.Sites.Identity},
    "Elixir.BrandoAdmin.Sites.SEOLive" => {:update, Brando.Sites.SEO},
    "Elixir.BrandoAdmin.Images.AltTextLive" => {:update, Brando.Images.Image},
    "Elixir.BrandoAdmin.Sites.CacheLive" => {:read, :utilities},
    "Elixir.BrandoAdmin.Sites.UtilsLive" => {:read, :utilities},
    "Elixir.BrandoAdmin.Sites.BlockAuditLive" => {:read, :utilities},
    "Elixir.BrandoAdmin.Sites.ScheduledPublishingLive" => {:read, :utilities},
    "Elixir.BrandoAdmin.Forms.InboxLive" => {:read, Brando.Forms.Form},
    "Elixir.BrandoAdmin.Forms.SubmissionsLive" => {:read, Brando.Forms.Form},
    "Elixir.BrandoAdmin.Users.GroupsLive" => {:read, :groups},
    "Elixir.BrandoAdmin.Nav" => {:access, :backend},
    "Elixir.BrandoAdmin.Chrome" => {:access, :backend},
    "Elixir.BrandoAdmin.CommandPaletteLive" => {:access, :backend}
  }

  @legacy_superuser_views [BrandoAdmin.Sites.GlobalSetListLive, BrandoAdmin.Sites.GlobalSetFormLive]

  def requirement(view, params, live_action) do
    Code.ensure_loaded?(view)

    cond do
      view == BrandoAdmin.Users.UserUpdatePasswordLive ->
        {:update, :profile}

      function_exported?(view, :__authorization_resource__, 0) ->
        resource_requirement(view.__authorization_resource__(), params, live_action)

      function_exported?(view, :__authorization__, 0) ->
        view.__authorization__()

      true ->
        Map.get(@views, Atom.to_string(view), {:unknown, :backend})
    end
  end

  defp resource_requirement({kind, schema}, params, live_action) do
    action =
      if kind == :listing,
        do: :read,
        else: if(is_map(params) and Map.has_key?(params, "entry_id"), do: :update, else: :create)

    cond do
      is_nil(schema) -> {:access, :backend}
      live_action == :shared_update -> {:update, :shared_library}
      true -> {action, schema}
    end
  end

  def on_mount(:default, params, _session, socket) do
    if Engine.enabled?() or socket.view == BrandoAdmin.Users.GroupsLive do
      requirement = requirement(socket.view, params, socket.assigns[:live_action])
      scope = scope(socket, requirement, params)
      Boundary.put_scope(scope)
      socket = socket |> assign(:authorization_scope, scope) |> assign(:authorization_requirement, requirement)

      case check(socket) do
        {:cont, socket} -> {:cont, attach_authorization_hooks(socket, params)}
        denied -> denied
      end
    else
      legacy_check(socket, params)
    end
  end

  # Legacy mode checks the roles' fixed meaning only (`Boundary`): a form for
  # module or container code opens for superusers, and so does the setup of
  # global sets, whose definitions say how an editor's values print; editors
  # fill those in on the Globals screen. `allowed?/2` asks the same for the
  # user this view holds, which the hooks below keep up to date.
  defp legacy_check(socket, params) do
    user = socket.assigns.current_user
    Process.put(@legacy_actor_key, user)
    {action, subject} = requirement(socket.view, params, socket.assigns[:live_action])

    superuser_only? =
      Brando.Authorization.Catalog.superuser_only?(action, subject) or socket.view in @legacy_superuser_views

    if superuser_only? and not Boundary.superuser?(user),
      do: {:halt, redirect(socket, to: "/admin/access-denied")},
      else: {:cont, attach_legacy_hooks(socket, params)}
  end

  # Without a user its session has just ended: there is nobody to check again, and
  # the page's own LiveView sends it to log in.
  defp attach_legacy_hooks(%{assigns: %{current_user: nil}} = socket, _params), do: socket

  defp attach_legacy_hooks(socket, params) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:authorization")

    socket =
      if params == :not_mounted_at_router,
        do: socket,
        else: attach_hook(socket, :legacy_authority_params, :handle_params, &legacy_params_hook/3)

    socket
    |> assign(:legacy_site_rule, legacy_site_rule(socket, params))
    |> attach_hook(:legacy_authority_events, :handle_event, &legacy_event_hook/3)
    |> attach_hook(:legacy_authority_info, :handle_info, &legacy_info_hook/2)
  end

  defp legacy_params_hook(params, _url, socket) do
    socket |> assign(:legacy_site_rule, legacy_site_rule(socket, params)) |> legacy_recheck()
  end

  # Runs before every other hook of the view, a listing's and a form's included.
  # A LiveComponent's events get here by `BrandoAdmin.Authorization.EventGuard`. The
  # recheck has just read the role and the view holds it, so this reads no other.
  defp legacy_event_hook(event, _params, socket) do
    with {:cont, socket} <- legacy_recheck(socket) do
      if Events.refused_to_role?(socket.view, event, socket.assigns.current_user.role),
        do: {:halt, Events.refuse(socket)},
        else: {:cont, socket}
    end
  end

  # Always halted: most views have no `handle_info` clause for it.
  defp legacy_info_hook({:authorization_changed, _}, socket) do
    {_, socket} = legacy_recheck(socket, :broadcast)
    {:halt, socket}
  end

  defp legacy_info_hook(_message, socket), do: {:cont, socket}

  # What a site no longer enterable means for this view
  defp legacy_site_rule(_socket, :not_mounted_at_router), do: :rejoin

  defp legacy_site_rule(socket, params) do
    requirement = requirement(socket.view, params, socket.assigns[:live_action])
    if requirement == {:update, :profile} or installation?(requirement, params), do: :ignore, else: :leave
  end

  defp legacy_recheck(socket, trigger \\ :own) do
    %{current_user: user, current_site: site} = socket.assigns
    site_id = if site && Brando.Tenant.mode() == :multi, do: site.id

    case Access.legacy_standing(user.id, site_id) do
      nil -> {:halt, redirect(socket, to: "/admin/access-denied")}
      {role, true} -> if lowered?(user.role, role), do: remount(socket), else: {:cont, legacy_hold_role(socket, role)}
      {role, false} -> if lowered?(user.role, role), do: remount(socket), else: site_lost(socket, role, trigger)
    end
  end

  defp site_lost(socket, role, trigger) do
    %{current_user: user, current_site: site, legacy_site_rule: site_rule} = socket.assigns

    cond do
      site_rule == :ignore or (site_rule == :rejoin and trigger == :broadcast) -> {:cont, legacy_hold_role(socket, role)}
      site_rule == :leave -> {:halt, redirect(socket, to: "/admin/access-denied")}
      rejoins_on_same_site?(user, site) -> {:halt, socket}
      true -> remount(socket)
    end
  end

  # A rejoin resolves the site from this node's cache (`Brando.Tenant.AdminContext`).
  # While that holds the site enterable a rejoin gets it back, and the view would end
  # again on the next event, a form's recovery among them: it refuses meanwhile. No
  # other node's write reaches this cache, so that can last until a registry write
  # here or a restart.
  defp rejoins_on_same_site?(user, site) do
    cached = Cache.get_site(site.key)
    not is_nil(cached) and Access.can_access?(user, cached)
  end

  defp lowered?(held, stored), do: role_rank(stored) < role_rank(held)

  defp role_rank(role) do
    {:ok, rank} = Brando.Type.Role.dump(role)
    rank
  end

  # Every gate a view set at mount is asked again, whatever it was. A shutdown, not
  # the session's sockets: closing a socket makes the client reload the page, which
  # loses what a form holds, and a rejoin recovers it. No crash report either. An HTTP
  # render has no client to rejoin, and an exit would be an error page.
  defp remount(socket) do
    if connected?(socket),
      do: exit({:shutdown, :authority_changed}),
      else: {:halt, redirect(socket, to: "/admin")}
  end

  defp legacy_hold_role(%{assigns: %{current_user: %{role: role}}} = socket, role), do: socket

  defp legacy_hold_role(%{assigns: %{current_user: user}} = socket, role) do
    user = %{user | role: role}
    Process.put(@legacy_actor_key, user)
    assign(socket, :current_user, user)
  end

  defp attach_authorization_hooks(socket, params) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:authorization")

    socket =
      if params == :not_mounted_at_router,
        do: socket,
        else: attach_hook(socket, :authorization_params, :handle_params, &params_hook/3)

    socket
    |> attach_hook(:authorization_events, :handle_event, &event_hook/3)
    |> attach_hook(:authorization_info, :handle_info, &info_hook/2)
  end

  defp scope(socket, requirement, params) do
    user = socket.assigns.current_user
    if installation?(requirement, params), do: Scope.installation(user), else: Scope.current(user)
  end

  @doc """
  Whether a view's requirement (`requirement/3`) is the installation's rather
  than a site's: sites, frontend assets, the shared library, accounts with
  tenancy on, and installation groups.
  """
  def installation?({_action, resource}, params) do
    resource in [:sites, :frontend_assets, :shared_library] or
      (resource == Brando.Users.User and Brando.Tenant.enabled?()) or
      (resource == :groups and is_map(params) and params["scope"] == "installation")
  end

  defp params_hook(params, _url, socket) do
    requirement = requirement(socket.view, params, socket.assigns[:live_action])

    socket
    |> assign(:authorization_requirement, requirement)
    |> assign(:authorization_scope, scope(socket, requirement, params))
    |> check()
  end

  defp event_hook(event, _params, socket) do
    case check(socket) do
      {:cont, socket} ->
        {_, subject} = socket.assigns.authorization_requirement
        action = event_action(subject, event)

        if is_nil(action) or Engine.authorize(socket.assigns.authorization_scope, action, subject) == :ok,
          do: {:cont, socket},
          else: {:halt, put_flash(socket, :error, "You do not have permission for this action.")}

      denied ->
        denied
    end
  end

  defp info_hook({:authorization_changed, _}, socket) do
    case check(socket) do
      {:cont, socket} ->
        socket =
          case socket.view do
            BrandoAdmin.Nav -> BrandoAdmin.Nav.refresh_authorization(socket)
            BrandoAdmin.Chrome -> BrandoAdmin.Chrome.refresh_authorization(socket)
            BrandoAdmin.Sites.ActivityLive -> BrandoAdmin.Sites.ActivityLive.refresh_authorization(socket)
            _ -> socket
          end

        {:halt, socket}

      denied ->
        denied
    end
  end

  defp info_hook(_, socket), do: check(socket)

  defp check(socket) do
    scope = socket.assigns.authorization_scope
    Boundary.put_scope(scope)
    {action, subject} = socket.assigns.authorization_requirement

    snapshot =
      if socket.view == BrandoAdmin.Users.GroupsLive,
        do: Administration.snapshot(scope),
        else: Engine.snapshot(scope)

    Boundary.put_presentation(snapshot)

    if Engine.can?(snapshot, action, subject) do
      avatar =
        case socket.assigns.current_user.avatar do
          %Ecto.Association.NotLoaded{} -> nil
          loaded -> loaded
        end

      user = %{snapshot.user | avatar: avatar}
      socket = socket |> assign(:authorization, snapshot) |> assign(:current_user, user)
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/admin/access-denied")}
    end
  end

  # Answering the step-up prompt only proves who you are. The event it holds
  # was checked on its way in, and the context checks it again when it runs.
  defp event_action(_, "brando:reauth:" <> _), do: nil

  # Every event on the webhook screens needs the one permission they have.
  defp event_action(:webhooks, _event), do: :manage
  defp event_action(:notifications, _event), do: :manage
  defp event_action(_, event) when event in ["refresh", "refresh_jobs"], do: :read

  defp event_action(:environments, event) do
    case event do
      "create_environment" ->
        :create

      "delete_environment" ->
        :delete

      "prune_archives" ->
        :delete

      value
      when value in [
             "queue_copy",
             "schedule_copy",
             "queue_set_live",
             "schedule_set_live",
             "rollback",
             "cancel_scheduled",
             "cancel_operation"
           ] ->
        :promote

      _ ->
        :update
    end
  end

  defp event_action(:publishing, event) do
    case event do
      "request_build" -> :build
      "schedule_build" -> :schedule
      _ -> :deploy
    end
  end

  defp event_action(:sites, "create_site"), do: :create
  defp event_action(:sites, event) when event in ["archive_site", "delete_site", "archive", "delete"], do: :delete
  defp event_action(:sites, _), do: :update
  defp event_action(subject, _) when subject in [:frontend_assets, :shared_library, :utilities], do: :update

  defp event_action(_, event)
       when event in ["delete_entry", "delete_selected", "delete_user", "confirm_transfer_delete", "delete_unused"],
       do: :delete

  # The media libraries' "Sort by use", drag, paste and new folder organize
  # the library: they move assets between folders and create folders.
  defp event_action(_, event)
       when event in [
              "sweep_apply",
              "sweep_undo",
              "assets_move_selected_to_folder",
              "assets_paste_selected",
              "assets_create_folder"
            ],
       do: :update

  # The video library's lookups store what they find as the system.
  defp event_action(_, "fetch_metadata"), do: :update

  defp event_action(_, event)
       when event in [
              "duplicate_entry",
              "duplicate_selected_to_language",
              "duplicate_entry_to_language",
              "translate_entry_to_language",
              "create_entry_translation"
            ],
       do: :duplicate

  defp event_action(_, "undelete_entry"), do: :restore
  defp event_action(_, "rerender_entry"), do: :publish
  defp event_action(_, "export_modules"), do: :export
  defp event_action(_, "export_module_files"), do: :export
  defp event_action(_, "import_modules"), do: :create
  defp event_action(_, event) when event in ["disable_user", "enable_user"], do: :update
  defp event_action(_, _), do: nil

  @doc """
  The user this admin view's process acts for: the authorization scope with
  groups, the user the view holds in legacy mode, else nil. For
  LiveComponents, which may not be given the user, and whose events this
  module's event check does not see.
  """
  def current_actor, do: Boundary.current_scope() || Process.get(@legacy_actor_key)

  @doc "Nil with groups, unlike `current_actor/0`: there `Events` refuses nothing."
  def legacy_actor, do: Process.get(@legacy_actor_key)

  @doc """
  Presentation checks against the current administration scope; in legacy
  mode, against the user the view holds, with no read: a template may ask
  often. What it answers follows a role change within the view's next check.
  """
  def allowed?(action, subject) do
    if Engine.enabled?(),
      do: Engine.can?(Boundary.presentation() || Boundary.current_scope(), action, subject),
      else: legacy_allowed?(Process.get(@legacy_actor_key), action, subject)
  end

  # Outside a mounted admin view there is nobody to ask: as before, allowed.
  defp legacy_allowed?(nil, _action, _subject), do: true
  defp legacy_allowed?(actor, action, subject), do: Boundary.role_allows?(actor, action, subject)
end
