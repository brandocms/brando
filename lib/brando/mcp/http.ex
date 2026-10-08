defmodule Brando.MCP.HTTP do
  @moduledoc """
  The HTTP side of the remote MCP endpoint, mounted by
  `Brando.Router.mcp_routes/0`:

      POST /mcp[/<site>/<environment>]                    the MCP endpoint
      GET  /mcp[/<site>/<environment>]/oauth/authorize    to the consent screen
      POST /mcp[/<site>/<environment>]/oauth/token        code and refresh grants
      POST /mcp[/<site>/<environment>]/oauth/revoke       RFC 7009
      GET  /.well-known/oauth-protected-resource/mcp[/<site>/<environment>]
      GET  /.well-known/oauth-authorization-server/mcp[/<site>/<environment>]

  A site environment with the endpoint off answers every one of them as a
  route that does not exist (`Phoenix.Router.NoRouteError`, the
  application's own 404), before anything else is checked.

  On the MCP endpoint, in order: only POST (405 otherwise); an `Origin`
  header, when sent, must be the site's own or a configured one (403); a
  bearer access token for this endpoint (401 with `WWW-Authenticate` naming
  the resource metadata; 403 when the person may no longer connect tools);
  at most `max_request_bytes` (413); at most `requests_per_minute` per
  connection and `user_requests_per_minute` per person (429). No CORS
  headers are sent.
  """
  @behaviour Plug

  import Plug.Conn

  alias Brando.MCP
  alias Brando.MCP.OAuth
  alias Brando.MCP.Server
  alias Brando.RateLimit

  @minute 60_000

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, :dispatch) do
    segments = conn.path_params["path"] || []
    {tenant_segments, rest} = split_tenant(segments)

    with {:ok, tenant} <- enabled_tenant(tenant_segments),
         {:ok, action} <- action(rest) do
      run(conn, action, tenant)
    else
      _ -> not_found(conn)
    end
  end

  def call(conn, :endpoint), do: call(%{conn | path_params: Map.put(conn.path_params, "path", [])}, :dispatch)

  def call(conn, metadata) when metadata in [:resource_metadata, :server_metadata] do
    case enabled_tenant(conn.path_params["tenant"] || []) do
      {:ok, tenant} when conn.method in ["GET", "HEAD"] -> metadata(conn, metadata, tenant)
      {:ok, _tenant} -> method_not_allowed(conn, "GET")
      :error -> not_found(conn)
    end
  end

  defp split_tenant(segments) do
    if Brando.Tenant.enabled?(), do: Enum.split(segments, 2), else: {[], segments}
  end

  defp enabled_tenant(segments) do
    with {:ok, tenant} <- MCP.tenant_from_segments(segments),
         true <- MCP.enabled?(tenant) do
      {:ok, tenant}
    else
      _ -> :error
    end
  end

  defp action([]), do: {:ok, :mcp}
  defp action(["oauth", "authorize"]), do: {:ok, :authorize}
  defp action(["oauth", "token"]), do: {:ok, :token}
  defp action(["oauth", "revoke"]), do: {:ok, :revoke}
  defp action(_rest), do: :error

  # As if the route did not exist: the application's own 404.
  defp not_found(conn) do
    raise Phoenix.Router.NoRouteError, conn: conn, router: Brando.RuntimeConfig.router()
  end

  ## The MCP endpoint

  defp run(conn, :mcp, tenant) do
    with :ok <- post_only(conn),
         :ok <- origin(conn),
         {:ok, auth} <- authenticate(conn, tenant),
         {:ok, body} <- body(conn),
         :ok <- rate_limit(auth) do
      headers = Map.new(~w(mcp-protocol-version mcp-method mcp-name), &{&1, header(conn, &1)})

      case Server.handle(body, headers, auth, tenant) do
        {202, nil} -> conn |> no_store() |> send_resp(202, "") |> halt()
        {status, reply} -> json(conn, status, reply)
      end
    else
      {:halt, conn} ->
        conn

      {:error, :method} ->
        method_not_allowed(conn, "POST")

      {:error, :origin} ->
        json(conn, 403, Server.error(nil, -32_600, "Origin not allowed."))

      {:error, :too_large} ->
        json(conn, 413, Server.error(nil, -32_600, "The request is too large."))

      {:error, :unsupported} ->
        json(conn, 415, Server.error(nil, -32_600, "Send application/json."))

      {:error, {:unauthorized, error}} ->
        unauthorized(conn, tenant, error)

      {:error, :forbidden} ->
        forbidden(conn, tenant)

      {:error, {:rate_limited, retry_after}} ->
        rate_limited(conn, retry_after, Server.error(nil, -32_000, "Too many requests."))
    end
  end

  defp run(conn, :authorize, tenant) do
    if conn.method in ["GET", "HEAD"], do: authorize(conn, tenant), else: method_not_allowed(conn, "GET")
  end

  defp run(conn, action, tenant) when action in [:token, :revoke] do
    with :ok <- post_only(conn),
         :ok <- origin(conn),
         :ok <- form(conn),
         :ok <- hit({:oauth_ip, client_ip(conn)}, MCP.config(:token_requests_per_minute, 30)),
         {:ok, conn} <- parse_form(conn) do
      oauth(conn, action, tenant, conn.body_params)
    else
      {:error, :method} -> method_not_allowed(conn, "POST")
      {:error, :origin} -> oauth_error(conn, 403, "invalid_request", "Origin not allowed.")
      {:error, :unsupported} -> oauth_error(conn, 400, "invalid_request", "Send application/x-www-form-urlencoded.")
      {:error, {:rate_limited, retry_after}} -> rate_limited(conn, retry_after, %{error: "slow_down"})
    end
  end

  defp post_only(%{method: "POST"}), do: :ok
  defp post_only(_conn), do: {:error, :method}

  # An Origin header comes from a browser: only the site's own pages, or an
  # origin the application allows, may call (DNS rebinding, cross-site use).
  defp origin(conn) do
    case header(conn, "origin") do
      nil -> :ok
      origin -> if origin in allowed_origins(), do: :ok, else: {:error, :origin}
    end
  end

  defp allowed_origins do
    base = URI.parse(MCP.base_url())
    own = URI.to_string(%URI{scheme: base.scheme, host: base.host, port: base.port})
    [own | MCP.config(:allowed_origins, [])]
  end

  defp authenticate(conn, tenant) do
    case bearer(conn) do
      nil ->
        {:error, {:unauthorized, nil}}

      token ->
        case OAuth.authenticate(token, tenant) do
          {:ok, auth} -> {:ok, auth}
          {:error, :forbidden} -> {:error, :forbidden}
          {:error, :invalid_token} -> {:error, {:unauthorized, "invalid_token"}}
        end
    end
  end

  # Only the Authorization header: never a token in the query string.
  defp bearer(conn) do
    with [value] <- get_req_header(conn, "authorization"),
         [_, token] <- Regex.run(~r/\ABearer +([A-Za-z0-9\-._~+\/]+=*)\z/i, String.trim(value)) do
      token
    else
      _ -> nil
    end
  end

  defp body(conn) do
    max = MCP.config(:max_request_bytes, 512_000)

    cond do
      not json?(conn) -> {:error, :unsupported}
      too_long?(conn, max) -> {:error, :too_large}
      true -> parsed_body(conn, max)
    end
  end

  defp json?(conn) do
    case header(conn, "content-type") do
      "application/json" <> _ -> true
      _ -> false
    end
  end

  defp too_long?(conn, max) do
    case Integer.parse(header(conn, "content-length") || "") do
      {length, ""} -> length > max
      _ -> false
    end
  end

  # The endpoint's `Plug.Parsers` has usually parsed the body already; a
  # JSON array lands in "_json". Without a parser, read it here.
  defp parsed_body(%{body_params: %Plug.Conn.Unfetched{}} = conn, max) do
    case read_body(conn, length: max) do
      {:ok, raw, _conn} ->
        case Jason.decode(raw) do
          {:ok, body} -> {:ok, body}
          {:error, _} -> {:halt, json(conn, 400, Server.error(nil, -32_700, "Parse error."))}
        end

      {:more, _, _conn} ->
        {:error, :too_large}

      {:error, _} ->
        {:halt, json(conn, 400, Server.error(nil, -32_700, "Parse error."))}
    end
  end

  defp parsed_body(%{body_params: params}, max) do
    body = Map.get(params, "_json", params)
    if IO.iodata_length(Jason.encode_to_iodata!(body)) > max, do: {:error, :too_large}, else: {:ok, body}
  end

  defp rate_limit(%{grant: grant, user: user}) do
    with :ok <- hit({:grant, grant.id}, MCP.config(:requests_per_minute, 60)) do
      hit({:user, user.id}, MCP.config(:user_requests_per_minute, 120))
    end
  end

  defp hit(bucket, limit) do
    case RateLimit.hit({MCP, bucket}, limit, @minute) do
      :ok -> :ok
      {:error, :rate_limited, retry_after} -> {:error, {:rate_limited, retry_after}}
    end
  end

  defp unauthorized(conn, tenant, error) do
    challenge =
      [
        ~s(resource_metadata="#{MCP.resource_metadata_url(tenant)}"),
        ~s(scope="#{MCP.scope()}"),
        error && ~s(error="#{error}")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    conn
    |> put_resp_header("www-authenticate", "Bearer " <> challenge)
    |> json(401, Server.error(nil, -32_000, "Authorization required."))
  end

  defp forbidden(conn, tenant) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer error="insufficient_scope", scope="#{MCP.scope()}", resource_metadata="#{MCP.resource_metadata_url(tenant)}", ) <>
        ~s(error_description="The user may no longer connect tools to this site")
    )
    |> json(403, Server.error(nil, -32_000, "The user may no longer connect tools to this site."))
  end

  ## OAuth

  defp authorize(conn, tenant) do
    params = fetch_query_params(conn).query_params
    resource = MCP.resource(tenant)

    case params["resource"] do
      value when value in [nil, ""] ->
        redirect_to_consent(conn, Map.put(params, "resource", resource))

      value ->
        case MCP.tenant_for_resource(value) do
          {:ok, ^tenant} -> redirect_to_consent(conn, params)
          _ -> conn |> no_store() |> put_resp_content_type("text/plain") |> send_resp(400, "invalid_target") |> halt()
        end
    end
  end

  defp redirect_to_consent(conn, params) do
    conn
    |> no_store()
    |> put_resp_header("location", "/admin/mcp/authorize?" <> URI.encode_query(params))
    |> send_resp(302, "")
    |> halt()
  end

  defp form(conn) do
    case header(conn, "content-type") do
      "application/x-www-form-urlencoded" <> _ -> :ok
      _ -> {:error, :unsupported}
    end
  end

  # The endpoint's `Plug.Parsers` has usually parsed the form already.
  defp parse_form(%{body_params: %Plug.Conn.Unfetched{}} = conn) do
    {:ok, Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:urlencoded], length: 16_000))}
  rescue
    _ in [Plug.Parsers.RequestTooLargeError, Plug.Parsers.BadEncodingError] -> {:error, :unsupported}
  end

  defp parse_form(conn), do: {:ok, conn}

  defp oauth(conn, _action, _tenant, %{"client_secret" => _}),
    do: oauth_error(conn, 401, "invalid_client", "Only public clients without a secret are supported.")

  defp oauth(conn, :token, tenant, params) do
    case OAuth.token(params, tenant) do
      {:ok, response} -> json(conn, 200, response)
      {:error, error, description} -> oauth_error(conn, 400, error, description)
    end
  end

  defp oauth(conn, :revoke, tenant, params) do
    case OAuth.revoke(params, tenant) do
      :ok -> json(conn, 200, %{})
      {:error, error, description} -> oauth_error(conn, 400, error, description)
    end
  end

  defp oauth_error(conn, status, error, description),
    do: json(conn, status, %{error: error, error_description: description})

  ## Metadata

  defp metadata(conn, :resource_metadata, tenant) do
    json(conn, 200, %{
      resource: MCP.resource(tenant),
      authorization_servers: [MCP.resource(tenant)],
      scopes_supported: [MCP.scope()],
      bearer_methods_supported: ["header"],
      resource_name: resource_name(tenant)
    })
  end

  defp metadata(conn, :server_metadata, tenant) do
    json(conn, 200, %{
      issuer: MCP.resource(tenant),
      authorization_endpoint: MCP.oauth_url(tenant, "authorize"),
      token_endpoint: MCP.oauth_url(tenant, "token"),
      revocation_endpoint: MCP.oauth_url(tenant, "revoke"),
      response_types_supported: ["code"],
      response_modes_supported: ["query"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      revocation_endpoint_auth_methods_supported: ["none"],
      scopes_supported: [MCP.scope()],
      client_id_metadata_document_supported: true,
      authorization_response_iss_parameter_supported: true
    })
  end

  defp resource_name(%{site: nil}), do: "Brando"
  defp resource_name(%{site: site, environment: environment}), do: "Brando · #{site.name} · #{environment.name}"

  ## Responses

  defp json(conn, status, body) do
    conn
    |> no_store()
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp method_not_allowed(conn, allow) do
    conn
    |> put_resp_header("allow", allow)
    |> no_store()
    |> send_resp(405, "")
    |> halt()
  end

  defp rate_limited(conn, retry_after, body) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(max(div(retry_after, 1000), 1)))
    |> json(429, body)
  end

  defp no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end

  defp header(conn, name), do: conn |> get_req_header(name) |> List.first()

  defp client_ip(conn) do
    case Brando.ClientIP.from_conn(conn) do
      nil -> "unknown"
      address -> address |> :inet.ntoa() |> to_string()
    end
  end
end
