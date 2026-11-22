defmodule Brando.MCP.FigmaOAuthTest do
  # Figma connected with OAuth (Brando.Figma.OAuth): the site environment's
  # app, which credential a call uses, the authorization request, and the
  # access token's renewal, against a stubbed Figma.
  use Brando.LiveCase

  import Brando.FigmaOAuthHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.Figma
  alias Brando.Figma.OAuth
  alias Brando.MCP

  @token "figd_pasted-token-wxyz"
  @link %{file_key: "35BOzFjfvJHJM6Wm50E3wA", node_id: "1:2"}
  @nodes %{"name" => "File", "nodes" => %{"1:2" => %{"document" => %{"id" => "1:2", "type" => "FRAME"}}}}

  setup %{current_user: user} do
    %{tenant: MCP.tenant(nil, nil), user: user}
  end

  defp activity do
    Repo.all(
      from e in Brando.Activity.Event,
        where: e.schema == "Elixir.Brando.MCP.Setting",
        order_by: [asc: e.id],
        select: e.details
    )
    |> Enum.map(&Map.drop(&1, ["origin", "client"]))
  end

  defp refreshes, do: for({:figma, "POST", "/v1/oauth/refresh", params, headers} <- messages(), do: {params, headers})

  defp messages do
    receive do
      message -> [message | messages()]
    after
      0 -> []
    end
  end

  describe "the app" do
    test "is stored encrypted, with the client id's last four characters, and recorded without its credentials",
         %{tenant: tenant, user: user} do
      app!(tenant, user)

      setting = setting(tenant)
      refute setting.figma_client_id =~ client_id()
      refute setting.figma_client_secret =~ client_secret()
      assert setting.figma_client_id_hint == "AB12"
      assert decrypted(tenant, :client_id) == {:ok, client_id()}
      assert decrypted(tenant, :client_secret) == {:ok, client_secret()}

      assert %{client_hint: "AB12", readable: true, state: :none, set_by: %{id: user_id}} = OAuth.status(tenant)
      assert user_id == user.id

      assert [%{"figma_app" => "added"}] = activity()
      refute inspect(Repo.all(Brando.Activity.Event)) =~ client_secret()
    end

    test "is refused without the permission, or when it does not look like one", %{tenant: tenant, user: user} do
      editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      assert OAuth.put_app(tenant, client_id(), client_secret(), editor) == {:error, :forbidden}
      assert OAuth.put_app(tenant, "short", client_secret(), user) == {:error, :invalid_app}
      assert OAuth.put_app(tenant, client_id(), "has a space in it", user) == {:error, :invalid_app}
      assert OAuth.status(tenant) == nil
    end

    test "saving it leaves a pasted token and its expiry as they are, and calls keep using the token until Figma is connected",
         %{tenant: tenant, user: user} do
      expires_on = Date.add(Figma.today(), 30)
      :ok = MCP.put_figma_token(tenant, @token, user, expires_on: expires_on)
      app!(tenant, user)

      assert %{hint: "wxyz", expires_on: ^expires_on, readable: true} = MCP.figma_token_status(tenant)
      assert Figma.credential(tenant) == {:ok, @token}
    end

    test "the same client id with a new secret keeps the connection; another client id removes it",
         %{tenant: tenant, user: user} do
      tenant |> app!(user) |> connect!()

      :ok = OAuth.put_app(tenant, client_id(), "a-new-client-secret", user)
      assert %{state: :connected} = OAuth.status(tenant)
      assert decrypted(tenant, :client_secret) == {:ok, "a-new-client-secret"}

      :ok = OAuth.put_app(tenant, "another-client-id", "another-secret", user)
      assert %{state: :none, client_hint: "t-id"} = OAuth.status(tenant)
      assert no_connection?(tenant)

      assert [_, %{"figma_app" => "replaced"}, %{"figma_app" => "replaced", "figma_oauth" => "removed"}] = activity()
    end

    test "removing it removes the connection too, and calls use the pasted token again", %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      tenant |> app!(user) |> connect!()
      assert {:ok, {:oauth, _}} = Figma.credential(tenant)

      :ok = OAuth.delete_app(tenant, user)
      assert OAuth.status(tenant) == nil
      assert no_connection?(tenant)
      assert Figma.credential(tenant) == {:ok, @token}
      assert %{"figma_app" => "removed"} = List.last(activity())
    end

    test "disconnecting keeps the app, and calls use the pasted token again", %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      tenant |> app!(user) |> connect!()

      :ok = OAuth.disconnect(tenant, user)
      assert %{state: :none, client_hint: "AB12"} = OAuth.status(tenant)
      assert no_connection?(tenant)
      assert Figma.credential(tenant) == {:ok, @token}
      assert %{"figma_oauth" => "disconnected"} = List.last(activity())

      editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      assert OAuth.disconnect(tenant, editor) == {:error, :forbidden}
      assert OAuth.delete_app(tenant, editor) == {:error, :forbidden}
    end
  end

  describe "which credential a call uses" do
    test "nothing, a pasted token, then the connection once there is one", %{tenant: tenant, user: user} do
      assert {:error, "Figma is not connected" <> _} = Figma.credential(tenant)

      :ok = MCP.put_figma_token(tenant, @token, user)
      assert Figma.credential(tenant) == {:ok, @token}

      tenant |> app!(user) |> connect!()
      assert Figma.credential(tenant) == {:ok, {:oauth, tenant}}
    end

    test "a connection that needs reconnecting stops calls, without moving over to the pasted token",
         %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      tenant |> app!(user) |> connect!()
      Repo.update_all(MCP.Setting, set: [figma_oauth_needs_reconnect: true])

      assert {:error, message} = Figma.credential(tenant)
      assert message =~ "An administrator reconnects Figma under Configuration → Integrations → Connected AI tools."
      assert Figma.check_token(tenant) == :needs_reconnect
    end

    test "a connection that no longer decrypts needs repair, not 'not connected', and the pasted token is not used",
         %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      tenant |> app!(user) |> connect!()
      Repo.update_all(MCP.Setting, set: [figma_oauth_refresh_token: Brando.Crypto.encrypt("x", "another context")])

      assert OAuth.connection_state(tenant) == :needs_repair
      assert %{state: :needs_repair, readable: true} = OAuth.status(tenant)
      assert {:error, message} = Figma.credential(tenant)
      assert message =~ "can no longer be decrypted"
      assert Figma.check_token(tenant) == :needs_repair
    end
  end

  describe "starting a connection" do
    test "asks Figma for the scopes, with PKCE, a state and the redirect URL; the state is stored hashed only",
         %{tenant: tenant, user: user, conn: conn} do
      app!(tenant, user)
      session_id = Brando.Users.token_id(get_session(conn, :user_token))

      assert {:ok, url} = OAuth.start(tenant, user, session_id)
      %URI{scheme: "https", host: "www.figma.com", path: "/oauth", query: query} = URI.parse(url)
      query = URI.decode_query(query)

      assert %{
               "client_id" => "figma-client-id-AB12",
               "redirect_uri" => redirect_uri,
               "scope" => "file_content:read,current_user:read",
               "response_type" => "code",
               "code_challenge_method" => "S256",
               "state" => state,
               "code_challenge" => challenge
             } = query

      assert redirect_uri == OAuth.redirect_url()
      assert redirect_uri == MCP.base_url() <> "/admin/config/mcp/figma/callback"
      assert byte_size(state) >= 43
      assert byte_size(challenge) == 43

      setting = setting(tenant)
      assert setting.figma_oauth_state_hash == :crypto.hash(:sha256, state)
      refute setting.figma_oauth_pending =~ state
      refute inspect(setting) =~ state

      # A new attempt replaces it
      assert {:ok, again} = OAuth.start(tenant, user, session_id)
      refute again == url
      refute setting(tenant).figma_oauth_state_hash == setting.figma_oauth_state_hash
    end

    test "needs an app, the permission and a session", %{tenant: tenant, user: user} do
      assert OAuth.start(tenant, user, 1) == {:error, :no_app}
      app!(tenant, user)
      assert OAuth.start(tenant, user, nil) == {:error, :forbidden}

      editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      assert OAuth.start(tenant, editor, 1) == {:error, :forbidden}
    end
  end

  describe "calls with the connection" do
    setup %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      tenant |> app!(user) |> connect!(access: "access-1", refresh: "refresh-1", expires_in: 3600)
      :ok
    end

    test "send the access token as a Bearer token, never the pasted token", %{tenant: tenant} do
      stub_figma(fn "GET", "/v1/files/" <> _, _params -> {200, @nodes} end)

      assert {:ok, %{file_name: "File"}} = Figma.node({:oauth, tenant}, @link)
      assert_received {:figma, "GET", _, _, %{"authorization" => "Bearer access-1", "x-figma-token" => nil}}
      assert refreshes() == []
    end

    test "a pasted token still goes in X-Figma-Token", %{tenant: tenant} do
      stub_figma(fn "GET", _, _params -> {200, @nodes} end)
      {:ok, token} = Figma.token(tenant)

      assert {:ok, _node} = Figma.node(token, @link)
      assert_received {:figma, "GET", _, _, %{"authorization" => nil, "x-figma-token" => @token}}
    end

    test "renew the access token first when it expires within five minutes, with the app's credentials, and keep the refresh token Figma leaves out",
         %{tenant: tenant} do
      Repo.update_all(MCP.Setting, set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), 240, :second)])
      counter = :counters.new(1, [])

      stub_figma(fn
        "POST", "/v1/oauth/refresh", _params ->
          :counters.add(counter, 1, 1)
          n = :counters.get(counter, 1)
          # Figma's documented answer: a new access token and its lifetime only
          {200, %{"access_token" => "access-#{n + 1}", "token_type" => "bearer", "expires_in" => 200}}

        "GET", _path, _params ->
          {200, @nodes}
      end)

      assert {:ok, _node} = Figma.node({:oauth, tenant}, @link)

      assert [{%{"refresh_token" => "refresh-1"}, %{"authorization" => "Basic " <> basic}}] = refreshes()
      assert Base.decode64!(basic) == client_id() <> ":" <> client_secret()
      assert decrypted(tenant, :access_token) == {:ok, "access-2"}
      assert decrypted(tenant, :refresh_token) == {:ok, "refresh-1"}

      # Lasts 200 seconds: within the margin again, so the next call renews
      # again, with the refresh token kept
      assert {:ok, _node} = Figma.node({:oauth, tenant}, @link)

      assert [
               {:figma, "POST", "/v1/oauth/refresh", %{"refresh_token" => "refresh-1"}, _},
               {:figma, "GET", _, _, %{"authorization" => "Bearer access-3"}}
             ] = messages()

      assert decrypted(tenant, :access_token) == {:ok, "access-3"}
    end

    test "a refresh token Figma does send replaces the stored one", %{tenant: tenant} do
      Repo.update_all(MCP.Setting, set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), 10, :second)])

      stub_figma(fn
        "POST", "/v1/oauth/refresh", _ ->
          {200, %{"access_token" => "access-2", "refresh_token" => "refresh-2", "expires_in" => 7_776_000}}

        "GET", _, _ ->
          {200, @nodes}
      end)

      assert {:ok, _} = Figma.node({:oauth, tenant}, @link)
      assert decrypted(tenant, :refresh_token) == {:ok, "refresh-2"}
      assert DateTime.diff(setting(tenant).figma_oauth_expires_at, DateTime.utc_now()) > 7_000_000
    end

    test "after Figma answers 'expired', renew once and retry that request; each request reads the token again",
         %{tenant: tenant} do
      images_asked = :counters.new(1, [])

      stub_figma(fn
        "POST", "/v1/oauth/refresh", _ ->
          {200, %{"access_token" => "access-2", "expires_in" => 3600}}

        "GET", "/v1/files/35BOzFjfvJHJM6Wm50E3wA/nodes", _ ->
          {200, @nodes}

        "GET", "/v1/files/35BOzFjfvJHJM6Wm50E3wA/images", _ ->
          :counters.add(images_asked, 1, 1)

          if :counters.get(images_asked, 1) == 1,
            do: {403, %{"status" => 403, "err" => "Token expired"}},
            else: {200, %{"meta" => %{"images" => %{"ref" => "https://x"}}}}
      end)

      # Two requests of one call (as an import makes), with one credential
      credential = {:oauth, tenant}
      assert {:ok, _node} = Figma.node(credential, @link)

      assert_received {:figma, "GET", "/v1/files/35BOzFjfvJHJM6Wm50E3wA/nodes", _,
                       %{"authorization" => "Bearer access-1"}}

      # Between them, the stored token changes: the next request reads it
      Repo.update_all(MCP.Setting, set: [figma_oauth_access_token: encrypt("access-1b", tenant, :access_token)])

      # Figma answers it "expired": renewed, and that same request retried
      assert {:ok, %{"ref" => "https://x"}} = Figma.image_urls(credential, @link.file_key)

      assert [
               {:figma, "GET", "/v1/files/35BOzFjfvJHJM6Wm50E3wA/images", _, %{"authorization" => "Bearer access-1b"}},
               {:figma, "POST", "/v1/oauth/refresh", %{"refresh_token" => "refresh-1"}, _},
               {:figma, "GET", "/v1/files/35BOzFjfvJHJM6Wm50E3wA/images", _, %{"authorization" => "Bearer access-2"}}
             ] = messages()
    end

    test "a token another call renewed already is used, with no second refresh", %{tenant: tenant} do
      stub_figma(fn "POST", "/v1/oauth/refresh", _ -> {200, %{"access_token" => "never", "expires_in" => 3600}} end)
      Repo.update_all(MCP.Setting, set: [figma_oauth_access_token: encrypt("access-2", tenant, :access_token)])

      # Figma refused access-1; the row holds access-2 now
      assert OAuth.access_token(tenant, "access-1") == {:ok, "access-2"}
      assert refreshes() == []
    end

    test "a file the account cannot open is not a token problem: no refresh", %{tenant: tenant} do
      stub_figma(fn "GET", _, _ -> {403, %{"status" => 403, "err" => "File not shared"}} end)

      assert {:error, message} = Figma.node({:oauth, tenant}, @link)
      assert message =~ "the connected Figma account cannot open this file"
      assert refreshes() == []
    end

    test "Figma not answering a refresh (timeout, 429, 5xx) keeps everything, and a later call tries again",
         %{tenant: tenant} do
      Repo.update_all(MCP.Setting, set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)])

      for status <- [429, 502, 503] do
        stub_figma(fn "POST", "/v1/oauth/refresh", _ -> {status, %{"error" => "busy"}} end)

        assert {:error, "Figma could not be reached to renew the site's access. Try again in a moment."} =
                 Figma.node({:oauth, tenant}, @link)
      end

      Req.Test.stub(Brando.Figma, &Req.Test.transport_error(&1, :timeout))
      assert {:error, "Figma could not be reached to renew" <> _} = Figma.node({:oauth, tenant}, @link)

      assert %{state: :connected} = OAuth.status(tenant)
      assert decrypted(tenant, :refresh_token) == {:ok, "refresh-1"}
      assert decrypted(tenant, :access_token) == {:ok, "access-1"}

      stub_figma(fn
        "POST", "/v1/oauth/refresh", _ -> {200, %{"access_token" => "access-2", "expires_in" => 3600}}
        "GET", _, _ -> {200, @nodes}
      end)

      assert {:ok, _node} = Figma.node({:oauth, tenant}, @link)
    end

    test "Figma refusing the refresh token marks the connection as needing a reconnect, recorded, and calls say so",
         %{tenant: tenant} do
      Repo.update_all(MCP.Setting, set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)])
      stub_figma(fn "POST", "/v1/oauth/refresh", _ -> {400, %{"error" => "invalid_grant"}} end)

      assert {:error, message} = Figma.node({:oauth, tenant}, @link)
      assert message =~ "Figma refused to renew it"
      assert message =~ "An administrator reconnects Figma"
      assert %{state: :needs_reconnect} = OAuth.status(tenant)
      assert %{"figma_oauth" => "needs_reconnect"} = List.last(activity())

      # Not the pasted token, silently
      assert {:error, ^message} = Figma.credential(tenant)
      refute message =~ @token
    end

    test "a 401 from something in front of Figma, without its error text, is not a refused refresh token",
         %{tenant: tenant} do
      Repo.update_all(MCP.Setting, set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)])

      Req.Test.stub(Brando.Figma, fn conn -> conn |> Plug.Conn.put_status(401) |> Req.Test.html("<h1>Blocked</h1>") end)
      assert {:error, "Figma could not be reached to renew" <> _} = Figma.node({:oauth, tenant}, @link)
      assert %{state: :connected} = OAuth.status(tenant)
    end

    test "no secret reaches an error message or the log", %{tenant: tenant} do
      Repo.update_all(MCP.Setting, set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)])
      stub_figma(fn "POST", "/v1/oauth/refresh", _ -> {401, %{"error" => "invalid_client"}} end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, message} = Figma.node({:oauth, tenant}, @link)
          send(self(), {:message, message})
        end)

      assert_received {:message, message}

      for secret <- [client_secret(), client_id(), "access-1", "refresh-1", @token] do
        refute message =~ secret
        refute log =~ secret
      end
    end
  end
end
