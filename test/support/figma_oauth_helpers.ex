defmodule Brando.FigmaOAuthHelpers do
  @moduledoc false
  # Connecting Figma with OAuth in tests: a stubbed Figma (the Req.Test stub
  # the test config sends every Figma request to) that answers by method and
  # path and tells the test what it was asked, and a site environment's app
  # and connection written directly.

  import Ecto.Query, only: [from: 2]

  alias Brando.MCP
  alias Brando.MCP.Setting
  alias Plug.Conn

  @client_id "figma-client-id-AB12"
  @client_secret "figma-client-secret-CD34"

  def client_id, do: @client_id
  def client_secret, do: @client_secret

  @doc """
  Stubs Figma with `answer`, called with the method, the path and the
  request's form or query params, and returning `{status, json}`. Every
  request is sent to `test` as `{:figma, method, path, params, headers}`,
  the headers a map of `authorization` and `x-figma-token`.
  """
  def stub_figma(answer, test \\ self()) do
    Req.Test.stub(Brando.Figma, fn conn ->
      {:ok, body, conn} = Conn.read_body(conn)
      conn = Conn.fetch_query_params(conn)
      params = Map.merge(conn.query_params, URI.decode_query(body))

      headers =
        Map.new(~w(authorization x-figma-token), fn name ->
          {name, conn |> Conn.get_req_header(name) |> List.first()}
        end)

      send(test, {:figma, conn.method, conn.request_path, params, headers})
      {status, json} = answer.(conn.method, conn.request_path, params)
      conn |> Conn.put_status(status) |> Req.Test.json(json)
    end)
  end

  @doc "Saves the test app for `tenant`, as `user`."
  def app!(tenant, user, client_id \\ @client_id, secret \\ @client_secret) do
    :ok = Brando.Figma.OAuth.put_app(tenant, client_id, secret, user)
    tenant
  end

  @doc """
  Writes a connection on `tenant`'s row (its app saved first): `access`,
  `refresh`, and `expires_in` seconds from now (nil for no expiry).
  """
  def connect!(tenant, opts \\ []) do
    repo = Keyword.get(opts, :repo, Brando.Repo)
    now = DateTime.utc_now()

    fields = [
      figma_oauth_access_token: encrypt(Keyword.get(opts, :access, "access-1"), tenant, :access_token),
      figma_oauth_refresh_token: encrypt(Keyword.get(opts, :refresh, "refresh-1"), tenant, :refresh_token),
      figma_oauth_expires_at:
        case Keyword.get(opts, :expires_in, 3600) do
          nil -> nil
          seconds -> DateTime.add(now, seconds, :second)
        end,
      figma_oauth_handle: Keyword.get(opts, :handle, "Ada"),
      figma_oauth_connected_at: now,
      figma_oauth_needs_reconnect: false
    ]

    {1, _} = repo.update_all(MCP.setting_query(tenant), set: fields)
    tenant
  end

  @doc "`tenant`'s settings row."
  def setting(tenant, repo \\ Brando.Repo), do: repo.one(MCP.setting_query(tenant))

  @doc "A field of `tenant`'s row decrypted, as `Brando.Figma.OAuth` encrypts it."
  def decrypted(tenant, field, repo \\ Brando.Repo) do
    column =
      Map.fetch!(
        %{
          client_id: :figma_client_id,
          client_secret: :figma_client_secret,
          access_token: :figma_oauth_access_token,
          refresh_token: :figma_oauth_refresh_token
        },
        field
      )

    tenant
    |> MCP.setting_query()
    |> then(&from(s in &1, select: field(s, ^column)))
    |> repo.one()
    |> Brando.Crypto.decrypt(context(tenant, field))
  end

  def encrypt(value, tenant, field), do: Brando.Crypto.encrypt(value, context(tenant, field))

  defp context(tenant, field),
    do: "mcp.figma_#{field}:#{(tenant.site && tenant.site.id) || 0}:#{(tenant.environment && tenant.environment.id) || 0}"

  @doc "The setting rows' Figma columns are all empty"
  def no_connection?(tenant, repo \\ Brando.Repo) do
    case setting(tenant, repo) do
      nil -> true
      %Setting{} = setting -> is_nil(setting.figma_oauth_connected_at) and is_nil(setting.figma_oauth_access_token)
    end
  end
end
