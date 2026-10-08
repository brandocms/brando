defmodule Brando.MCP.TenancyTest do
  # A connection belongs to one site environment: its token works only at
  # that environment's endpoint, whatever ids or paths a client tries. And
  # with group authorization, the Connected AI tools permission decides.
  use Brando.ConnCase, async: false

  import Brando.MCPHelpers

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Environments.Environment
  alias Brando.Factory
  alias Brando.MCP
  alias Brando.MCP.OAuth
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache

  defp insert_site!(key) do
    %Site{}
    |> Site.changeset(%{
      name: String.capitalize(key),
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    })
    |> Repo.insert!()
  end

  defp insert_environment!(site, key) do
    %Environment{}
    |> Environment.changeset(%{site_id: site.id, name: String.capitalize(key), key: key, live: key == "production"})
    |> Repo.insert!()
  end

  # A connection made through the consent screen's own functions
  defp connect_directly(user, tenant) do
    {verifier, challenge} = pkce()
    params = authorize_params(tenant, challenge)
    {:ok, request} = OAuth.validate(params, user)
    {:ok, url} = OAuth.approve(request, user)
    %{"code" => code} = URI.decode_query(URI.parse(url).query)

    {:ok, tokens} =
      OAuth.token(
        %{
          "grant_type" => "authorization_code",
          "code" => code,
          "code_verifier" => verifier,
          "client_id" => client_id(),
          "redirect_uri" => redirect_uri()
        },
        tenant
      )

    tokens
  end

  describe "with sites" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      Cache.clear()
      on_exit(&Cache.clear/0)
      setup_fetcher()

      acme = insert_site!("acme")
      other = insert_site!("other")
      acme_production = insert_environment!(acme, "production")
      acme_staging = insert_environment!(acme, "staging")
      other_production = insert_environment!(other, "production")
      Cache.warm()

      user = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{}) |> enable_two_factor()

      tenants =
        for {site, environment} <- [{acme, acme_production}, {acme, acme_staging}, {other, other_production}] do
          MCP.tenant(Cache.get_site(site.key), Cache.get_env(site.key, environment.key)) |> switch!()
        end

      %{user: user, tenants: tenants}
    end

    test "each environment has its own endpoint, metadata and issuer", %{tenants: [acme | _]} do
      assert acme.path == "/mcp/acme/production"
      prm = build_conn() |> get("/.well-known/oauth-protected-resource/mcp/acme/production") |> json_response(200)
      assert prm["resource"] == MCP.base_url() <> "/mcp/acme/production"
      assert prm["resource_name"] =~ "Acme"

      as = build_conn() |> get("/.well-known/oauth-authorization-server/mcp/acme/production") |> json_response(200)
      assert as["issuer"] == prm["resource"]

      # Without tenancy's path, nothing
      assert_not_found(build_conn() |> get("/.well-known/oauth-protected-resource/mcp"))
      assert_not_found(rpc(%{path: "/mcp"}, nil, "ping"))
    end

    test "a token works only where it was issued", %{user: user, tenants: [acme, staging, other]} do
      tokens = connect_directly(user, acme)
      assert rpc(acme, tokens["access_token"], "ping").status == 200
      assert rpc(staging, tokens["access_token"], "ping").status == 401
      assert rpc(other, tokens["access_token"], "ping").status == 401

      # Nor does its refresh token, at another environment's token endpoint
      response =
        oauth_post(other, "token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => tokens["refresh_token"],
          "client_id" => client_id()
        })

      assert json_response(response, 400)["error"] == "invalid_grant"

      # Nor can another environment's revocation endpoint end it
      oauth_post(other, "revoke", %{"token" => tokens["access_token"], "client_id" => client_id()})
      assert rpc(acme, tokens["access_token"], "ping").status == 200
    end

    test "a code is exchanged only at its own environment", %{user: user, tenants: [acme, staging, _other]} do
      {verifier, challenge} = pkce()
      {:ok, request} = OAuth.validate(authorize_params(acme, challenge), user)
      {:ok, url} = OAuth.approve(request, user)
      %{"code" => code} = URI.decode_query(URI.parse(url).query)

      assert %{"error" => "invalid_target"} =
               exchange(staging, code, verifier, %{"resource" => MCP.resource(acme)}) |> json_response(400)

      assert %{"error" => "invalid_grant"} =
               exchange(staging, code, verifier, %{"resource" => MCP.resource(staging)}) |> json_response(400)
    end

    test "turning one environment off leaves the others on", %{user: user, tenants: [acme, staging, _other]} do
      tokens = connect_directly(user, staging)
      switch!(acme, false)
      assert_not_found(build_conn() |> get("/.well-known/oauth-protected-resource/mcp/acme/production"))
      assert rpc(staging, tokens["access_token"], "ping").status == 200
    end

    test "a site the user has no access to cannot be connected", %{tenants: [acme | _]} do
      admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{}) |> enable_two_factor()
      {_, challenge} = pkce()
      assert {:error, {:refused, :permission, _}} = OAuth.validate(authorize_params(acme, challenge), admin)
    end

    test "resources are matched exactly", %{tenants: [acme | _]} do
      base = MCP.base_url()
      assert {:ok, ^acme} = MCP.tenant_for_resource(base <> "/mcp/acme/production")
      assert {:ok, ^acme} = MCP.tenant_for_resource(String.upcase(base) <> "/mcp/acme/production")

      for bad <- [
            base <> "/mcp/acme/production/",
            base <> "/mcp/acme/production?x=1",
            base <> "/mcp/acme/production#x",
            base <> "/mcp/acme",
            base <> "/mcp/acme/nowhere",
            base <> "/mcp//acme/production",
            "https://elsewhere.example/mcp/acme/production",
            nil
          ] do
        assert MCP.tenant_for_resource(bad) == :error, inspect(bad)
      end
    end
  end

  describe "with group authorization" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      setup_fetcher()
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{}) |> enable_two_factor()
      {:ok, _} = Migration.run()
      %{owner: owner, user: user, scope: Scope.standalone(owner), tenant: MCP.tenant(nil, nil) |> switch!()}
    end

    defp grant(c, keys) do
      {:ok, group} = Groups.create(c.scope, %{name: "MCP #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
      group
    end

    test "connecting takes brando.mcp.connect; the assistant does not imply it", c do
      grant(c, ["brando.admin.access", "brando.assistant.use"])
      assert MCP.refusal(c.user, c.tenant) == :permission

      group = grant(c, ["brando.admin.access", "brando.mcp.connect"])
      assert MCP.refusal(c.user, c.tenant) == nil
      refute MCP.can_manage?(c.user, c.tenant)

      tokens = connect_directly(c.user, c.tenant)
      assert rpc(c.tenant, tokens["access_token"], "ping").status == 200

      # Taken away mid-session: the next call is refused.
      {:ok, _} = Groups.remove_member(c.scope, group.id, c.user.id)
      assert rpc(c.tenant, tokens["access_token"], "ping").status == 403
    end

    test "no preset group gets brando.mcp.connect" do
      for preset <- [:admin, :editor], kind <- [:standalone, :site] do
        refute "brando.mcp.connect" in Brando.Authorization.Catalog.preset_permissions(preset, kind)
      end

      assert "brando.mcp.manage" in Brando.Authorization.Catalog.preset_permissions(:admin, :standalone)
    end
  end
end
