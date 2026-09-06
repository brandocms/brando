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
    case Repo.get(User, id) do
      %{active: true, deleted_at: nil} = user ->
        if not Engine.enabled?() or Engine.backend_access?(user), do: :ok, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  def authorize_account(_), do: {:error, :forbidden}

  def authorize_scope(%Scope{} = scope) do
    if Engine.enabled?(),
      do: Engine.authorize(scope, :access, :backend),
      else: authorize_account(scope.user_id)
  end

  def authorize_scope(_), do: {:error, :forbidden}

  def subscribe, do: Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:authorization")

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
        else: legacy_visible?(scope, user)
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
