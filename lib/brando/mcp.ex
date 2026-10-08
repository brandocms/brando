defmodule Brando.MCP do
  @moduledoc """
  The remote MCP endpoint: Claude, ChatGPT, Claude Code and other MCP clients
  connect to a site environment over Streamable HTTP, as a person who
  approved them, to read content and prepare proposals that the person
  reviews and applies in the admin. See the guide, `guides/mcp.md`.

  ## Off until turned on

  The endpoint is off for every site environment until an administrator
  turns it on under Configuration → Integrations → Connected AI tools. While
  it is off, its metadata, the endpoint and the OAuth endpoints answer 404,
  as a route that does not exist does. The application mounts the routes
  with `Brando.Router.mcp_routes/0`; without them there is nothing to turn
  on.

  ## Who may connect

  A person with the Connected AI tools permission (`brando.mcp.connect`,
  granted per group; the admin and superuser roles without group
  authorization) and two-factor authentication on. Both are checked again on
  every request, as are the account, the switch and the connection itself:
  taking the permission away, turning two-factor authentication off,
  deactivating the user, turning the endpoint off or revoking the connection
  stops the next call.

  ## URLs

  Without tenancy the endpoint is `<base>/mcp`; with tenancy it is
  `<base>/mcp/<site>/<environment>`. `<base>` is the endpoint's configured
  URL (`Brando.endpoint().url()`), which must be `https` in production. The
  endpoint URL is also the OAuth resource identifier (RFC 8707) and the
  issuer of the authorization server that guards it.

  ## Configuration

      config :brando, Brando.MCP,
        access_token_minutes: 60,
        refresh_token_days: 30,
        requests_per_minute: 60,
        user_requests_per_minute: 120,
        max_request_bytes: 512_000,
        allowed_origins: []
  """

  import Ecto.Query

  alias Brando.Authorization.Engine
  alias Brando.Authorization.Scope
  alias Brando.Environments.Environment
  alias Brando.MCP.Grant
  alias Brando.MCP.Setting
  alias Brando.MCP.Token
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Users.User

  @path "/mcp"
  @scope "content"

  @type tenant :: %{
          site: Site.t() | nil,
          environment: Environment.t() | nil,
          prefix: String.t() | nil,
          path: String.t()
        }

  ## Configuration

  @doc "The application's `config :brando, Brando.MCP` settings."
  @spec config() :: keyword()
  def config, do: Brando.config(__MODULE__) || []

  @doc "One of the settings in `config/0`, or `default`."
  @spec config(atom(), term()) :: term()
  def config(key, default), do: Keyword.get(config(), key, default)

  @doc "The one OAuth scope a connection gets: read content and propose changes."
  @spec scope() :: String.t()
  def scope, do: @scope

  @doc "The path the endpoints are mounted under."
  @spec path() :: String.t()
  def path, do: @path

  ## Tenants and URLs

  @doc """
  The site environment of the path segments after `/mcp`: none without
  tenancy, `[site, environment]` with it. `:error` for anything else,
  including an inactive site or an unknown environment.
  """
  @spec tenant_from_segments([String.t()]) :: {:ok, tenant()} | :error
  def tenant_from_segments([]) do
    if Tenant.mode() == :none, do: {:ok, standalone_tenant()}, else: :error
  end

  def tenant_from_segments([site_key, environment_key]) do
    with true <- Tenant.enabled?(),
         true <- Tenant.valid_key?(site_key) and Tenant.valid_key?(environment_key),
         true <- Tenant.mode() == :multi or site_key == Brando.config(:site_key),
         %Site{status: :active} = site <- Tenant.Cache.get_site(site_key),
         %Environment{} = environment <- Tenant.Cache.get_env(site_key, environment_key) do
      {:ok, tenant(site, environment)}
    else
      _ -> :error
    end
  end

  def tenant_from_segments(_segments), do: :error

  @doc "The tenant of a site environment, or of the installation without tenancy (`nil, nil`)."
  @spec tenant(Site.t() | nil, Environment.t() | nil) :: tenant()
  def tenant(nil, nil), do: standalone_tenant()

  def tenant(%Site{} = site, %Environment{} = environment) do
    %{
      site: site,
      environment: environment,
      prefix: Tenant.prefix(site, environment),
      path: "#{@path}/#{site.key}/#{environment.key}"
    }
  end

  defp standalone_tenant, do: %{site: nil, environment: nil, prefix: nil, path: @path}

  @doc """
  The tenant whose endpoint URL is exactly `resource` (RFC 8707), comparing
  the scheme and host without case. `:error` for any other URL, so a token
  can only be asked for this installation's own endpoints.
  """
  @spec tenant_for_resource(String.t() | nil) :: {:ok, tenant()} | :error
  def tenant_for_resource(resource) when is_binary(resource) and byte_size(resource) <= 2048 do
    with %URI{query: nil, fragment: nil, userinfo: nil, scheme: scheme, host: host, path: "/" <> _ = path} = uri
         when is_binary(scheme) and is_binary(host) <- URI.parse(resource),
         {:ok, segments} <- mcp_segments(path),
         {:ok, tenant} <- tenant_from_segments(segments),
         true <- canonical(uri) == resource(tenant) do
      {:ok, tenant}
    else
      _ -> :error
    end
  end

  def tenant_for_resource(_resource), do: :error

  # The segments after `/mcp` in a resource's path, under the endpoint's own
  # path, if it has one. An empty segment (a trailing slash) is not a tenant.
  defp mcp_segments(path) do
    prefix = String.trim_trailing(URI.parse(base_url()).path || "", "/") <> @path

    case String.split_at(path, String.length(prefix)) do
      {^prefix, ""} ->
        {:ok, []}

      {^prefix, "/" <> rest} ->
        if String.contains?("/" <> rest <> "/", "//"), do: :error, else: {:ok, String.split(rest, "/")}

      _ ->
        :error
    end
  end

  # Scheme and host compared without case, as RFC 3986 allows.
  defp canonical(%URI{} = uri) do
    URI.to_string(%URI{
      scheme: String.downcase(uri.scheme),
      host: String.downcase(uri.host),
      port: uri.port,
      path: uri.path
    })
  end

  @doc "The configured URL of the endpoint, without a trailing slash."
  @spec base_url() :: String.t()
  def base_url, do: String.trim_trailing(Brando.endpoint().url(), "/")

  @doc "The MCP endpoint of `tenant`: its resource identifier, and the issuer of its authorization server."
  @spec resource(tenant()) :: String.t()
  def resource(tenant), do: base_url() <> tenant.path

  @doc "Where `tenant`'s protected resource metadata is served (RFC 9728)."
  @spec resource_metadata_url(tenant()) :: String.t()
  def resource_metadata_url(tenant), do: base_url() <> "/.well-known/oauth-protected-resource" <> tenant.path

  @doc "Where `tenant`'s authorization server metadata is served (RFC 8414)."
  @spec server_metadata_url(tenant()) :: String.t()
  def server_metadata_url(tenant), do: base_url() <> "/.well-known/oauth-authorization-server" <> tenant.path

  @doc ~s[The OAuth endpoint `name` (`"authorize"`, `"token"` or `"revoke"`) of `tenant`.]
  @spec oauth_url(tenant(), String.t()) :: String.t()
  def oauth_url(tenant, name), do: resource(tenant) <> "/oauth/" <> name

  @doc """
  Whether the endpoint's URL is fit to serve: `https`, or anything outside
  production (for development and tests).
  """
  @spec secure_base?() :: boolean()
  def secure_base? do
    Brando.env() != :prod or URI.parse(base_url()).scheme == "https"
  end

  @doc "Whether the application's router mounts the MCP routes (`Brando.Router.mcp_routes/0`)."
  @spec mounted?() :: boolean()
  def mounted? do
    router = Brando.RuntimeConfig.router()
    Code.ensure_loaded?(router) and function_exported?(router, :__brando_mcp_routes__, 0)
  end

  ## The switch

  @doc """
  Whether the endpoint is on for `tenant`: switched on, with a usable URL
  and the site active. Read from the database on every request, so turning
  it off takes effect at once.
  """
  @spec enabled?(tenant()) :: boolean()
  def enabled?(tenant) do
    secure_base?() and setting_enabled?(tenant)
  end

  defp setting_enabled?(tenant) do
    tenant
    |> setting_query()
    |> where([s], s.enabled == true)
    |> Repo.repo().exists?()
  end

  defp setting_query(%{site: nil, environment: nil}),
    do: from(s in Setting, where: is_nil(s.site_id) and is_nil(s.environment_id))

  defp setting_query(%{site: %{id: site_id}, environment: %{id: environment_id}}),
    do: from(s in Setting, where: s.site_id == ^site_id and s.environment_id == ^environment_id)

  @doc """
  Turns the endpoint on or off for `tenant`, as `actor`, who must be allowed
  to manage connections (`can_manage?/2`). Turning it off leaves the
  connections in place; they answer 404 until it is on again. Recorded in
  Activity.
  """
  @spec set_enabled(tenant(), boolean(), User.t()) :: :ok | {:error, :forbidden | :insecure_url}
  def set_enabled(tenant, enabled?, actor) when is_boolean(enabled?) do
    cond do
      not can_manage?(actor, tenant) ->
        {:error, :forbidden}

      enabled? and not secure_base?() ->
        {:error, :insecure_url}

      true ->
        now = DateTime.utc_now()

        setting = %Setting{
          site_id: tenant.site && tenant.site.id,
          environment_id: tenant.environment && tenant.environment.id,
          enabled: enabled?,
          changed_by_id: actor.id,
          inserted_at: now,
          updated_at: now
        }

        {:ok, setting} =
          Repo.insert(setting,
            on_conflict: [set: [enabled: enabled?, changed_by_id: actor.id, updated_at: now]],
            conflict_target: {:unsafe_fragment, "(coalesce(site_id, 0), coalesce(environment_id, 0))"},
            returning: true
          )

        in_tenant(tenant, fn ->
          Brando.Activity.setting_changed(:updated, setting, "MCP", actor,
            details: %{"mcp" => if(enabled?, do: "enabled", else: "disabled")}
          )
        end)

        :ok
    end
  end

  @doc "Runs `fun` in `tenant`'s schema prefix."
  @spec in_tenant(tenant(), (-> result)) :: result when result: var
  def in_tenant(%{prefix: prefix}, fun), do: Tenant.with_prefix(prefix, fun)

  @doc "The authorization scope of `user` in `tenant`."
  @spec authorization_scope(User.t(), tenant()) :: Scope.t()
  def authorization_scope(user, %{site: nil}), do: Scope.standalone(user)
  def authorization_scope(user, %{site: site, environment: environment}), do: Scope.site(user, site, environment)

  ## Who may connect

  @doc """
  Why `user` may not connect a tool to `tenant`, or nil when they may:
  `:inactive` (deactivated or deleted), `:permission` (no Connected AI tools
  permission, or no access to the site) or `:two_factor` (two-factor
  authentication is off).
  """
  @spec refusal(User.t() | nil, tenant()) :: nil | :inactive | :permission | :two_factor
  def refusal(%User{} = user, tenant) do
    cond do
      not active?(user) -> :inactive
      not permitted?(user, tenant, :connect) -> :permission
      not Brando.Users.TwoFactor.enabled?(user) -> :two_factor
      true -> nil
    end
  end

  def refusal(_user, _tenant), do: :inactive

  @doc "Whether `user` may connect a tool to `tenant` now (`refusal/2` is nil)."
  @spec can_connect?(User.t() | nil, tenant()) :: boolean()
  def can_connect?(user, tenant), do: is_nil(refusal(user, tenant))

  @doc """
  Whether `user` may turn the endpoint on and off for `tenant` and see and
  revoke everyone's connections there: the `brando.mcp.manage` permission
  with group authorization, the admin or superuser role without.
  """
  @spec can_manage?(User.t() | nil, tenant()) :: boolean()
  def can_manage?(%User{} = user, tenant), do: active?(user) and permitted?(user, tenant, :manage)
  def can_manage?(_user, _tenant), do: false

  @doc """
  Whether `user` may manage connections in the current admin context, for
  presentation such as the menu: `brando.mcp.manage` in the current
  authorization scope with group authorization, the admin or superuser role
  without. Screens and actions check `can_manage?/2` for their tenant.
  """
  @spec can_manage_here?(User.t() | nil) :: boolean()
  def can_manage_here?(%User{} = user) do
    active?(user) and
      if Engine.enabled?(),
        do: Brando.Authorization.Boundary.authorize(user, :manage, :mcp) == :ok,
        else: user.role in [:admin, :superuser]
  end

  def can_manage_here?(_user), do: false

  defp active?(%User{active: true, deleted_at: nil}), do: true
  defp active?(_user), do: false

  defp permitted?(user, tenant, action) do
    if Engine.enabled?() do
      Engine.can?(authorization_scope(user, tenant), action, :mcp)
    else
      legacy_admin?(user, tenant)
    end
  end

  defp legacy_admin?(user, %{site: nil}), do: user.role in [:admin, :superuser]
  defp legacy_admin?(user, %{site: site}), do: Tenant.Access.can_manage?(user, site)

  ## Connections

  @doc "`user`'s connections that are not revoked, newest first, with their site and environment."
  @spec list_user_grants(User.t()) :: [Grant.t()]
  def list_user_grants(%User{id: user_id}) do
    from(g in Grant,
      where: g.user_id == ^user_id and is_nil(g.revoked_at),
      order_by: [desc: g.inserted_at, desc: g.id],
      preload: [:site, :environment]
    )
    |> Repo.all()
  end

  @doc "The connections to `tenant` that are not revoked, newest first, with their users."
  @spec list_grants(tenant()) :: [Grant.t()]
  def list_grants(tenant) do
    tenant
    |> grant_query()
    |> where([g], is_nil(g.revoked_at))
    |> order_by([g], desc: g.inserted_at, desc: g.id)
    |> preload(user: :avatar)
    |> Repo.all()
  end

  defp grant_query(%{site: nil}), do: from(g in Grant, where: is_nil(g.site_id) and is_nil(g.environment_id))

  defp grant_query(%{site: %{id: site_id}, environment: %{id: environment_id}}),
    do: from(g in Grant, where: g.site_id == ^site_id and g.environment_id == ^environment_id)

  @doc """
  Revokes the connection `grant_id` as `actor`: its own user, or someone who
  may manage connections to its site environment. Its tokens stop working at
  once. `reason` is recorded (`"user"`, `"admin"` …).
  """
  @spec revoke(integer() | String.t(), User.t(), String.t()) :: :ok | {:error, :not_found}
  def revoke(grant_id, %User{} = actor, reason \\ "user") do
    with {id, ""} <- Integer.parse(to_string(grant_id)),
         %Grant{revoked_at: nil} = grant <- Repo.get(Grant, id) |> Repo.preload([:site, :environment]),
         true <- grant.user_id == actor.id or can_manage?(actor, grant_tenant(grant)) do
      revoke_grant(grant, actor, reason)
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Revokes `grant` and every token of it, as `actor` (a user, or `:system`
  for a revocation Brando makes itself: reuse of a token, a client's
  revocation request, two-factor authentication turned off). Recorded in
  Activity and the user's security log once.
  """
  @spec revoke_grant(Grant.t(), User.t() | :system, String.t()) :: :ok
  def revoke_grant(%Grant{} = grant, actor, reason) do
    now = DateTime.utc_now()
    actor_id = if match?(%User{}, actor), do: actor.id

    {count, _} =
      from(g in Grant, where: g.id == ^grant.id and is_nil(g.revoked_at))
      |> Repo.update_all(set: [revoked_at: now, revoked_by_id: actor_id, revoked_reason: reason, updated_at: now])

    from(t in Token, where: t.grant_id == ^grant.id and is_nil(t.revoked_at))
    |> Repo.update_all(set: [revoked_at: now])

    if count == 1, do: record_revoked(grant, actor, reason)
    :ok
  end

  defp record_revoked(grant, actor, reason) do
    grant = Repo.preload(grant, [:site, :environment, :user])
    details = %{"client" => grant.client_name, "mcp" => "revoked", "reason" => reason}

    in_tenant(grant_tenant(grant), fn ->
      Brando.Activity.setting_changed(:deleted, grant, grant.client_name, actor_or_system(actor), details: details)
    end)

    Brando.Users.SecurityLog.record(:mcp_revoked, grant.user,
      actor: if(match?(%User{id: id} when id != grant.user_id, actor), do: actor),
      details: %{"client" => grant.client_name, "reason" => reason}
    )
  end

  defp actor_or_system(%User{} = actor), do: actor
  defp actor_or_system(_), do: :system

  @doc """
  Revokes every connection of `user`, when their sign-in security changes so
  that they may no longer connect: two-factor authentication turned off or
  reset, the account deactivated or deleted, every session logged out.
  """
  @spec revoke_user_grants(map(), String.t()) :: :ok
  def revoke_user_grants(%{id: user_id}, reason) do
    # Before the brando_213 migration there is nothing to revoke, and a
    # failed query would abort the caller's transaction.
    if installed?() do
      from(g in Grant, where: g.user_id == ^user_id and is_nil(g.revoked_at))
      |> Repo.all()
      |> Enum.each(&revoke_grant(&1, :system, reason))
    end

    :ok
  end

  defp installed? do
    %{rows: [[table]]} = Repo.repo().query!("SELECT to_regclass('public.mcp_grants')::text")
    not is_nil(table)
  end

  @doc "The tenant a connection is bound to."
  @spec grant_tenant(Grant.t()) :: tenant()
  def grant_tenant(%Grant{site_id: nil}), do: standalone_tenant()

  def grant_tenant(%Grant{} = grant) do
    grant = Repo.preload(grant, [:site, :environment])
    tenant(grant.site, grant.environment)
  end
end
