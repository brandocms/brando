defmodule Brando.Authorization.Realtime do
  @moduledoc "Fresh account checks and server-signed workspace scopes for administration channels."
  import Ecto.Query, only: [from: 2]
  alias Brando.Authorization.{Engine, Scope}
  alias Brando.Repo
  alias Brando.Users.User

  @salt "brando-realtime-scope"

  @doc false
  def allow_sandbox(socket) do
    if Application.get_env(Brando.otp_app(), :sql_sandbox, false) do
      Phoenix.Ecto.SQL.Sandbox.allow(socket.assigns[:phoenix_ecto_sandbox], Ecto.Adapters.SQL.Sandbox)
    end

    :ok
  end

  def token(actor), do: Phoenix.Token.sign(Brando.endpoint(), @salt, Scope.current(actor))

  def verify_scope(token, user_id) do
    with {:ok, %Scope{user_id: ^user_id} = scope} <-
           Phoenix.Token.verify(Brando.endpoint(), @salt, token, max_age: 86_400),
         :ok <- authorize_scope(scope) do
      {:ok, scope}
    else
      _ -> {:error, :forbidden}
    end
  end

  def authorize_account(id) when is_integer(id) do
    case active_user(id) do
      %User{} = user ->
        if not Engine.enabled?() or Engine.backend_access?(user), do: :ok, else: {:error, :forbidden}

      nil ->
        {:error, :forbidden}
    end
  end

  def authorize_account(_), do: {:error, :forbidden}

  @doc """
  Whether the scope's user may still act in its workspace. With several
  sites, a site scope in legacy mode needs the site to be enterable by the
  user now (`Brando.Tenant.Access.can_access?/2`), not only when it was signed.
  """
  def authorize_scope(%Scope{} = scope) do
    if Engine.enabled?(),
      do: Engine.authorize(scope, :access, :backend),
      else: legacy_authorize_scope(scope)
  end

  def authorize_scope(_), do: {:error, :forbidden}

  defp legacy_authorize_scope(%Scope{user_id: id} = scope) when is_integer(id) do
    case active_user(id) do
      %User{} = user -> if legacy_site_access?(scope, user), do: :ok, else: {:error, :forbidden}
      nil -> {:error, :forbidden}
    end
  end

  defp legacy_authorize_scope(_scope), do: {:error, :forbidden}

  # In :single mode every account enters the one site (Brando.Tenant.AdminContext)
  defp legacy_site_access?(scope, user), do: Brando.Tenant.mode() != :multi or legacy_visible?(scope, user)

  defp active_user(id) do
    case Repo.get(User, id) do
      %User{active: true, deleted_at: nil} = user -> user
      _ -> nil
    end
  end

  def subscribe, do: Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:authorization")

  @doc "Tells open administration channels and views to check their access again."
  def broadcast_changed,
    do: Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:authorization", {:authorization_changed, :all})

  def notification_allowed?(scope, %{authorization: %{prefix: prefix, schema: schema, entry_id: id}}) do
    authorize_scope(scope) == :ok and scope.prefix == prefix and
      (not Engine.enabled?() or Brando.Authorization.Boundary.authorize_record(scope, :read, schema, id) == :ok)
  end

  def notification_allowed?(scope, _), do: not Engine.enabled?() and authorize_scope(scope) == :ok

  # The activity directory is deliberately independent of permission to edit
  # accounts. Only colleagues who can enter this workspace are visible.
  def users(scope) do
    from(user in User, where: user.active == true and is_nil(user.deleted_at), preload: [:avatar])
    |> Repo.all()
    |> Enum.filter(fn user ->
      if Engine.enabled?(),
        do: Engine.can?(%{scope | user_id: user.id}, :access, :backend),
        else: legacy_site_access?(scope, user)
    end)
  end

  def visible_meta?(scope, %{scope: presence_scope}), do: workspace(scope) == workspace(presence_scope)
  def visible_meta?(%Scope{kind: :standalone}, _), do: not Engine.enabled?()
  def visible_meta?(_, _), do: false

  defp workspace(%Scope{} = scope), do: {scope.kind, scope.site_id, scope.environment_id, scope.prefix}

  defp legacy_visible?(%Scope{kind: :site, site_id: id}, user) do
    case Brando.Tenant.Registry.get_site(id) do
      nil -> false
      site -> Brando.Tenant.Access.can_access?(user, site)
    end
  end

  defp legacy_visible?(_, _), do: true
end
