defmodule Brando.Figma.OAuth do
  @moduledoc """
  Connects a site environment to Figma with OAuth 2, through a Figma app of
  its own, so that nobody has to paste and replace personal access tokens.

  ## The app

  Each site environment registers its own app in Figma, with the redirect
  URL `redirect_url/0` shows (on the admin's host, under the admin's mount
  path), and an administrator saves its client id and secret under
  Configuration → Integrations → Connected AI tools (`put_app/4`). They are
  stored encrypted in the environment's `mcp_settings` row
  (`Brando.Crypto`, a context per site environment and field), never in
  configuration.

  ## Connecting

  `start/3` keeps a random `state` (its hash) on the row, with what the
  callback checks it against, encrypted: the person and the session that
  started, the app as saved then, the connection it set out to replace, the
  PKCE verifier and the redirect URL. It lasts ten minutes and is used
  once. `finish/4`, from the callback, exchanges Figma's code only for that
  person and session, while they may still manage the settings, and when
  the app and the connection are still the ones it started from; it saves
  the tokens and the Figma account's handle once both steps have worked.

  ## Calls

  `access_token/2` gives the access token for a call. Within five minutes of
  its expiry, or when Figma has answered that a token expired, it refreshes
  under the row's lock (`SELECT … FOR UPDATE`, waiting at most
  `lock_timeout` for it): a call that finds that another has already stored a
  newer token uses that one. Figma's answer to a refresh may leave out the
  refresh token, which is then kept. A timeout, a 429 or a 5xx leaves
  everything for a later call to try again; Figma refusing the refresh token
  marks the connection as needing a reconnect.

      config :brando, Brando.Figma,
        oauth_url: "https://www.figma.com/oauth",
        lock_timeout: 5_000
  """

  import Ecto.Query

  alias Brando.MCP
  alias Brando.MCP.Setting
  alias Brando.Repo
  alias Brando.Users.User

  require Logger

  @authorize_url "https://www.figma.com/oauth"
  @api_url "https://api.figma.com"
  # The scopes of the calls Brando makes: file nodes and image fills
  # (file_content:read), and the account's handle, GET /v1/me
  # (current_user:read)
  @scopes "file_content:read,current_user:read"
  @pending_seconds 600
  @refresh_margin 300
  @figma_timeout 10_000
  @lock_timeout 5_000

  @type tenant :: MCP.tenant()
  @type connection_state :: :none | :connected | :needs_reconnect | :needs_repair

  defp config, do: Brando.config(Brando.Figma) || []

  @doc "The scopes the app asks for, as Figma's authorization URL takes them."
  @spec scopes() :: String.t()
  def scopes, do: @scopes

  @doc "How long a connection being made waits for its callback, in seconds."
  @spec pending_seconds() :: pos_integer()
  def pending_seconds, do: @pending_seconds

  @doc """
  The redirect URL the Figma app is registered with, and every request of
  the flow uses: the callback under the admin's mount path
  (`Brando.Router.admin_routes/3`), at the endpoint's URL, where the admin
  answers (the admin host with `tenancy_mode: :multi`, `BrandoAdmin.AdminHost`).
  """
  @spec redirect_url() :: String.t()
  def redirect_url do
    endpoint = Brando.endpoint()
    String.trim_trailing(endpoint.url(), "/") <> endpoint.path(admin_path() <> "/config/mcp/figma/callback")
  end

  defp admin_path do
    router = Brando.router()

    if Code.ensure_loaded?(router) and function_exported?(router, :__brando_admin_path__, 0),
      do: router.__brando_admin_path__(),
      else: "/admin"
  end

  ## What the admin shows

  @doc """
  What the admin shows about `tenant`'s Figma app and its connection: nil
  without an app, else the client id's last four characters (`client_hint`),
  when and by whom the app was saved, whether its credentials can still be
  decrypted (`readable`), and the connection's `state` (`connection_state/1`)
  with its Figma `handle`, `connected_at` and `connected_by`. Never a secret.
  """
  @spec status(tenant()) :: nil | map()
  def status(tenant) do
    query =
      tenant
      |> MCP.setting_query()
      |> where([s], not is_nil(s.figma_client_id))
      |> preload([:figma_app_set_by, :figma_oauth_connected_by])

    case Repo.one(query) do
      nil ->
        nil

      setting ->
        %{
          client_hint: setting.figma_client_id_hint,
          set_at: setting.figma_app_set_at,
          set_by: setting.figma_app_set_by,
          readable: match?({:ok, _, _}, app_credentials(setting, tenant)),
          state: state_of(setting, tenant),
          handle: setting.figma_oauth_handle,
          connected_at: setting.figma_oauth_connected_at,
          connected_by: setting.figma_oauth_connected_by
        }
    end
  end

  @doc """
  Where `tenant`'s OAuth connection stands: `:none` (no connection, so calls
  use a pasted token if there is one), `:connected`, `:needs_reconnect`
  (Figma refused its refresh token) or `:needs_repair` (a part of it no
  longer decrypts, as after a change of the encryption secret). Calls never
  move over to a pasted token from the last two.
  """
  @spec connection_state(tenant()) :: connection_state()
  def connection_state(tenant) do
    case tenant |> MCP.setting_query() |> Repo.one() do
      nil -> :none
      setting -> state_of(setting, tenant)
    end
  end

  defp state_of(%Setting{figma_oauth_connected_at: nil}, _tenant), do: :none
  defp state_of(%Setting{figma_oauth_needs_reconnect: true}, _tenant), do: :needs_reconnect

  defp state_of(setting, tenant) do
    case secrets(setting, tenant) do
      {:ok, _secrets} -> :connected
      :error -> :needs_repair
    end
  end

  ## The app

  @doc """
  Saves `client_id` and `client_secret` as `tenant`'s Figma app, as `actor`
  (`Brando.MCP.can_manage?/2`). Another client id than the one saved removes
  the connection, which is then made again; the same client id with a new
  secret keeps it. A pasted token stays as it is. Recorded in Activity
  without the credentials.
  """
  @spec put_app(tenant(), String.t(), String.t(), User.t()) :: :ok | {:error, :forbidden | :invalid_app}
  def put_app(tenant, client_id, client_secret, actor) when is_binary(client_id) and is_binary(client_secret) do
    client_id = String.trim(client_id)
    client_secret = String.trim(client_secret)

    cond do
      not MCP.can_manage?(actor, tenant) ->
        {:error, :forbidden}

      not (credential?(client_id) and credential?(client_secret)) ->
        {:error, :invalid_app}

      true ->
        now = DateTime.utc_now()

        locked(tenant, fn setting ->
          same_app? = setting != nil and match?({:ok, ^client_id, _}, app_credentials(setting, tenant))
          replaced? = setting != nil and not is_nil(setting.figma_client_id)
          disconnected? = setting != nil and not same_app? and not is_nil(setting.figma_oauth_connected_at)

          fields =
            [
              figma_client_id: Brando.Crypto.encrypt(client_id, context(tenant, :client_id)),
              figma_client_id_hint: String.slice(client_id, -4, 4),
              figma_client_secret: Brando.Crypto.encrypt(client_secret, context(tenant, :client_secret)),
              figma_app_set_at: now,
              figma_app_set_by_id: actor.id
            ] ++ if(same_app?, do: [], else: connection_fields())

          setting = upsert(tenant, setting, fields)
          details = %{"figma_app" => if(replaced?, do: "replaced", else: "added")}
          record(tenant, setting, actor, if(disconnected?, do: Map.put(details, "figma_oauth", "removed"), else: details))
          :ok
        end)
    end
  end

  def put_app(_tenant, _client_id, _client_secret, _actor), do: {:error, :invalid_app}

  @doc """
  Removes `tenant`'s Figma app and the connection made with it, as `actor`
  (`Brando.MCP.can_manage?/2`). Calls use the pasted token again, if there
  is one. Recorded in Activity.
  """
  @spec delete_app(tenant(), User.t()) :: :ok | {:error, :forbidden}
  def delete_app(tenant, actor) do
    if MCP.can_manage?(actor, tenant) do
      locked(tenant, fn
        nil ->
          :ok

        setting ->
          # A connection being made stays, for its callback to say the app went
          fields = app_fields() ++ connection_fields()
          setting = upsert(tenant, setting, fields)
          record(tenant, setting, actor, %{"figma_app" => "removed"})
          :ok
      end)
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Removes `tenant`'s OAuth connection and keeps the app, as `actor`
  (`Brando.MCP.can_manage?/2`): calls use the pasted token again, if there is
  one. Recorded in Activity.
  """
  @spec disconnect(tenant(), User.t()) :: :ok | {:error, :forbidden}
  def disconnect(tenant, actor) do
    if MCP.can_manage?(actor, tenant) do
      locked(tenant, fn
        %Setting{figma_oauth_connected_at: %DateTime{}} = setting ->
          setting = upsert(tenant, setting, connection_fields())
          record(tenant, setting, actor, %{"figma_oauth" => "disconnected"})
          :ok

        _no_connection ->
          :ok
      end)
    else
      {:error, :forbidden}
    end
  end

  # Client ids and secrets are printable ASCII without spaces
  defp credential?(value), do: byte_size(value) in 8..512 and String.match?(value, ~r/\A[\x21-\x7E]+\z/)

  ## Connecting

  @doc """
  Starts connecting `tenant` to Figma, as `actor` in the admin session whose
  token row is `session_id` (`Brando.Users.token_id/1`): keeps a new `state`
  and returns Figma's authorization URL to send the browser to. A connection
  already being made is replaced, so a new attempt always works.
  """
  @spec start(tenant(), User.t(), integer() | nil) ::
          {:ok, String.t()} | {:error, :forbidden | :no_app | :unreadable_app}
  def start(tenant, actor, session_id) do
    if MCP.can_manage?(actor, tenant) and is_integer(session_id) do
      locked(tenant, fn setting -> start_locked(setting, tenant, actor, session_id) end)
    else
      {:error, :forbidden}
    end
  end

  defp start_locked(%Setting{figma_client_id: client} = setting, tenant, actor, session_id) when is_binary(client) do
    case app_credentials(setting, tenant) do
      {:ok, client_id, _secret} ->
        state = random()
        verifier = random()
        redirect_uri = redirect_url()

        pending = %{
          "user_id" => actor.id,
          "session_id" => session_id,
          "app" => marker(setting.figma_app_set_at),
          "connection" => marker(setting.figma_oauth_connected_at),
          "verifier" => verifier,
          "redirect_uri" => redirect_uri,
          "expires_at" => System.system_time(:second) + @pending_seconds
        }

        upsert(tenant, setting,
          figma_oauth_state_hash: hash(state),
          figma_oauth_pending: Brando.Crypto.encrypt(Jason.encode!(pending), context(tenant, :pending))
        )

        query = %{
          "client_id" => client_id,
          "redirect_uri" => redirect_uri,
          "scope" => @scopes,
          "state" => state,
          "response_type" => "code",
          "code_challenge" => Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false),
          "code_challenge_method" => "S256"
        }

        {:ok, Keyword.get(config(), :oauth_url, @authorize_url) <> "?" <> URI.encode_query(query, :rfc3986)}

      :error ->
        {:error, :unreadable_app}
    end
  end

  defp start_locked(_setting, _tenant, _actor, _session_id), do: {:error, :no_app}

  @typedoc "Why a callback saved nothing."
  @type refusal ::
          :unknown
          | :expired
          | :forbidden
          | :changed
          | :denied
          | :exchange_failed
          | :account_failed
          | :save_failed

  @doc """
  Finishes the connection `params` (the callback's query: `state` and `code`,
  or Figma's `error`) answers, for `user` in the session `session_id`.
  `{:ok, tenant}` once the tokens and the account's handle are saved;
  otherwise `{:error, refusal, tenant | nil}`, having saved nothing. The
  state is used once: whatever the outcome, it is gone after, unless it was
  not this person's and session's, which leaves it to its own.
  """
  @spec finish(map(), User.t() | nil, integer() | nil) :: {:ok, tenant()} | {:error, refusal(), tenant() | nil}
  def finish(%{"state" => state} = params, %User{} = user, session_id) when is_binary(state) and state != "" do
    case claim(state, user, session_id) do
      {:ok, setting, pending} ->
        tenant = tenant_of(setting)

        with :ok <- if(MCP.can_manage?(user, tenant), do: :ok, else: :forbidden),
             :ok <- code_given(params),
             :ok <- unchanged(setting, pending),
             {:ok, client_id, secret} <- app_or_changed(setting, tenant),
             {:ok, tokens} <- exchange(params["code"], pending, client_id, secret),
             {:ok, handle} <- account(tokens["access_token"]),
             :ok <- save_connection(tenant, pending, tokens, handle, user) do
          {:ok, tenant}
        else
          # The row's lock not free in time, while saving
          {:error, _reason} -> {:error, :save_failed, tenant}
          reason -> {:error, reason, tenant}
        end

      {:error, reason} ->
        {:error, reason, nil}
    end
  end

  def finish(_params, _user, _session_id), do: {:error, :unknown, nil}

  # The pending connection `state` names, taken off the row when it is this
  # person's and session's and not past its time (then gone too)
  defp claim(state, user, session_id) do
    hash = hash(state)

    transaction(fn ->
      query =
        from(s in Setting, where: s.figma_oauth_state_hash == ^hash, lock: "FOR UPDATE", preload: [:site, :environment])

      case Repo.one(query) do
        nil -> {:error, :unknown}
        setting -> claim_locked(setting, pending(setting), user, session_id)
      end
    end)
  end

  # A pending connection that no longer decrypts is of no use to anyone
  defp claim_locked(setting, :error, _user, _session_id) do
    clear_pending(setting)
    {:error, :unknown}
  end

  defp claim_locked(setting, {:ok, pending}, user, session_id) do
    cond do
      pending["user_id"] != user.id or pending["session_id"] != session_id ->
        {:error, :unknown}

      pending["expires_at"] < System.system_time(:second) ->
        clear_pending(setting)
        {:error, :expired}

      true ->
        clear_pending(setting)
        {:ok, setting, pending}
    end
  end

  defp pending(setting) do
    with {:ok, json} <- Brando.Crypto.decrypt(setting.figma_oauth_pending, context(tenant_of(setting), :pending)),
         {:ok, %{} = pending} <- Jason.decode(json) do
      {:ok, pending}
    else
      _ -> :error
    end
  end

  defp clear_pending(setting) do
    from(s in Setting, where: s.id == ^setting.id)
    |> Repo.update_all(set: pending_fields() ++ [updated_at: DateTime.utc_now()])
  end

  # Figma sends no callback when consent is refused (its documentation); an
  # `error` or a missing code is taken as a refusal all the same
  defp code_given(%{"code" => code} = params) when is_binary(code) and code != "",
    do: if(Map.has_key?(params, "error"), do: :denied, else: :ok)

  defp code_given(_params), do: :denied

  defp unchanged(setting, pending) do
    if pending["app"] == marker(setting.figma_app_set_at) and
         pending["connection"] == marker(setting.figma_oauth_connected_at),
       do: :ok,
       else: :changed
  end

  defp app_or_changed(setting, tenant) do
    case app_credentials(setting, tenant) do
      {:ok, _client_id, _secret} = app -> app
      :error -> :changed
    end
  end

  defp exchange(code, pending, client_id, secret) do
    form = [
      redirect_uri: pending["redirect_uri"],
      code: code,
      grant_type: "authorization_code",
      code_verifier: pending["verifier"]
    ]

    case post("/v1/oauth/token", form, client_id, secret) do
      {:ok, %{"access_token" => access, "refresh_token" => refresh} = tokens}
      when is_binary(access) and access != "" and is_binary(refresh) and refresh != "" ->
        {:ok, tokens}

      _other ->
        :exchange_failed
    end
  end

  defp account(access_token) do
    case Brando.Figma.check({:bearer, access_token}) do
      {:valid, handle} -> {:ok, handle}
      _other -> :account_failed
    end
  end

  defp save_connection(tenant, pending, tokens, handle, user) do
    now = DateTime.utc_now()

    locked(tenant, fn setting ->
      with %Setting{} <- setting,
           :ok <- unchanged(setting, pending) do
        fields =
          [
            figma_oauth_access_token: Brando.Crypto.encrypt(tokens["access_token"], context(tenant, :access_token)),
            figma_oauth_refresh_token: Brando.Crypto.encrypt(tokens["refresh_token"], context(tenant, :refresh_token)),
            figma_oauth_expires_at: expires_at(tokens["expires_in"], now),
            figma_oauth_handle: handle,
            figma_oauth_connected_at: now,
            figma_oauth_connected_by_id: user.id,
            figma_oauth_needs_reconnect: false
          ]

        setting = upsert(tenant, setting, fields)
        details = %{"figma_oauth" => if(pending["connection"], do: "reconnected", else: "connected")}
        record(tenant, setting, user, details)
        :ok
      else
        _changed -> :changed
      end
    end)
  end

  ## Calls

  @doc """
  The access token of `tenant`'s connection for a call. Refreshed first under
  the row's lock when it expires within five minutes, or when `rejected` is
  the token Figma just answered "expired" to, unless another call has stored
  a newer one meanwhile. `{:error, reason}`: `:disconnected` (no connection
  any more), `:needs_reconnect`, `:needs_repair`, `:busy` (the lock was not
  free in time) or `:unreachable` (Figma did not answer the refresh; try
  again later).
  """
  @spec access_token(tenant(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :disconnected | :needs_reconnect | :needs_repair | :busy | :unreachable}
  def access_token(tenant, rejected \\ nil) do
    case tenant |> MCP.setting_query() |> Repo.one() do
      %Setting{} = setting ->
        case usable(setting, tenant) do
          {:ok, %{access: access}} ->
            if is_nil(rejected) and fresh?(setting.figma_oauth_expires_at),
              do: {:ok, access},
              else: refresh(tenant, rejected)

          error ->
            error
        end

      nil ->
        {:error, :disconnected}
    end
  end

  defp usable(%Setting{figma_oauth_connected_at: nil}, _tenant), do: {:error, :disconnected}
  defp usable(%Setting{figma_oauth_needs_reconnect: true}, _tenant), do: {:error, :needs_reconnect}

  defp usable(setting, tenant) do
    case secrets(setting, tenant) do
      {:ok, secrets} -> {:ok, secrets}
      :error -> {:error, :needs_repair}
    end
  end

  defp fresh?(nil), do: true
  defp fresh?(expires_at), do: DateTime.diff(expires_at, DateTime.utc_now()) > @refresh_margin

  defp refresh(tenant, rejected) do
    locked(tenant, fn setting ->
      with %Setting{} <- setting,
           {:ok, secrets} <- usable(setting, tenant) do
        cond do
          # Another call refreshed while this one waited
          rejected && secrets.access != rejected -> {:ok, secrets.access}
          is_nil(rejected) and fresh?(setting.figma_oauth_expires_at) -> {:ok, secrets.access}
          true -> refresh_locked(setting, tenant, secrets)
        end
      else
        nil -> {:error, :disconnected}
        error -> error
      end
    end)
  end

  defp refresh_locked(setting, tenant, secrets) do
    case post("/v1/oauth/refresh", [refresh_token: secrets.refresh], secrets.client_id, secrets.client_secret) do
      {:ok, %{"access_token" => access} = answer} when is_binary(access) and access != "" ->
        refresh_token =
          case answer["refresh_token"] do
            token when is_binary(token) and token != "" -> token
            _kept -> secrets.refresh
          end

        upsert(tenant, setting,
          figma_oauth_access_token: Brando.Crypto.encrypt(access, context(tenant, :access_token)),
          figma_oauth_refresh_token: Brando.Crypto.encrypt(refresh_token, context(tenant, :refresh_token)),
          figma_oauth_expires_at: expires_at(answer["expires_in"], DateTime.utc_now())
        )

        {:ok, access}

      {:refused, _status} ->
        setting = upsert(tenant, setting, figma_oauth_needs_reconnect: true)
        record(tenant, setting, :system, %{"figma_oauth" => "needs_reconnect"})
        Logger.warning("[Brando.Figma.OAuth] Figma refused the refresh token: the connection needs reconnecting")
        {:error, :needs_reconnect}

      _unreachable ->
        {:error, :unreachable}
    end
  end

  defp expires_at(seconds, now) when is_integer(seconds) and seconds > 0, do: DateTime.add(now, seconds, :second)
  defp expires_at(_seconds, _now), do: nil

  # POST to Figma's token or refresh endpoint, the app's credentials in HTTP
  # Basic authentication (Figma's documentation). `{:refused, status}` only
  # when Figma itself refuses (a 400, 401 or 403 with its error text);
  # anything else is `:unreachable`, and a later call tries again.
  defp post(path, form, client_id, secret) do
    options =
      Keyword.merge(
        [
          base_url: Keyword.get(config(), :api_url, @api_url),
          url: path,
          form: form,
          auth: {:basic, client_id <> ":" <> secret},
          receive_timeout: @figma_timeout,
          connect_options: [timeout: @figma_timeout],
          retry: false,
          redirect: false
        ],
        Keyword.get(config(), :req_options, [])
      )

    case Req.post(options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status} = response} when status in [400, 401, 403] ->
        if figma_said?(response), do: {:refused, status}, else: :unreachable

      _other ->
        :unreachable
    end
  end

  # A JSON body with an error in it is Figma's; anything else came from
  # something in front of it
  defp figma_said?(%Req.Response{body: body}) when is_map(body),
    do: Enum.any?(~w(error err message error_description), &(body[&1] not in [nil, false, ""]))

  defp figma_said?(%Req.Response{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> figma_said?(%Req.Response{body: decoded})
      _ -> false
    end
  end

  defp figma_said?(_response), do: false

  ## The row

  # Runs `fun` with `tenant`'s row locked (nil when there is none), waiting
  # at most `lock_timeout` for the lock
  defp locked(tenant, fun) do
    timeout = Keyword.get(config(), :lock_timeout, @lock_timeout)

    transaction(fn ->
      Repo.repo().query!("SET LOCAL lock_timeout = '#{Integer.to_string(timeout)}ms'")
      tenant |> MCP.setting_query() |> lock("FOR UPDATE") |> Repo.one() |> fun.()
    end)
  rescue
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :lock_not_available}}, error),
        do: {:error, :busy},
        else: reraise(error, __STACKTRACE__)
  end

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert(_tenant, %Setting{} = setting, fields) do
    {1, [setting]} =
      from(s in Setting, where: s.id == ^setting.id, select: s)
      |> Repo.update_all(set: Keyword.put(fields, :updated_at, DateTime.utc_now()))

    setting
  end

  defp upsert(tenant, nil, fields) do
    now = DateTime.utc_now()

    struct(
      %Setting{
        site_id: tenant.site && tenant.site.id,
        environment_id: tenant.environment && tenant.environment.id,
        inserted_at: now,
        updated_at: now
      },
      fields
    )
    |> Repo.insert!()
  end

  defp record(tenant, setting, actor, details) do
    MCP.in_tenant(tenant, fn -> Brando.Activity.setting_changed(:updated, setting, "MCP", actor, details: details) end)
  end

  defp app_fields,
    do: [
      figma_client_id: nil,
      figma_client_id_hint: nil,
      figma_client_secret: nil,
      figma_app_set_at: nil,
      figma_app_set_by_id: nil
    ]

  defp connection_fields,
    do: [
      figma_oauth_access_token: nil,
      figma_oauth_refresh_token: nil,
      figma_oauth_expires_at: nil,
      figma_oauth_handle: nil,
      figma_oauth_connected_at: nil,
      figma_oauth_connected_by_id: nil,
      figma_oauth_needs_reconnect: false
    ]

  defp pending_fields, do: [figma_oauth_state_hash: nil, figma_oauth_pending: nil]

  defp app_credentials(setting, tenant) do
    with {:ok, client_id} <- Brando.Crypto.decrypt(setting.figma_client_id, context(tenant, :client_id)),
         {:ok, secret} <- Brando.Crypto.decrypt(setting.figma_client_secret, context(tenant, :client_secret)) do
      {:ok, client_id, secret}
    end
  end

  defp secrets(setting, tenant) do
    with {:ok, client_id, client_secret} <- app_credentials(setting, tenant),
         {:ok, access} <- Brando.Crypto.decrypt(setting.figma_oauth_access_token, context(tenant, :access_token)),
         {:ok, refresh} <- Brando.Crypto.decrypt(setting.figma_oauth_refresh_token, context(tenant, :refresh_token)) do
      {:ok, %{client_id: client_id, client_secret: client_secret, access: access, refresh: refresh}}
    end
  end

  defp tenant_of(%Setting{site_id: nil}), do: MCP.tenant(nil, nil)
  defp tenant_of(%Setting{site: site, environment: environment}), do: MCP.tenant(site, environment)

  # Binds each ciphertext to its site environment and field: copied to
  # another row or column, it does not decrypt
  defp context(tenant, field),
    do: "mcp.figma_#{field}:#{(tenant.site && tenant.site.id) || 0}:#{(tenant.environment && tenant.environment.id) || 0}"

  defp marker(nil), do: nil
  defp marker(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)

  defp random, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp hash(state), do: :crypto.hash(:sha256, state)
end
