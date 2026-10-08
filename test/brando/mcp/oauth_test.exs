defmodule Brando.MCP.OAuthTest do
  # The authorization flow of the remote MCP endpoint, as a client drives it:
  # metadata, the consent screen, the code exchange with PKCE, refresh
  # rotation with reuse detection, and revocation, with the ways each must
  # fail.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.MCP
  alias Brando.MCP.AuthorizationCode
  alias Brando.MCP.Grant
  alias Brando.MCP.Token
  alias Brando.Users.SecurityEvent

  setup %{current_user: user} do
    setup_fetcher()
    enable_two_factor(user)
    tenant = MCP.tenant(nil, nil) |> switch!()
    %{tenant: tenant}
  end

  describe "metadata" do
    test "describes the protected resource and its authorization server", %{tenant: tenant} do
      resource = MCP.resource(tenant)

      prm = build_conn() |> get("/.well-known/oauth-protected-resource/mcp") |> json_response(200)
      assert prm["resource"] == resource
      assert prm["authorization_servers"] == [resource]
      assert prm["scopes_supported"] == ["content"]

      as = build_conn() |> get("/.well-known/oauth-authorization-server/mcp") |> json_response(200)
      assert as["issuer"] == resource
      assert as["code_challenge_methods_supported"] == ["S256"]
      assert as["token_endpoint_auth_methods_supported"] == ["none"]
      assert as["client_id_metadata_document_supported"] == true
      assert as["authorization_response_iss_parameter_supported"] == true
      assert as["token_endpoint"] == resource <> "/oauth/token"
      refute Map.has_key?(as, "registration_endpoint")
    end

    test "an unauthenticated call points at the resource metadata", %{tenant: tenant} do
      conn = rpc(tenant, nil, "tools/list")
      assert conn.status == 401
      [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ ~s(resource_metadata="#{MCP.resource_metadata_url(tenant)}")
      assert challenge =~ ~s(scope="content")
    end
  end

  describe "the whole flow" do
    test "consent, code, MCP calls, refresh rotation, reuse detection and revocation", %{
      conn: conn,
      tenant: tenant,
      current_user: user
    } do
      {verifier, challenge} = pkce()
      params = authorize_params(tenant, challenge)

      # The authorize URL leads to the consent screen with the same request.
      authorize = build_conn() |> get("/mcp/oauth/authorize?" <> URI.encode_query(Map.delete(params, "resource")))
      assert "/admin/mcp/authorize?" <> query = redirected_to(authorize, 302)
      assert URI.decode_query(query)["resource"] == MCP.resource(tenant)

      {:ok, view, html} = consent(conn, params)
      assert html =~ "Test Client"
      assert html =~ "client.example"
      assert html =~ "127.0.0.1:43123"
      # Nothing is approved without the click.
      assert Repo.aggregate(AuthorizationCode, :count) == 0

      {:error, {:redirect, %{to: url}}} = view |> element("[data-testid=mcp-consent-approve]") |> render_click()
      redirect = URI.decode_query(URI.parse(url).query)
      assert redirect["state"] == "xyz"
      assert redirect["iss"] == MCP.resource(tenant)
      assert "bmcp_ac_" <> _ = code = redirect["code"]

      # Codes and tokens are stored as hashes only.
      [stored] = Repo.all(AuthorizationCode)
      assert stored.code_hash == :crypto.hash(:sha256, code)

      tokens = exchange(tenant, code, verifier) |> json_response(200)
      assert %{"token_type" => "Bearer", "expires_in" => 3600, "scope" => "content"} = tokens
      assert "bmcp_at_" <> _ = access = tokens["access_token"]
      assert "bmcp_rt_" <> _ = refresh = tokens["refresh_token"]
      refute Repo.exists?(from t in Token, where: t.token_hash == ^access or t.token_hash == ^refresh)

      assert [%Grant{client_name: "Test Client", user_id: user_id, revoked_at: nil}] = Repo.all(Grant)
      assert user_id == user.id
      assert Repo.exists?(from e in SecurityEvent, where: e.user_id == ^user.id and e.action == :mcp_connected)

      assert %{"result" => %{"tools" => [_ | _]}} = rpc(tenant, access, "tools/list") |> json_response(200)

      # Refresh: a new pair; the old refresh token is spent.
      refreshed =
        tenant
        |> oauth_post("token", %{"grant_type" => "refresh_token", "refresh_token" => refresh, "client_id" => client_id()})
        |> json_response(200)

      assert refreshed["refresh_token"] != refresh
      assert rpc(tenant, refreshed["access_token"], "ping") |> json_response(200)

      # Reuse of the spent refresh token: the whole connection ends.
      reuse =
        oauth_post(tenant, "token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => refresh,
          "client_id" => client_id()
        })

      assert %{"error" => "invalid_grant"} = json_response(reuse, 400)
      assert %Grant{revoked_reason: "refresh_token_reuse"} = Repo.one!(Grant)
      assert rpc(tenant, refreshed["access_token"], "ping").status == 401

      reuse_refresh =
        oauth_post(tenant, "token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => refreshed["refresh_token"],
          "client_id" => client_id()
        })

      assert json_response(reuse_refresh, 400)["error"] == "invalid_grant"
    end

    test "revocation (RFC 7009) ends the connection", %{conn: conn, tenant: tenant} do
      tokens = connect!(conn, tenant)

      assert oauth_post(tenant, "revoke", %{"token" => tokens["refresh_token"], "client_id" => client_id()})
             |> json_response(200) == %{}

      assert rpc(tenant, tokens["access_token"], "ping").status == 401

      # Unknown tokens get the same answer.
      assert oauth_post(tenant, "revoke", %{"token" => "bmcp_rt_nothing", "client_id" => client_id()}).status == 200
    end

    test "a revocation for another client changes nothing", %{conn: conn, tenant: tenant} do
      tokens = connect!(conn, tenant)

      assert oauth_post(tenant, "revoke", %{"token" => tokens["access_token"], "client_id" => other_client_id()}).status ==
               200

      assert rpc(tenant, tokens["access_token"], "ping").status == 200
    end
  end

  describe "the code exchange refuses" do
    setup %{conn: conn, tenant: tenant} do
      {verifier, challenge} = pkce()
      %{"code" => code} = approve!(conn, authorize_params(tenant, challenge))
      %{code: code, verifier: verifier}
    end

    test "a wrong verifier", %{tenant: tenant, code: code} do
      {other, _} = pkce()
      assert %{"error" => "invalid_grant"} = exchange(tenant, code, other) |> json_response(400)
      refute Repo.exists?(Grant)
    end

    test "a replayed code, and revokes what the first use made", %{tenant: tenant, code: code, verifier: verifier} do
      tokens = exchange(tenant, code, verifier) |> json_response(200)
      assert %{"error" => "invalid_grant"} = exchange(tenant, code, verifier) |> json_response(400)
      assert %Grant{revoked_reason: "code_reuse"} = Repo.one!(Grant)
      assert rpc(tenant, tokens["access_token"], "ping").status == 401
    end

    test "another redirect_uri", %{tenant: tenant, code: code, verifier: verifier} do
      response = exchange(tenant, code, verifier, %{"redirect_uri" => "http://127.0.0.1:9999/callback"})
      assert %{"error" => "invalid_grant"} = json_response(response, 400)
    end

    test "another client", %{tenant: tenant, code: code, verifier: verifier} do
      response = exchange(tenant, code, verifier, %{"client_id" => other_client_id()})
      assert %{"error" => "invalid_grant"} = json_response(response, 400)
    end

    test "another resource", %{tenant: tenant, code: code, verifier: verifier} do
      response = exchange(tenant, code, verifier, %{"resource" => "https://elsewhere.example/mcp"})
      assert %{"error" => "invalid_target"} = json_response(response, 400)
    end

    test "an expired code", %{tenant: tenant, code: code, verifier: verifier} do
      Repo.update_all(AuthorizationCode, set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)])
      assert %{"error" => "invalid_grant"} = exchange(tenant, code, verifier) |> json_response(400)
    end

    test "a client with a secret", %{tenant: tenant, code: code, verifier: verifier} do
      response = exchange(tenant, code, verifier, %{"client_secret" => "s3cret"})
      assert %{"error" => "invalid_client"} = json_response(response, 401)
    end

    test "a user who lost the permission in between", %{
      tenant: tenant,
      code: code,
      verifier: verifier,
      current_user: user
    } do
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :editor])
      assert %{"error" => "invalid_grant"} = exchange(tenant, code, verifier) |> json_response(400)
    end

    test "a JSON body", %{tenant: tenant, code: code, verifier: verifier} do
      response =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          tenant.path <> "/oauth/token",
          Jason.encode!(%{grant_type: "authorization_code", code: code, code_verifier: verifier})
        )

      assert json_response(response, 400)["error"] == "invalid_request"
    end
  end

  describe "the consent screen" do
    test "refuses PKCE without S256, at the client's redirect URI", %{conn: conn, tenant: tenant} do
      params = authorize_params(tenant, "x", %{"code_challenge_method" => "plain"})
      assert {:error, {:redirect, %{to: url}}} = consent(conn, params)
      assert %{"error" => "invalid_request", "state" => "xyz"} = URI.decode_query(URI.parse(url).query)

      {_, challenge} = pkce()
      params = authorize_params(tenant, challenge) |> Map.delete("code_challenge_method")
      assert {:error, {:redirect, %{to: url}}} = consent(conn, params)
      assert %{"error" => "invalid_request"} = URI.decode_query(URI.parse(url).query)
    end

    test "does not send anyone to a redirect URI the client did not declare", %{conn: conn, tenant: tenant} do
      {_, challenge} = pkce()

      for uri <- ["https://evil.example/callback", "http://127.0.0.1:43123/other", "http://192.168.1.2/callback"] do
        {:ok, _view, html} = consent(conn, authorize_params(tenant, challenge, %{"redirect_uri" => uri}))
        assert html =~ ~s(data-testid="mcp-consent-error")
        refute html =~ "mcp-consent-approve"
      end
    end

    test "refuses a client whose document cannot be read", %{conn: conn, tenant: tenant} do
      {_, challenge} = pkce()
      params = authorize_params(tenant, challenge, %{"client_id" => "https://unknown.example/c.json"})
      {:ok, _view, html} = consent(conn, params)
      assert html =~ ~s(data-testid="mcp-consent-error")

      params = authorize_params(tenant, challenge, %{"client_id" => "http://client.example/oauth/client.json"})
      {:ok, _view, html} = consent(conn, params)
      assert html =~ ~s(data-testid="mcp-consent-error")
    end

    test "is 404 for another resource or with the endpoint off", %{conn: conn, tenant: tenant} do
      {_, challenge} = pkce()

      assert_not_found(
        get(
          conn,
          "/admin/mcp/authorize?" <>
            URI.encode_query(authorize_params(tenant, challenge, %{"resource" => "https://elsewhere.example/mcp"}))
        )
      )

      switch!(tenant, false)
      assert_not_found(get(conn, "/admin/mcp/authorize?" <> URI.encode_query(authorize_params(tenant, challenge))))
    end

    test "shows a refusal to a user without the permission, and fetches nothing", %{
      conn: conn,
      tenant: tenant,
      current_user: user
    } do
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :editor])
      {_, challenge} = pkce()
      params = authorize_params(tenant, challenge, %{"client_id" => "https://unknown.example/c.json"})
      {:ok, view, html} = consent(conn, params)
      assert html =~ ~s(data-testid="mcp-refusal")
      refute html =~ "mcp-consent-approve"
      render_click(view, "approve", %{})
      assert Repo.aggregate(AuthorizationCode, :count) == 0
    end

    test "shows a refusal to a user without two-factor authentication", %{conn: conn, tenant: tenant, current_user: user} do
      Repo.delete_all(from(s in Brando.Users.Security, where: s.user_id == ^user.id))
      {_, challenge} = pkce()
      {:ok, _view, html} = consent(conn, authorize_params(tenant, challenge))
      assert html =~ ~s(data-testid="mcp-refusal")
      assert html =~ "/admin/users/security"
    end

    test "asks to confirm before approving when the session has not lately", %{conn: conn, tenant: tenant} do
      token = get_session(conn, :user_token)
      hour_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      Repo.update_all(from(t in Brando.Users.UserToken, where: t.token == ^token), set: [confirmed_at: hour_ago])

      {_, challenge} = pkce()
      {:ok, view, _html} = consent(conn, authorize_params(tenant, challenge))
      html = view |> element("[data-testid=mcp-consent-approve]") |> render_click()
      assert html =~ "reauth-modal"
      assert Repo.aggregate(AuthorizationCode, :count) == 0

      assert {:error, {:redirect, %{to: url}}} =
               view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()

      assert URI.decode_query(URI.parse(url).query)["code"]
    end

    test "cancel tells the client the person declined", %{conn: conn, tenant: tenant} do
      {_, challenge} = pkce()
      {:ok, view, _html} = consent(conn, authorize_params(tenant, challenge))
      {:error, {:redirect, %{to: url}}} = view |> element("[data-testid=mcp-consent-deny]") |> render_click()
      assert %{"error" => "access_denied", "state" => "xyz"} = URI.decode_query(URI.parse(url).query)
    end

    test "cannot be framed and sends a visitor to log in", %{tenant: tenant} do
      {_, challenge} = pkce()
      conn = build_conn() |> get("/admin/mcp/authorize?" <> URI.encode_query(authorize_params(tenant, challenge)))
      assert redirected_to(conn) == "/admin/login"
      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    end
  end

  describe "with the endpoint off" do
    test "every route answers as if it did not exist", %{conn: conn, tenant: tenant} do
      tokens = connect!(conn, tenant)
      switch!(tenant, false)

      assert_not_found(build_conn() |> get("/.well-known/oauth-protected-resource/mcp"))
      assert_not_found(build_conn() |> get("/.well-known/oauth-authorization-server/mcp"))
      assert_not_found(rpc(tenant, tokens["access_token"], "ping"))
      assert_not_found(build_conn() |> get("/mcp/oauth/authorize"))
      assert_not_found(oauth_post(tenant, "token", %{"grant_type" => "refresh_token"}))
      assert_not_found(oauth_post(tenant, "revoke", %{"token" => "x"}))

      # And back on, the connection works again.
      switch!(tenant, true)
      assert rpc(tenant, tokens["access_token"], "ping").status == 200
    end

    test "nothing answers under /mcp but the endpoint's own paths", %{tenant: tenant} do
      assert_not_found(build_conn() |> get("/mcp/oauth/register"))
      assert_not_found(build_conn() |> get("/mcp/elsewhere/live"))
      assert_not_found(build_conn() |> get("/.well-known/oauth-protected-resource/mcp/a/b"))
      assert tenant
    end
  end

  describe "tokens are checked at every call" do
    setup %{conn: conn, tenant: tenant} do
      %{tokens: connect!(conn, tenant)}
    end

    test "an expired access token", %{tenant: tenant, tokens: tokens} do
      Repo.update_all(from(t in Token, where: t.kind == :access),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      conn = rpc(tenant, tokens["access_token"], "ping")
      assert conn.status == 401
      assert [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ ~s(error="invalid_token")
    end

    test "a refresh token is not an access token", %{tenant: tenant, tokens: tokens} do
      assert rpc(tenant, tokens["refresh_token"], "ping").status == 401
    end

    test "a token in the query string is not read", %{tenant: tenant, tokens: tokens} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          tenant.path <> "?access_token=" <> tokens["access_token"],
          Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"})
        )

      assert conn.status == 401
    end

    test "a permission taken away stops the next call", %{tenant: tenant, tokens: tokens, current_user: user} do
      assert rpc(tenant, tokens["access_token"], "ping").status == 200
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :editor])
      conn = rpc(tenant, tokens["access_token"], "ping")
      assert conn.status == 403
      assert [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ ~s(error="insufficient_scope")
    end

    test "turning two-factor authentication off revokes the connection", %{
      tenant: tenant,
      tokens: tokens,
      current_user: user
    } do
      assert :ok = Brando.Users.TwoFactor.disable(user, "admin")
      assert %Grant{revoked_reason: "two_factor_off"} = Repo.one!(Grant)
      assert rpc(tenant, tokens["access_token"], "ping").status == 401
    end

    test "two-factor authentication gone in any other way stops the next call", %{
      tenant: tenant,
      tokens: tokens,
      current_user: user
    } do
      Repo.delete_all(from(s in Brando.Users.Security, where: s.user_id == ^user.id))
      assert rpc(tenant, tokens["access_token"], "ping").status == 401
    end

    test "a deactivated user", %{tenant: tenant, tokens: tokens, current_user: user} do
      {:ok, _} = Brando.Users.update_user(user, %{active: false}, :system)
      assert %Grant{revoked_reason: "account_deactivated"} = Repo.one!(Grant)
      assert rpc(tenant, tokens["access_token"], "ping").status == 401
    end

    test "refresh is refused once the user may no longer connect", %{tenant: tenant, tokens: tokens, current_user: user} do
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :editor])

      response =
        oauth_post(tenant, "token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => tokens["refresh_token"],
          "client_id" => client_id()
        })

      assert json_response(response, 400)["error"] == "invalid_grant"
    end
  end
end
