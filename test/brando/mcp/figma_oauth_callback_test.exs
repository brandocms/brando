defmodule Brando.MCP.FigmaOAuthCallbackTest do
  # Connecting Figma with OAuth, through the router: the authorization
  # request Brando.Figma.OAuth.start/3 makes, and Figma's callback to the
  # admin, with a stubbed Figma. Without tenancy (and with the admin mounted
  # elsewhere), in single-site mode, and in multi-site mode with two
  # environments behind one admin host.
  use Brando.LiveCase, async: false

  import Brando.FigmaOAuthHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Environment
  alias Brando.Figma
  alias Brando.Figma.OAuth
  alias Brando.MCP
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache

  @callback_path "/admin/config/mcp/figma/callback"

  defp session_id(conn), do: Brando.Users.token_id(get_session(conn, :user_token))

  # Starts connecting `tenant` in `conn`'s session; Figma's authorization
  # request as a map
  defp start!(conn, tenant, user) do
    assert {:ok, url} = OAuth.start(tenant, user, session_id(conn))
    URI.decode_query(URI.parse(url).query)
  end

  defp stub_figma_ok(handle \\ "Ada Designer") do
    stub_figma(fn
      "POST", "/v1/oauth/token", _ ->
        {200,
         %{
           "access_token" => "access-1",
           "refresh_token" => "refresh-1",
           "expires_in" => 7_776_000,
           "token_type" => "bearer",
           "user_id_string" => "42"
         }}

      "GET", "/v1/me", _ ->
        {200, %{"id" => "42", "handle" => handle, "email" => "ada@example.com"}}
    end)
  end

  defp callback(conn, params, path \\ @callback_path), do: get(conn, path <> "?" <> URI.encode_query(params))

  defp outcome(conn) do
    %URI{path: path, query: query} = URI.parse(redirected_to(conn))
    {path, URI.decode_query(query || "")["figma"]}
  end

  defp activity do
    Repo.all(from e in Brando.Activity.Event, where: e.schema == "Elixir.Brando.MCP.Setting", select: e.details)
  end

  describe "without tenancy" do
    setup %{current_user: user} do
      tenant = MCP.tenant(nil, nil)
      app!(tenant, user)
      %{tenant: tenant}
    end

    test "connects: the code is exchanged with PKCE, the app's credentials and the same redirect URL, and the account's handle saved",
         %{conn: conn, tenant: tenant, current_user: user} do
      request = start!(conn, tenant, user)
      stub_figma_ok()

      response = callback(conn, %{"state" => request["state"], "code" => "code-1"})
      assert outcome(response) == {"/admin/config/mcp", "connected"}
      assert get_resp_header(response, "cache-control") == ["no-store"]

      assert_received {:figma, "POST", "/v1/oauth/token", form, %{"authorization" => "Basic " <> basic}}
      assert Base.decode64!(basic) == client_id() <> ":" <> client_secret()

      assert %{
               "grant_type" => "authorization_code",
               "code" => "code-1",
               "redirect_uri" => redirect_uri,
               "code_verifier" => verifier
             } = form

      assert redirect_uri == request["redirect_uri"]
      assert redirect_uri == OAuth.redirect_url()
      assert Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false) == request["code_challenge"]

      assert_received {:figma, "GET", "/v1/me", _, %{"authorization" => "Bearer access-1"}}

      assert %{state: :connected, handle: "Ada Designer", connected_by: %{id: user_id}} = OAuth.status(tenant)
      assert user_id == user.id
      assert decrypted(tenant, :access_token) == {:ok, "access-1"}
      assert decrypted(tenant, :refresh_token) == {:ok, "refresh-1"}
      assert DateTime.diff(setting(tenant).figma_oauth_expires_at, DateTime.utc_now()) > 7_000_000
      assert setting(tenant).figma_oauth_state_hash == nil
      assert Figma.credential(tenant) == {:ok, {:oauth, tenant}}

      assert Enum.any?(activity(), &(&1["figma_oauth"] == "connected"))
      encoded = inspect(activity())
      for secret <- ["access-1", "refresh-1", client_secret(), "ada@example.com"], do: refute(encoded =~ secret)
    end

    test "a state is used once", %{conn: conn, tenant: tenant, current_user: user} do
      request = start!(conn, tenant, user)
      stub_figma_ok()

      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "connected"
      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-2"})) |> elem(1) == "unknown"
      assert outcome(callback(conn, %{"state" => "made-up", "code" => "code-2"})) |> elem(1) == "unknown"
    end

    test "a state past its ten minutes saves nothing, and a new attempt works", %{
      conn: conn,
      tenant: tenant,
      current_user: user
    } do
      request = start!(conn, tenant, user)

      setting = setting(tenant)
      {:ok, json} = Brando.Crypto.decrypt(setting.figma_oauth_pending, "mcp.figma_pending:0:0")
      pending = Jason.decode!(json)
      assert (pending["expires_at"] - System.system_time(:second)) in 595..600

      late = Jason.encode!(%{pending | "expires_at" => System.system_time(:second) - 1})
      Repo.update_all(MCP.Setting, set: [figma_oauth_pending: Brando.Crypto.encrypt(late, "mcp.figma_pending:0:0")])

      stub_figma_ok()
      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "expired"
      refute_received {:figma, _, _, _, _}
      assert no_connection?(tenant)
      assert setting(tenant).figma_oauth_state_hash == nil

      request = start!(conn, tenant, user)
      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "connected"
    end

    test "is bound to the session that started it: another session of the same person gets nothing, and leaves it be",
         %{conn: conn, tenant: tenant, current_user: user} do
      request = start!(conn, tenant, user)
      stub_figma_ok()

      other_session = Brando.Test.log_in_user(admin_conn(), user)
      assert outcome(callback(other_session, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "unknown"
      refute_received {:figma, _, _, _, _}

      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "connected"
    end

    test "is bound to the person: another administrator's session gets nothing", %{
      conn: conn,
      tenant: tenant,
      current_user: user
    } do
      request = start!(conn, tenant, user)
      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})

      other_conn = Brando.Test.log_in_user(admin_conn(), other)
      assert outcome(callback(other_conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "unknown"
      assert no_connection?(tenant)
    end

    test "checks again that the person may manage the settings", %{conn: conn, tenant: tenant, current_user: user} do
      request = start!(conn, tenant, user)
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :user])
      stub_figma_ok()

      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "forbidden"
      refute_received {:figma, _, _, _, _}
      assert no_connection?(tenant)
    end

    test "saves nothing when the app changed meanwhile", %{conn: conn, tenant: tenant, current_user: user} do
      request = start!(conn, tenant, user)
      :ok = OAuth.put_app(tenant, client_id(), "a-new-client-secret", user)
      stub_figma_ok()

      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "changed"
      refute_received {:figma, _, _, _, _}
      assert no_connection?(tenant)
    end

    test "saves nothing when another connection was made meanwhile, or the one it set out to replace removed",
         %{conn: conn, tenant: tenant, current_user: user} do
      stub_figma_ok()

      request = start!(conn, tenant, user)
      connect!(tenant, access: "made-meanwhile")
      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "changed"
      assert decrypted(tenant, :access_token) == {:ok, "made-meanwhile"}

      # Reconnecting, and disconnected meanwhile
      request = start!(conn, tenant, user)
      :ok = OAuth.disconnect(tenant, user)
      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "changed"
      assert no_connection?(tenant)
      refute_received {:figma, "POST", _, _, _}
    end

    test "a connection removed while Figma exchanged the code is not brought back",
         %{conn: conn, tenant: tenant, current_user: user} do
      request = start!(conn, tenant, user)
      test = self()

      stub_figma(fn
        "POST", "/v1/oauth/token", _ ->
          # The app is removed while the code is being exchanged
          send(test, :exchanging)
          :ok = OAuth.delete_app(tenant, user)
          {200, %{"access_token" => "access-1", "refresh_token" => "refresh-1", "expires_in" => 60}}

        "GET", "/v1/me", _ ->
          {200, %{"handle" => "Ada"}}
      end)

      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "changed"
      assert_received :exchanging
      assert OAuth.status(tenant) == nil
      assert no_connection?(tenant)
    end

    test "a refused consent leaves nothing behind, and a new attempt works", %{
      conn: conn,
      tenant: tenant,
      current_user: user
    } do
      request = start!(conn, tenant, user)

      assert outcome(callback(conn, %{"state" => request["state"], "error" => "access_denied"})) |> elem(1) == "denied"
      assert setting(tenant).figma_oauth_state_hash == nil
      assert no_connection?(tenant)

      request = start!(conn, tenant, user)
      stub_figma_ok()
      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "connected"
    end

    test "a code Figma does not exchange, or an account it does not show, saves nothing",
         %{conn: conn, tenant: tenant, current_user: user} do
      request = start!(conn, tenant, user)
      stub_figma(fn "POST", "/v1/oauth/token", _ -> {400, %{"error" => true, "message" => "Invalid code"}} end)
      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "exchange_failed"
      assert no_connection?(tenant)

      request = start!(conn, tenant, user)

      stub_figma(fn
        "POST", "/v1/oauth/token", _ -> {200, %{"access_token" => "access-1", "refresh_token" => "refresh-1"}}
        "GET", "/v1/me", _ -> {500, %{"status" => 500}}
      end)

      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) |> elem(1) == "account_failed"
      assert no_connection?(tenant)
      refute inspect(setting(tenant)) =~ "access-1"
    end

    test "needs a signed-in person", %{tenant: tenant, conn: conn, current_user: user} do
      request = start!(conn, tenant, user)
      response = callback(admin_conn(), %{"state" => request["state"], "code" => "code-1"})
      assert redirected_to(response) =~ "/admin/login"
      assert no_connection?(tenant)
    end

    test "with the admin mounted elsewhere, the redirect URL and the way back follow it",
         %{conn: conn, tenant: tenant, current_user: user} do
      router = Brando.Test.AdminHostScopedRouter
      put_test_env(:router_module, router)

      assert OAuth.redirect_url() == MCP.base_url() <> "/cms/admin/config/mcp/figma/callback"
      request = start!(conn, tenant, user)
      assert request["redirect_uri"] == OAuth.redirect_url()
      stub_figma_ok()

      response =
        :get
        |> Plug.Test.conn(
          "/cms/admin/config/mcp/figma/callback?" <> URI.encode_query(%{"state" => request["state"], "code" => "c"})
        )
        |> Plug.Test.init_test_session(%{user_token: get_session(conn, :user_token)})
        |> router.call(router.init([]))

      assert outcome(response) == {"/cms/admin/config/mcp", "connected"}
      assert_received {:figma, "POST", "/v1/oauth/token", %{"redirect_uri" => redirect_uri}, _}
      assert redirect_uri == MCP.base_url() <> "/cms/admin/config/mcp/figma/callback"
      assert %{state: :connected} = OAuth.status(tenant)
    end
  end

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

  describe "in multi-site mode, two environments behind one admin host" do
    setup %{current_user: user} do
      put_test_env(:tenancy_mode, :multi)
      Cache.clear()
      on_exit(&Cache.clear/0)

      acme = insert_site!("acme")
      insert_environment!(acme, "production")
      insert_environment!(acme, "staging")
      Cache.warm()

      production = MCP.tenant(Cache.get_site("acme"), Cache.get_env("acme", "production"))
      staging = MCP.tenant(Cache.get_site("acme"), Cache.get_env("acme", "staging"))

      # Each environment has its own app
      app!(production, user, "production-client-id", "production-secret")
      app!(staging, user, "staging-client-id", "staging-secret")

      %{production: production, staging: staging}
    end

    test "each environment's app has the admin host's redirect URL, and the callback connects the environment that started",
         %{conn: conn, production: production, staging: staging, current_user: user} do
      # The person's session is in production meanwhile
      conn = Plug.Test.init_test_session(conn, %{"brando_site_key" => "acme", "brando_environment_key" => "production"})

      staging_request = start!(conn, staging, user)
      production_request = start!(conn, production, user)
      assert staging_request["redirect_uri"] == production_request["redirect_uri"]
      assert URI.parse(staging_request["redirect_uri"]).host == BrandoAdmin.AdminHost.endpoint_host()
      assert staging_request["client_id"] == "staging-client-id"

      stub_figma_ok()
      response = callback(conn, %{"state" => staging_request["state"], "code" => "code-1"})
      assert outcome(response) == {"/admin/config/mcp", "connected"}
      assert_received {:figma, "POST", "/v1/oauth/token", _, %{"authorization" => "Basic " <> basic}}
      assert Base.decode64!(basic) == "staging-client-id:staging-secret"

      assert %{state: :connected} = OAuth.status(staging)
      assert %{state: :none} = OAuth.status(production)
      # Back in the environment it connected
      assert get_session(response, "brando_environment_key") == "staging"

      # Production's own attempt is still there for it
      response = callback(conn, %{"state" => production_request["state"], "code" => "code-2"})
      assert outcome(response) |> elem(1) == "connected"
      assert %{state: :connected} = OAuth.status(production)
    end

    test "the tokens of one environment do not decrypt as another's", %{production: production, staging: staging} do
      connect!(staging, access: "staging-access")
      ciphertext = setting(staging).figma_oauth_access_token
      Repo.update_all(MCP.setting_query(production), set: [figma_oauth_access_token: ciphertext])
      connect!(production)
      Repo.update_all(MCP.setting_query(production), set: [figma_oauth_access_token: ciphertext])

      assert OAuth.connection_state(production) == :needs_repair
      assert OAuth.connection_state(staging) == :connected
    end
  end

  describe "in single-site mode" do
    setup %{current_user: user} do
      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, "acme")
      Cache.clear()
      on_exit(&Cache.clear/0)

      acme = insert_site!("acme")
      insert_environment!(acme, "production")
      Cache.warm()

      tenant = MCP.tenant(Cache.get_site("acme"), Cache.get_env("acme", "production"))
      app!(tenant, user)
      %{tenant: tenant}
    end

    test "connects the site's environment", %{conn: conn, tenant: tenant, current_user: user} do
      request = start!(conn, tenant, user)
      assert request["redirect_uri"] == MCP.base_url() <> @callback_path
      stub_figma_ok()

      assert outcome(callback(conn, %{"state" => request["state"], "code" => "code-1"})) ==
               {"/admin/config/mcp", "connected"}

      assert %{state: :connected, handle: "Ada Designer"} = OAuth.status(tenant)
    end
  end
end
