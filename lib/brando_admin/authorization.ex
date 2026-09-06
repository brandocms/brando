defmodule BrandoAdmin.Authorization do
  @moduledoc """
  Server-side LiveView authorization. Generated listings and forms declare their
  resource automatically. Custom admin views declare `__authorization__/0`, returning
  `{action, resource}`; mutations still authorize at their context boundary.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, redirect: 2, put_flash: 3]
  alias Brando.Authorization.{Boundary, Engine, Scope}

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
    "Elixir.BrandoAdmin.Sites.CacheLive" => {:read, :utilities},
    "Elixir.BrandoAdmin.Sites.UtilsLive" => {:read, :utilities},
    "Elixir.BrandoAdmin.Sites.ScheduledPublishingLive" => {:read, :utilities},
    "Elixir.BrandoAdmin.Globals.GlobalsLive" => {:update, Brando.Sites.GlobalSet},
    "Elixir.BrandoAdmin.Users.GroupsLive" => {:read, :groups},
    "Elixir.BrandoAdmin.Nav" => {:access, :backend},
    "Elixir.BrandoAdmin.Chrome" => {:access, :backend}
  }

  def requirement(view, params, live_action) do
    Code.ensure_loaded?(view)

    cond do
      view == BrandoAdmin.Users.UserUpdatePasswordLive ->
        {:update, :profile}

      function_exported?(view, :__authorization_resource__, 0) ->
        {kind, schema} = view.__authorization_resource__()

        action =
          if kind == :listing,
            do: :read,
            else: if(is_map(params) and Map.has_key?(params, "entry_id"), do: :update, else: :create)

        cond do
          is_nil(schema) -> {:access, :backend}
          live_action == :shared_update -> {:update, :shared_library}
          true -> {action, schema}
        end

      function_exported?(view, :__authorization__, 0) ->
        view.__authorization__()

      true ->
        Map.get(@views, Atom.to_string(view), {:unknown, :backend})
    end
  end

  def on_mount(:default, params, _session, socket) do
    if Engine.enabled?() do
      requirement = requirement(socket.view, params, socket.assigns[:live_action])
      scope = scope(socket, requirement, params)
      Boundary.put_scope(scope)
      socket = socket |> assign(:authorization_scope, scope) |> assign(:authorization_requirement, requirement)

      case check(socket) do
        {:cont, socket} ->
          if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:authorization")

          socket =
            if params == :not_mounted_at_router,
              do: socket,
              else: attach_hook(socket, :authorization_params, :handle_params, &params_hook/3)

          {:cont,
           socket
           |> attach_hook(:authorization_events, :handle_event, &event_hook/3)
           |> attach_hook(:authorization_info, :handle_info, &info_hook/2)}

        denied ->
          denied
      end
    else
      {:cont, socket}
    end
  end

  defp scope(socket, {_, resource}, params) do
    user = socket.assigns.current_user

    installation? =
      resource in [:sites, :frontend_assets, :shared_library] or
        (resource == Brando.Users.User and Brando.Tenant.enabled?()) or
        (resource == :groups and is_map(params) and params["scope"] == "installation")

    if installation?, do: Scope.installation(user), else: Scope.current(user)
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
    snapshot = Engine.snapshot(scope)
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

  defp event_action(_, event) when event in ["delete_entry", "delete_selected", "delete_user", "confirm_transfer_delete"],
    do: :delete

  defp event_action(_, event)
       when event in [
              "duplicate_entry",
              "duplicate_selected_to_language",
              "duplicate_entry_to_language",
              "translate_entry_to_language"
            ],
       do: :duplicate

  defp event_action(_, "undelete_entry"), do: :restore
  defp event_action(_, "rerender_entry"), do: :publish
  defp event_action(_, "export_modules"), do: :export
  defp event_action(_, "import_modules"), do: :create
  defp event_action(_, "disable_user"), do: :update
  defp event_action(_, _), do: nil

  @doc "Presentation checks against the current administration scope."
  def allowed?(action, subject) do
    not Engine.enabled?() or Engine.can?(Boundary.presentation() || Boundary.current_scope(), action, subject)
  end
end
