defmodule Brando.MCPHelpers do
  @moduledoc false
  # The remote MCP endpoint in tests: a client whose metadata document is
  # served from here instead of the internet, a user with two-factor
  # authentication, the switch, PKCE, the consent screen and the token and
  # MCP endpoints, driven through the test router as a client would.

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn

  alias Brando.MCP
  alias Brando.MCP.Setting
  alias Brando.Repo

  @endpoint BrandoIntegrationWeb.Endpoint

  @client_id "https://client.example/oauth/client.json"
  @other_client_id "https://other.example/client.json"
  @redirect_uri "http://127.0.0.1:43123/callback"

  def client_id, do: @client_id
  def other_client_id, do: @other_client_id
  def redirect_uri, do: @redirect_uri

  @doc false
  def fetch(@client_id) do
    {:ok,
     Jason.encode!(%{
       client_id: @client_id,
       client_name: "Test Client",
       redirect_uris: ["http://127.0.0.1/callback", "https://client.example/callback"],
       token_endpoint_auth_method: "none"
     })}
  end

  def fetch(@other_client_id) do
    {:ok,
     Jason.encode!(%{client_id: @other_client_id, client_name: "Other", redirect_uris: ["https://other.example/cb"]})}
  end

  def fetch(_client_id), do: {:error, :unreachable}

  @doc "Serves the test clients' documents, and forgets counters and cached documents."
  def setup_fetcher do
    Brando.Test.Support.put_test_env(Brando.MCP, client_metadata_fetcher: {__MODULE__, :fetch})
    Brando.MCP.ClientMetadata.clear_cache()
    Brando.RateLimit.reset(&match?({Brando.MCP, _}, &1))
    :ok
  end

  @doc "Turns two-factor authentication on for `user` with an authenticator app."
  def enable_two_factor(user) do
    Repo.insert!(
      %Brando.Users.Security{user_id: user.id, totp_enabled_at: DateTime.truncate(DateTime.utc_now(), :second)},
      on_conflict: {:replace, [:totp_enabled_at]},
      conflict_target: :user_id
    )

    user
  end

  @doc "Switches the endpoint on (or off) for `tenant` directly."
  def switch!(tenant, enabled? \\ true) do
    Repo.insert!(
      %Setting{
        site_id: tenant.site && tenant.site.id,
        environment_id: tenant.environment && tenant.environment.id,
        enabled: enabled?
      },
      on_conflict: [set: [enabled: enabled?]],
      conflict_target: {:unsafe_fragment, "(coalesce(site_id, 0), coalesce(environment_id, 0))"}
    )

    tenant
  end

  @doc """
  Asserts that `conn` was answered as a route that does not exist: the
  router's `Phoenix.Router.NoRouteError`, rendered as the application's 404
  (not reraised, as for any unknown path).
  """
  def assert_not_found(conn) do
    {404, _headers, _body} = Plug.Test.sent_resp(conn)
    conn
  end

  def pkce do
    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    {verifier, Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)}
  end

  def authorize_params(tenant, challenge, overrides \\ %{}) do
    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => @client_id,
        "redirect_uri" => @redirect_uri,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256",
        "state" => "xyz",
        "scope" => "content",
        "resource" => MCP.resource(tenant)
      },
      overrides
    )
  end

  @doc "POSTs `body` with its Content-Length, as clients do."
  def post_sized(conn, path, body) do
    conn |> put_req_header("content-length", Integer.to_string(byte_size(body))) |> post(path, body)
  end

  @doc "Opens the consent screen for `params` as the conn's user."
  def consent(conn, params), do: live(conn, "/admin/mcp/authorize?" <> URI.encode_query(params))

  @doc "Approves on the consent screen and returns the redirect's query."
  def approve!(conn, params) do
    {:ok, view, _html} = consent(conn, params)
    {:error, {:redirect, %{to: url}}} = view |> element("[data-testid=mcp-consent-approve]") |> render_click()
    assert_redirect_uri!(url)
    URI.decode_query(URI.parse(url).query)
  end

  defp assert_redirect_uri!(url) do
    %URI{scheme: "http", host: "127.0.0.1", port: 43_123, path: "/callback"} = URI.parse(url)
  end

  @doc "POSTs a form to the token or revocation endpoint of `tenant`."
  def oauth_post(tenant, name, params, headers \\ []) do
    body = URI.encode_query(params)

    conn =
      Enum.reduce(headers, build_conn(), fn {k, v}, conn -> put_req_header(conn, k, v) end)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))

    post(conn, tenant.path <> "/oauth/" <> name, body)
  end

  @doc "Exchanges `code` for tokens."
  def exchange(tenant, code, verifier, overrides \\ %{}) do
    params =
      Map.merge(
        %{
          "grant_type" => "authorization_code",
          "code" => code,
          "code_verifier" => verifier,
          "client_id" => @client_id,
          "redirect_uri" => @redirect_uri,
          "resource" => MCP.resource(tenant)
        },
        overrides
      )

    oauth_post(tenant, "token", params)
  end

  @doc "Consents and exchanges: a connection's tokens."
  def connect!(conn, tenant) do
    {verifier, challenge} = pkce()
    %{"code" => code} = approve!(conn, authorize_params(tenant, challenge))
    exchange(tenant, code, verifier) |> json_response(200)
  end

  @doc "A legacy (2025-06-18) JSON-RPC request to the MCP endpoint."
  def rpc(tenant, token, method, params \\ %{}, opts \\ []) do
    message = %{"jsonrpc" => "2.0", "id" => opts[:id] || 1, "method" => method, "params" => params}
    body = Jason.encode!(opts[:body] || message)

    build_conn()
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> put_req_header("mcp-protocol-version", opts[:version] || "2025-06-18")
    |> then(&if(token, do: put_req_header(&1, "authorization", "Bearer " <> token), else: &1))
    |> then(&Enum.reduce(opts[:headers] || [], &1, fn {k, v}, conn -> put_req_header(conn, k, v) end))
    |> post(tenant.path, body)
  end

  @doc "Calls tool `name` and returns the decoded JSON-RPC response."
  def call_tool(tenant, token, name, arguments \\ %{}) do
    tenant
    |> rpc(token, "tools/call", %{"name" => "brando_content_" <> name, "arguments" => arguments})
    |> json_response(200)
  end
end
