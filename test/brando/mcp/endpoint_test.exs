defmodule Brando.MCP.EndpointTest do
  # The MCP endpoint itself: Streamable HTTP for both protocol eras, every
  # tool over JSON-RPC, Activity, and the limits on origin, size and rate.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Content.Proposals
  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.Pages.Page

  setup %{conn: conn, current_user: user} do
    setup_fetcher()
    enable_two_factor(user)
    tenant = MCP.tenant(nil, nil) |> switch!()
    tokens = connect!(conn, tenant)
    %{tenant: tenant, token: tokens["access_token"]}
  end

  defp modern(tenant, token, method, params, headers \\ []) do
    meta = %{
      "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities" => %{},
      "io.modelcontextprotocol/clientInfo" => %{"name" => "test", "version" => "1"}
    }

    defaults = [{"mcp-method", method}] ++ if(params["name"], do: [{"mcp-name", params["name"]}], else: [])

    rpc(tenant, token, method, Map.put(params, "_meta", meta),
      version: "2026-07-28",
      headers: Enum.uniq_by(headers ++ defaults, &elem(&1, 0))
    )
  end

  describe "the protocol" do
    test "initialize negotiates a legacy version, without a session", %{tenant: tenant, token: token} do
      conn = rpc(tenant, token, "initialize", %{"protocolVersion" => "2025-06-18", "capabilities" => %{}})

      assert %{"result" => %{"protocolVersion" => "2025-06-18", "capabilities" => %{"tools" => _}}} =
               json_response(conn, 200)

      assert get_resp_header(conn, "mcp-session-id") == []

      conn = rpc(tenant, token, "initialize", %{"protocolVersion" => "1999-01-01"})
      assert %{"result" => %{"protocolVersion" => "2025-11-25"}} = json_response(conn, 200)
    end

    test "notifications are accepted without a body", %{tenant: tenant, token: token} do
      conn = rpc(tenant, token, nil, %{}, body: %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
      assert conn.status == 202
      assert conn.resp_body == ""
    end

    test "ping, and unknown methods", %{tenant: tenant, token: token} do
      assert %{"result" => %{}} = rpc(tenant, token, "ping") |> json_response(200)
      assert %{"error" => %{"code" => -32_601}} = rpc(tenant, token, "resources/list") |> json_response(200)
    end

    test "an unsupported legacy version header is refused", %{tenant: tenant, token: token} do
      assert rpc(tenant, token, "ping", %{}, version: "2024-01-01").status == 400
    end

    test "a request without the version header is taken as 2025-03-26", %{tenant: tenant, token: token} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer " <> token)
        |> post_sized(tenant.path, Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))

      assert json_response(conn, 200)["result"] == %{}
    end

    test "modern requests carry their version, and the headers must match the body", %{tenant: tenant, token: token} do
      assert %{"result" => %{"resultType" => "complete", "supportedVersions" => ["2026-07-28" | _]}} =
               modern(tenant, token, "server/discover", %{}) |> json_response(200)

      assert %{"result" => %{"resultType" => "complete", "tools" => [_ | _]}} =
               modern(tenant, token, "tools/list", %{}) |> json_response(200)

      assert %{"error" => %{"code" => -32_020}} =
               modern(tenant, token, "tools/list", %{}, [{"mcp-method", "ping"}]) |> json_response(400)

      assert %{"error" => %{"code" => -32_020}} =
               modern(tenant, token, "tools/call", %{"name" => "brando_content_list_content_types"}, [
                 {"mcp-name", "brando_content_search_entries"}
               ])
               |> json_response(400)

      # A name sent in base64
      encoded = "=?base64?" <> Base.encode64("brando_content_list_content_types") <> "?="

      assert %{"result" => %{"content" => _}} =
               modern(tenant, token, "tools/call", %{"name" => "brando_content_list_content_types"}, [
                 {"mcp-name", encoded}
               ])
               |> json_response(200)

      assert %{"error" => %{"code" => -32_601}} = modern(tenant, token, "prompts/list", %{}) |> json_response(404)
    end

    test "an unsupported modern version lists the supported ones", %{tenant: tenant, token: token} do
      meta = %{
        "io.modelcontextprotocol/protocolVersion" => "2099-01-01",
        "io.modelcontextprotocol/clientCapabilities" => %{}
      }

      conn = rpc(tenant, token, "ping", %{"_meta" => meta}, version: "2099-01-01", headers: [{"mcp-method", "ping"}])
      assert %{"error" => %{"code" => -32_022, "data" => %{"supported" => supported}}} = json_response(conn, 400)
      assert "2026-07-28" in supported
    end

    test "GET and DELETE are not allowed, and batches are refused", %{tenant: tenant, token: token} do
      conn = build_conn() |> put_req_header("authorization", "Bearer " <> token) |> get(tenant.path)
      assert conn.status == 405
      assert get_resp_header(conn, "allow") == ["POST"]
      assert (build_conn() |> delete(tenant.path)).status == 405

      batch = [%{jsonrpc: "2.0", id: 1, method: "ping"}, %{jsonrpc: "2.0", id: 2, method: "ping"}]
      assert %{"error" => %{"code" => -32_600}} = rpc(tenant, token, nil, %{}, body: batch) |> json_response(400)
    end

    test "only JSON is accepted", %{tenant: tenant, token: token} do
      conn =
        build_conn()
        |> put_req_header("content-type", "text/plain")
        |> put_req_header("authorization", "Bearer " <> token)
        |> post_sized(tenant.path, "{}")

      assert conn.status == 415
    end

    test "no CORS headers are sent", %{tenant: tenant, token: token} do
      conn = rpc(tenant, token, "ping")
      assert get_resp_header(conn, "access-control-allow-origin") == []
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "transport hygiene" do
    test "an Origin from elsewhere is refused before the token is looked at", %{tenant: tenant, token: token} do
      assert rpc(tenant, token, "ping", %{}, headers: [{"origin", "https://evil.example"}]).status == 403
      assert rpc(tenant, nil, "ping", %{}, headers: [{"origin", "https://evil.example"}]).status == 403
      # The site's own origin, or a configured one, is fine.
      own = MCP.base_url()
      assert rpc(tenant, token, "ping", %{}, headers: [{"origin", own}]).status == 200
    end

    test "the length is checked from the header, before the token", %{tenant: tenant} do
      body = Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"})

      unsized =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(tenant.path, body)

      assert unsized.status == 411

      # No token at all, and still 413, not 401: nothing past the length is looked at
      oversized =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-length", "600000")
        |> post(tenant.path, body)

      assert oversized.status == 413

      # A Transfer-Encoding beside the length: refused, before the token
      both =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-length", Integer.to_string(byte_size(body)))
        |> put_req_header("transfer-encoding", "chunked")
        |> post(tenant.path, body)

      assert both.status == 400
    end

    test "Brando.MCP.BodyLimit refuses before anything reads the body" do
      conn = fn path, length ->
        Plug.Test.conn("POST", path, "{}")
        |> then(&if(length, do: put_req_header(&1, "content-length", length), else: &1))
        |> Brando.MCP.BodyLimit.call([])
      end

      assert %{status: 411, halted: true} = conn.("/mcp", nil)
      assert %{status: 413, halted: true} = conn.("/mcp/site/env/oauth/token", "600000")
      assert %{halted: false} = conn.("/mcp", "2")

      chunked = Plug.Test.conn("POST", "/mcp", "{}") |> put_req_header("content-length", "2")
      chunked = put_req_header(chunked, "transfer-encoding", "chunked")
      assert %{status: 400, halted: true} = Brando.MCP.BodyLimit.call(chunked, [])
      assert %{halted: false} = conn.("/elsewhere", nil)
    end

    test "a modern request without Mcp-Method is refused", %{tenant: tenant, token: token} do
      meta = %{
        "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities" => %{}
      }

      conn = rpc(tenant, token, "tools/list", %{"_meta" => meta}, version: "2026-07-28")
      assert %{"error" => %{"code" => -32_020}} = json_response(conn, 400)
    end

    test "oversized requests are refused", %{tenant: tenant, token: token} do
      put_test_env(MCP, client_metadata_fetcher: {Brando.MCPHelpers, :fetch}, max_request_bytes: 2_000)
      big = String.duplicate("x", 3_000)

      conn =
        rpc(tenant, token, "tools/call", %{"name" => "brando_content_search_entries", "arguments" => %{"query" => big}})

      assert conn.status == 413
    end

    test "requests over the limits get 429", %{tenant: tenant, token: token} do
      put_test_env(MCP, client_metadata_fetcher: {Brando.MCPHelpers, :fetch}, requests_per_minute: 3)
      assert Enum.map(1..3, fn _ -> rpc(tenant, token, "ping").status end) == [200, 200, 200]
      conn = rpc(tenant, token, "ping")
      assert conn.status == 429
      assert [_] = get_resp_header(conn, "retry-after")
    end

    test "a person's connections share a limit", %{conn: conn, tenant: tenant, token: token} do
      put_test_env(MCP, client_metadata_fetcher: {Brando.MCPHelpers, :fetch}, user_requests_per_minute: 2)
      other = connect!(conn, tenant)["access_token"]
      assert rpc(tenant, token, "ping").status == 200
      assert rpc(tenant, other, "ping").status == 200
      assert rpc(tenant, other, "ping").status == 429
    end

    test "the token endpoint is rate limited per address", %{tenant: tenant} do
      put_test_env(MCP, client_metadata_fetcher: {Brando.MCPHelpers, :fetch}, token_requests_per_minute: 2)
      Brando.RateLimit.reset(&match?({Brando.MCP, _}, &1))
      params = %{"grant_type" => "refresh_token", "refresh_token" => "x", "client_id" => client_id()}
      assert oauth_post(tenant, "token", params).status == 400
      assert oauth_post(tenant, "token", params).status == 400
      assert oauth_post(tenant, "token", params).status == 429
    end
  end

  describe "the tools" do
    setup do
      c = Brando.ProposalFixtures.context()
      Enum.each([c.identity, c.naming], &Brando.Content.create_identifier(Page, &1))
      c
    end

    test "are the content tools that read and propose, and nothing that applies", %{tenant: tenant, token: token} do
      %{"result" => %{"tools" => tools}} = rpc(tenant, token, "tools/list") |> json_response(200)
      names = Enum.map(tools, & &1["name"])

      assert names == Enum.map(MCP.Tools.offered(), &("brando_content_" <> &1))
      refute Enum.any?(names, &(&1 =~ ~r/apply|approve|delete|attach_folder/))

      assert %{"readOnlyHint" => false, "destructiveHint" => false} =
               Enum.find(tools, &(&1["name"] =~ "prepare")) |> Map.get("annotations")
    end

    test "each one answers over JSON-RPC", %{tenant: tenant, token: token} = c do
      page = %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id}

      calls = [
        {"list_content_types", %{}},
        {"describe_content_type", %{"content_type" => "Brando.Pages.Page"}},
        {"search_entries", %{"query" => "Identity", "content_type" => "Brando.Pages.Page"}},
        {"entry_outline", page},
        {"list_modules", %{"content_type" => "Brando.Pages.Page"}},
        {"describe_module", %{"module" => "local:#{c.case_module.id}"}},
        {"list_entry_media", page},
        {"search_assets", %{"kind" => "image"}},
        {"find_media_folders", %{"kind" => "image", "name" => "x"}}
      ]

      for {name, args} <- calls do
        assert %{"result" => %{"content" => [%{"type" => "text"}]} = result} = call_tool(tenant, token, name, args)
        refute result["isError"], "#{name}: #{inspect(result)}"
      end

      # A datasource question about a module without one is an error result, not a crash.
      assert %{"result" => %{"isError" => true}} =
               call_tool(tenant, token, "list_selection_options", %{"module" => "local:#{c.case_module.id}"})

      %{"result" => %{"structuredContent" => found}} =
        call_tool(tenant, token, "search_entries", %{"query" => "Identity", "content_type" => "Brando.Pages.Page"})

      assert Enum.any?(found["entries"], &(&1["id"] == c.identity.id))
    end

    test "prepare_proposal stores a proposal from the client, to review in the admin",
         %{tenant: tenant, token: token} = c do
      op = %{
        "op" => "insert_block",
        "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
        "module" => "local:#{c.case_module.id}",
        "values" => %{"heading" => "From MCP"}
      }

      %{"result" => %{"structuredContent" => review}} =
        call_tool(tenant, token, "prepare_proposal", %{"summary" => "Add a case", "operations" => [op]})

      assert review["review_url"] =~ "/admin/assistant/connected/"
      assert {:ok, proposal} = Proposals.get(review["proposal_id"], c.current_user)
      assert %{origin: "mcp", client: "Test Client", status: "pending"} = proposal
    end

    test "tools the endpoint does not offer are unknown", %{tenant: tenant, token: token} do
      for name <- ["attach_folder", "list_attachments", "apply_proposal"] do
        assert %{"error" => %{"code" => -32_602}} = call_tool(tenant, token, name, %{})
      end
    end

    test "every call is in Activity with the person, the client and the token's id",
         %{tenant: tenant, token: token} = c do
      call_tool(tenant, token, "list_content_types")
      call_tool(tenant, token, "describe_module", %{"module" => "local:0"})

      events = Repo.all(from e in Event, where: e.action == :tool_called, order_by: e.id)
      grant = Repo.one!(Grant)

      assert [
               %{source: :mcp, details: %{"tool" => "list_content_types", "ok" => true} = details},
               %{details: %{"tool" => "describe_module", "ok" => false}}
             ] = events

      assert Enum.all?(events, &(&1.user_id == c.current_user.id and &1.entry_id == grant.id))
      assert details["client"] == "Test Client"
      assert is_integer(details["token"])
      refute inspect(Enum.map(events, & &1.details)) =~ token
      refute inspect(Enum.map(events, & &1.details)) =~ "bmcp_"
    end
  end
end
