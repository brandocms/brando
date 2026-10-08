defmodule Brando.MCP.OAuth do
  @moduledoc """
  The OAuth 2.1 authorization server that guards the MCP endpoint: the
  authorization code grant with PKCE (S256 only), refresh tokens that rotate,
  and revocation (RFC 7009). Public clients only, identified by their Client
  ID Metadata Document (`Brando.MCP.ClientMetadata`).

  * **Authorization codes** are random, stored hashed, used once and last a
    minute. A code is bound to the client, its redirect URI, the PKCE
    challenge, the user, the site environment and the resource. Using a code
    twice revokes the connection the first use made.
  * **Access tokens** are random (`bmcp_at_…`), stored hashed (SHA-256), last
    an hour, and are only good at the endpoint they were issued for.
  * **Refresh tokens** (`bmcp_rt_…`) are hashed too, last 30 days and are
    used once: each refresh returns a new pair. Presenting a refresh token
    that was already used revokes the whole connection, since one of the two
    holders must have stolen it.

  Nothing here logs a token, code or verifier; Activity records a token by
  its row id only.
  """

  import Ecto.Query

  alias Brando.MCP
  alias Brando.MCP.AuthorizationCode
  alias Brando.MCP.ClientMetadata
  alias Brando.MCP.Grant
  alias Brando.MCP.Token
  alias Brando.Repo
  alias Brando.Users.User

  @code_seconds 60
  @max_state 1024
  # A client may refresh twice at once: within this many seconds of an
  # exchange, the same refresh token gets the same answer.
  @refresh_grace_seconds 10
  @verifier_format ~r/\A[A-Za-z0-9\-._~]{43,128}\z/
  @challenge_format ~r/\A[A-Za-z0-9\-_]{43}\z/

  @doc "How long an access token lasts, in seconds."
  @spec access_token_seconds() :: pos_integer()
  def access_token_seconds, do: MCP.config(:access_token_minutes, 60) * 60

  @doc "How long a refresh token lasts, in seconds."
  @spec refresh_token_seconds() :: pos_integer()
  def refresh_token_seconds, do: MCP.config(:refresh_token_days, 30) * 86_400

  ## Authorization requests

  @doc """
  Checks an authorization request (the query of the authorize URL) for
  `user`, who is signed in. Returns the request to show on the consent
  screen, or:

    * `{:error, {:refused, reason, request}}` — the person may not connect
      (`MCP.refusal/2`); `request` has what is known of the client;
    * `{:error, {:page, reason}}` — the client or its redirect URI cannot be
      trusted, so the person is not sent back to it;
    * `{:error, {:client_error, request, error, description}}` — the client
      and its redirect URI check out, but the request is wrong. The person
      sees an error page; nothing redirects until they click to go back to
      the client (`error_redirect/1`).
  """
  @spec validate(map(), User.t()) :: {:ok, map()} | {:error, term()}
  def validate(params, user) when is_map(params) do
    with {:ok, tenant} <- tenant(params["resource"]),
         :ok <- valid_client_id(params["client_id"]) do
      request = %{
        tenant: tenant,
        resource: MCP.resource(tenant),
        client_id: params["client_id"],
        client: nil,
        redirect_uri: params["redirect_uri"],
        # A state that is too long is refused (`request_error/1`); until then
        # it is not repeated back to anyone.
        state: bounded(params["state"], @max_state)
      }

      validate_for(MCP.refusal(user, tenant), user, request, params)
    end
  end

  defp validate_for(nil, user, request, params) do
    with :ok <- rate_limit(user), do: validate_client(request, params)
  end

  defp validate_for(reason, _user, request, _params), do: {:error, {:refused, reason, request}}

  # Each check may fetch the client's document: a few dozen a minute is
  # more than a person clicking needs.
  defp rate_limit(user) do
    case Brando.RateLimit.hit({MCP, {:authorize, user.id}}, MCP.config(:authorize_per_minute, 30), 60_000) do
      :ok -> :ok
      {:error, :rate_limited, _} -> {:error, {:page, :rate_limited}}
    end
  end

  defp tenant(resource) do
    case MCP.tenant_for_resource(resource) do
      {:ok, tenant} -> if MCP.enabled?(tenant), do: {:ok, tenant}, else: {:error, {:page, :not_found}}
      :error -> {:error, {:page, :invalid_resource}}
    end
  end

  defp valid_client_id(client_id) do
    if ClientMetadata.valid_client_id?(client_id), do: :ok, else: {:error, {:page, :invalid_client}}
  end

  defp validate_client(request, params) do
    with {:ok, client} <- fetch_client(request.client_id),
         :ok <- redirect_uri(client, request.redirect_uri) do
      request = %{request | client: client}

      case request_error(params) do
        nil -> {:ok, Map.put(request, :code_challenge, params["code_challenge"])}
        {error, description} -> {:error, {:client_error, request, error, description}}
      end
    end
  end

  # What is wrong with an authorization request whose client and redirect
  # URI check out. The person sees it on an error page; only their click
  # sends it back to the client (`error_redirect/1`).
  defp request_error(params) do
    cond do
      params["response_type"] != "code" ->
        {"unsupported_response_type", "Only the code flow is supported."}

      params["code_challenge_method"] != "S256" ->
        {"invalid_request", "PKCE with S256 is required."}

      not (is_binary(params["code_challenge"]) and params["code_challenge"] =~ @challenge_format) ->
        {"invalid_request", "code_challenge is missing or malformed."}

      not valid_scope?(params["scope"]) ->
        {"invalid_scope", "The only scope is #{MCP.scope()}."}

      not valid_state?(params["state"]) ->
        {"invalid_request", "state is too long."}

      true ->
        nil
    end
  end

  defp valid_state?(nil), do: true
  defp valid_state?(state), do: is_binary(state) and byte_size(state) <= @max_state

  defp fetch_client(client_id) do
    case ClientMetadata.fetch(client_id) do
      {:ok, client} -> {:ok, client}
      {:error, :unreachable} -> {:error, {:page, :client_unreachable}}
      {:error, _reason} -> {:error, {:page, :invalid_client}}
    end
  end

  defp redirect_uri(client, redirect_uri) do
    if ClientMetadata.redirect_allowed?(client, redirect_uri), do: :ok, else: {:error, {:page, :invalid_redirect_uri}}
  end

  # Clients may ask for the one scope, and for `offline_access`, which some
  # add for a refresh token; every connection gets one anyway.
  defp valid_scope?(nil), do: true

  defp valid_scope?(scope) when is_binary(scope) and byte_size(scope) <= 256,
    do: scope |> String.split(" ", trim: true) |> Enum.all?(&(&1 in [MCP.scope(), "offline_access"]))

  defp valid_scope?(_scope), do: false

  defp bounded(value, max) when is_binary(value) and byte_size(value) <= max, do: value
  defp bounded(_value, _max), do: nil

  @doc """
  The person approved `request` (from `validate/2`, checked again just
  before): issue a one-time code and return where to send them, the client's
  redirect URI with `code`, `state` and `iss`.
  """
  @spec approve(map(), User.t()) :: {:ok, String.t()}
  def approve(request, %User{} = user) do
    code = random("bmcp_ac_")
    now = DateTime.utc_now()

    # Codes that were never exchanged are of no use to anyone.
    from(c in AuthorizationCode, where: c.expires_at < ^DateTime.add(now, -3600, :second))
    |> Repo.delete_all()

    Repo.insert!(%AuthorizationCode{
      code_hash: hash(code),
      user_id: user.id,
      site_id: request.tenant.site && request.tenant.site.id,
      environment_id: request.tenant.environment && request.tenant.environment.id,
      resource: request.resource,
      client_id: request.client_id,
      client_name: request.client.client_name,
      redirect_uri: request.redirect_uri,
      code_challenge: request.code_challenge,
      scope: MCP.scope(),
      expires_at: DateTime.add(now, @code_seconds, :second)
    })

    {:ok, redirect_url(request, %{"code" => code})}
  end

  @doc """
  Where to send the person, at their click, back to the client of a request
  `validate/2` refused with `{:client_error, request, error, description}`.
  """
  @spec error_redirect({map(), String.t(), String.t()}) :: String.t()
  def error_redirect({request, error, description}), do: error_url(request, error, description)

  @doc "Where to send the person who declined `request`: its redirect URI with `access_denied`."
  @spec deny(map()) :: String.t()
  def deny(request), do: error_url(request, "access_denied", "The person declined.")

  defp error_url(request, error, description),
    do: redirect_url(request, %{"error" => error, "error_description" => description})

  defp redirect_url(request, params) do
    params =
      params
      |> Map.put("iss", MCP.resource(request.tenant))
      |> then(&if(request.state, do: Map.put(&1, "state", request.state), else: &1))

    uri = URI.parse(request.redirect_uri)
    query = URI.decode_query(uri.query || "") |> Map.merge(params) |> URI.encode_query()
    URI.to_string(%{uri | query: query})
  end

  ## The token endpoint

  @doc """
  Handles a token request at `tenant`'s token endpoint (form parameters).
  Returns the token response, or `{:error, error, description}` with an
  OAuth error code.
  """
  @spec token(map(), MCP.tenant()) :: {:ok, map()} | {:error, String.t(), String.t()}
  def token(%{"grant_type" => "authorization_code"} = params, tenant), do: exchange_code(params, tenant)
  def token(%{"grant_type" => "refresh_token"} = params, tenant), do: refresh(params, tenant)

  def token(%{"grant_type" => _}, _tenant),
    do: {:error, "unsupported_grant_type", "Use authorization_code or refresh_token."}

  def token(_params, _tenant), do: {:error, "invalid_request", "grant_type is missing."}

  defp exchange_code(params, tenant) do
    with {:ok, code, verifier, client_id, redirect_uri} <- code_params(params),
         :ok <- resource_param(params, tenant) do
      fn -> redeem(locked_code(code), verifier, client_id, redirect_uri, tenant) end
      |> Repo.transaction()
      |> unwrap()
    end
  end

  defp code_params(%{
         "code" => code,
         "code_verifier" => verifier,
         "client_id" => client_id,
         "redirect_uri" => redirect_uri
       })
       when is_binary(code) and is_binary(verifier) and is_binary(client_id) and is_binary(redirect_uri),
       do: {:ok, code, verifier, client_id, redirect_uri}

  defp code_params(_params),
    do: {:error, "invalid_request", "code, code_verifier, client_id and redirect_uri are required."}

  # The resource a client names must be this endpoint (RFC 8707).
  defp resource_param(%{"resource" => resource}, tenant) when is_binary(resource) do
    case MCP.tenant_for_resource(resource) do
      {:ok, ^tenant} -> :ok
      _ -> {:error, "invalid_target", "The resource is not this MCP endpoint."}
    end
  end

  defp resource_param(%{"resource" => _}, _tenant),
    do: {:error, "invalid_target", "The resource is not this MCP endpoint."}

  defp resource_param(_params, _tenant), do: :ok

  defp locked_code(code) do
    Repo.one(from c in AuthorizationCode, where: c.code_hash == ^hash(code), lock: "FOR UPDATE")
  end

  defp redeem(nil, _verifier, _client_id, _redirect_uri, _tenant), do: Repo.rollback(invalid_grant())

  defp redeem(%AuthorizationCode{used_at: used_at} = code, _verifier, _client_id, _redirect_uri, _tenant)
       when not is_nil(used_at) do
    # A code used twice: whoever holds it now may have stolen it, so the
    # connection the first use made ends (RFC 6749 section 4.1.2).
    Repo.rollback({:revoke, code.grant_id, "code_reuse"})
  end

  defp redeem(code, verifier, client_id, redirect_uri, tenant) do
    now = DateTime.utc_now()

    cond do
      DateTime.compare(code.expires_at, now) != :gt -> Repo.rollback(invalid_grant())
      not secure_equal?(code.client_id, client_id) -> Repo.rollback(invalid_grant())
      not secure_equal?(code.redirect_uri, redirect_uri) -> Repo.rollback(invalid_grant())
      not secure_equal?(code.resource, MCP.resource(tenant)) -> Repo.rollback(invalid_grant())
      not same_tenant?(code, tenant) -> Repo.rollback(invalid_grant())
      not pkce?(verifier, code.code_challenge) -> Repo.rollback(invalid_grant())
      true -> issue_from_code(code, tenant, now)
    end
  end

  defp issue_from_code(code, tenant, now) do
    user = Repo.get(User, code.user_id)

    if MCP.enabled?(tenant) and MCP.can_connect?(user, tenant) do
      grant =
        Repo.insert!(%Grant{
          user_id: user.id,
          site_id: code.site_id,
          environment_id: code.environment_id,
          resource: code.resource,
          client_id: code.client_id,
          client_name: code.client_name,
          redirect_uri: code.redirect_uri,
          scope: code.scope
        })

      code |> Ecto.Changeset.change(used_at: now, grant_id: grant.id) |> Repo.update!()
      record_connected(grant, user, tenant)
      grant |> issue_tokens() |> elem(0)
    else
      code |> Ecto.Changeset.change(used_at: now) |> Repo.update!()
      Repo.rollback({"invalid_grant", "The user may no longer connect tools."})
    end
  end

  defp record_connected(grant, user, tenant) do
    MCP.in_tenant(tenant, fn ->
      Brando.Activity.setting_changed(:created, grant, grant.client_name, user,
        details: %{"client" => grant.client_name, "mcp" => "connected"}
      )
    end)

    Brando.Users.SecurityLog.record(:mcp_connected, user, details: %{"client" => grant.client_name})
  end

  defp refresh(params, tenant) do
    with {:ok, token, client_id} <- refresh_params(params),
         :ok <- resource_param(params, tenant) do
      fn -> rotate(locked_refresh_token(token), client_id, tenant) end
      |> Repo.transaction()
      |> unwrap()
    end
  end

  defp locked_refresh_token(token) do
    Repo.one(
      from t in Token,
        where: t.token_hash == ^hash(token) and t.kind == :refresh,
        lock: "FOR UPDATE",
        preload: [:grant]
    )
  end

  defp refresh_params(%{"refresh_token" => token, "client_id" => client_id})
       when is_binary(token) and is_binary(client_id),
       do: {:ok, token, client_id}

  defp refresh_params(_params), do: {:error, "invalid_request", "refresh_token and client_id are required."}

  defp rotate(nil, _client_id, _tenant), do: Repo.rollback(invalid_grant())

  defp rotate(%Token{grant: grant} = token, client_id, tenant) do
    case refresh_refusal(token, client_id, tenant) do
      nil ->
        now = DateTime.utc_now()

        # Tokens past their time are of no use, and only rotated refresh
        # tokens still within theirs are kept, to notice reuse.
        from(t in Token, where: t.grant_id == ^grant.id and t.expires_at < ^now) |> Repo.delete_all()

        {response, successor_id} = issue_tokens(grant)
        token |> Ecto.Changeset.change(rotated_at: now, successor_id: successor_id) |> Repo.update!()
        Repo.after_commit(fn -> hold_for_replay(token, response) end)
        response

      {:replay, response} ->
        response

      refusal ->
        Repo.rollback(refusal)
    end
  end

  # Why a refresh token may not be exchanged, or nil
  defp refresh_refusal(%Token{grant: grant} = token, client_id, tenant) do
    cond do
      not is_nil(grant.revoked_at) or not is_nil(token.revoked_at) -> invalid_grant()
      not secure_equal?(grant.client_id, client_id) -> invalid_grant()
      not is_nil(token.rotated_at) -> reused(token, tenant)
      true -> refresh_expired(token, grant) || refresh_unbound(grant, tenant)
    end
  end

  defp refresh_expired(token, grant) do
    cond do
      DateTime.compare(token.expires_at, DateTime.utc_now()) != :gt -> invalid_grant()
      MCP.grant_expired?(grant) -> {"invalid_grant", "The connection has expired. Connect again."}
      true -> nil
    end
  end

  defp refresh_unbound(grant, tenant) do
    cond do
      not bound_to?(grant, tenant) -> invalid_grant()
      not allowed?(grant.user_id, tenant) -> {"invalid_grant", "The user may no longer connect tools."}
      true -> nil
    end
  end

  # A refresh token presented again. A client that refreshed twice at once
  # gets the pair the first exchange returned, within the grace period and
  # while that pair's refresh token is unused. Anything else is reuse: one of
  # the token's two holders stole it, so the connection ends.
  defp reused(%Token{grant: grant} = token, tenant) do
    with true <- DateTime.compare(token.rotated_at, grace_start(DateTime.utc_now())) == :gt,
         true <- bound_to?(grant, tenant) and allowed?(grant.user_id, tenant),
         %Token{rotated_at: nil, revoked_at: nil} <- token.successor_id && Repo.get(Token, token.successor_id),
         {:ok, response} <- held_for_replay(token) do
      {:replay, response}
    else
      _ -> {:revoke, grant.id, "refresh_token_reuse"}
    end
  end

  defp grace_start(now), do: DateTime.add(now, -@refresh_grace_seconds, :second)
  # The pair a refresh returned, held for the grace period in the node's
  # cache, encrypted for the token it replaced. Never in the database, so
  # it is in no table, backup or query log. With several nodes the grace
  # only works on the node that rotated the token: elsewhere there is no
  # entry, and a second use is treated as reuse, which is the safe side.
  defp hold_for_replay(token, response) do
    ciphertext = Brando.Crypto.encrypt(Jason.encode!(response), replay_context(token))
    Cachex.put(:cache, replay_key(token), ciphertext, expire: @refresh_grace_seconds * 1000)
  end

  defp held_for_replay(token) do
    with {:ok, ciphertext} when is_binary(ciphertext) <- Cachex.get(:cache, replay_key(token)),
         {:ok, json} <- Brando.Crypto.decrypt(ciphertext, replay_context(token)) do
      {:ok, Jason.decode!(json)}
    else
      _ -> :error
    end
  end

  @doc "The cache key of the pair the refresh token `token` was exchanged for, held for the grace period."
  @spec replay_key(map()) :: term()
  def replay_key(%{id: id}), do: {__MODULE__, :replay, id}

  defp replay_context(token), do: "mcp.refresh_replay:#{token.id}"

  defp bound_to?(grant, tenant), do: secure_equal?(grant.resource, MCP.resource(tenant)) and same_tenant?(grant, tenant)

  defp allowed?(user_id, tenant), do: MCP.enabled?(tenant) and MCP.can_connect?(Repo.get(User, user_id), tenant)

  defp issue_tokens(grant) do
    now = DateTime.utc_now()
    access = random("bmcp_at_")
    refresh = random("bmcp_rt_")

    {2, rows} =
      Repo.insert_all(
        Token,
        [
          %{
            grant_id: grant.id,
            kind: :access,
            token_hash: hash(access),
            expires_at:
              Enum.min([DateTime.add(now, access_token_seconds(), :second), MCP.grant_expires_at(grant)], DateTime),
            inserted_at: now
          },
          %{
            grant_id: grant.id,
            kind: :refresh,
            token_hash: hash(refresh),
            expires_at:
              Enum.min([DateTime.add(now, refresh_token_seconds(), :second), MCP.grant_expires_at(grant)], DateTime),
            inserted_at: now
          }
        ],
        returning: [:id, :kind]
      )

    refresh_id = Enum.find_value(rows, &(&1.kind == :refresh && &1.id))

    response = %{
      "access_token" => access,
      "token_type" => "Bearer",
      "expires_in" => min(access_token_seconds(), max(DateTime.diff(MCP.grant_expires_at(grant), now), 0)),
      "refresh_token" => refresh,
      "scope" => grant.scope
    }

    {response, refresh_id}
  end

  defp unwrap({:ok, response}), do: {:ok, response}

  # Reuse is noticed inside the token request's transaction, which rolls
  # back: the connection is revoked after it.
  defp unwrap({:error, {:revoke, grant_id, reason}}) do
    if grant_id, do: revoke_grant_id(grant_id, reason)
    {error, description} = invalid_grant()
    {:error, error, description}
  end

  defp unwrap({:error, {error, description}}), do: {:error, error, description}

  defp revoke_grant_id(grant_id, reason) do
    case Repo.get(Grant, grant_id) do
      nil -> :ok
      grant -> MCP.revoke_grant(grant, :system, reason)
    end
  end

  defp invalid_grant, do: {"invalid_grant", "The code or token is invalid, expired, used or not for this client."}

  defp same_tenant?(%{site_id: site_id, environment_id: environment_id}, tenant) do
    site_id == (tenant.site && tenant.site.id) and environment_id == (tenant.environment && tenant.environment.id)
  end

  defp pkce?(verifier, challenge) do
    verifier =~ @verifier_format and
      secure_equal?(Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false), challenge)
  end

  defp secure_equal?(a, b) when is_binary(a) and is_binary(b), do: Plug.Crypto.secure_compare(a, b)
  defp secure_equal?(_a, _b), do: false

  ## Revocation (RFC 7009)

  @doc """
  Revokes the connection of `token` (access or refresh), when `client_id` is
  the client it was issued to. Always `:ok`: the answer is the same for a
  token that does not exist, as RFC 7009 asks.
  """
  @spec revoke(map(), MCP.tenant()) :: :ok | {:error, String.t(), String.t()}
  def revoke(%{"token" => token, "client_id" => client_id}, tenant) when is_binary(token) and is_binary(client_id) do
    query = from t in Token, where: t.token_hash == ^hash(token), preload: [:grant]

    with %Token{grant: grant} <- Repo.one(query),
         true <- secure_equal?(grant.client_id, client_id),
         true <- same_tenant?(grant, tenant) do
      MCP.revoke_grant(grant, :system, "client")
    end

    :ok
  end

  def revoke(_params, _tenant), do: {:error, "invalid_request", "token and client_id are required."}

  ## Checking a request's token

  @doc """
  The connection behind the bearer `token` at `tenant`'s endpoint, checked
  now: the token is an access token for this endpoint, unexpired and not
  revoked; the connection is not revoked; its user is active, has two-factor
  authentication on and may still connect tools here.

  `{:error, :invalid_token}` (401) or `{:error, :forbidden}` (403: the
  person may no longer connect tools).
  """
  @spec authenticate(String.t() | nil, MCP.tenant()) ::
          {:ok, %{grant: Grant.t(), token: Token.t(), user: User.t()}} | {:error, :invalid_token | :forbidden}
  def authenticate(token, tenant) when is_binary(token) and byte_size(token) in 20..200 do
    now = DateTime.utc_now()

    with %Token{grant: grant} = token <- access_token(token, tenant, now),
         true <- same_tenant?(grant, tenant),
         %User{} = user <- Repo.get(User, grant.user_id) do
      authenticated(MCP.refusal(user, tenant), token, grant, user, now)
    else
      _ -> {:error, :invalid_token}
    end
  end

  def authenticate(_token, _tenant), do: {:error, :invalid_token}

  defp access_token(token, tenant, now) do
    resource = MCP.resource(tenant)
    made_after = DateTime.add(now, -MCP.grant_days() * 86_400, :second)

    Repo.one(
      from t in Token,
        join: g in assoc(t, :grant),
        where:
          t.token_hash == ^hash(token) and t.kind == :access and is_nil(t.revoked_at) and t.expires_at > ^now and
            is_nil(g.revoked_at) and g.resource == ^resource and g.inserted_at > ^made_after,
        preload: [grant: g]
    )
  end

  defp authenticated(nil, token, grant, user, now) do
    touch(token, grant, now)
    {:ok, %{grant: grant, token: token, user: user}}
  end

  defp authenticated(:permission, _token, _grant, _user, _now), do: {:error, :forbidden}
  defp authenticated(_inactive_or_two_factor, _token, _grant, _user, _now), do: {:error, :invalid_token}

  # Last used, at most once a minute per connection
  defp touch(token, grant, now) do
    if is_nil(grant.last_used_at) or DateTime.diff(now, grant.last_used_at) >= 60 do
      from(g in Grant, where: g.id == ^grant.id) |> Repo.update_all(set: [last_used_at: now])
      from(t in Token, where: t.id == ^token.id) |> Repo.update_all(set: [last_used_at: now])
    end

    :ok
  end

  ## Tokens

  defp random(prefix), do: prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  @doc "The SHA-256 hash a token or code is stored and looked up by."
  @spec hash(binary()) :: binary()
  def hash(token), do: :crypto.hash(:sha256, token)
end
