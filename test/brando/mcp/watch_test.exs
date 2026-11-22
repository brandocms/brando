defmodule Brando.MCP.WatchTest do
  # Following a connection's calls (Brando.MCP.Watch): what a real call over
  # the endpoint tells the connection's topic and Activity, and where the
  # live page's link reaches the client.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.MCP.Watch
  alias Brando.Pages.Page

  setup %{conn: conn, current_user: user} do
    setup_fetcher()
    enable_two_factor(user)
    tenant = MCP.tenant(nil, nil) |> switch!()
    tokens = connect!(conn, tenant)
    grant = Repo.one!(Grant)
    %{tenant: tenant, token: tokens["access_token"], grant: grant}
  end

  defp proposal_args(c) do
    op = %{
      "op" => "set_fields",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
      "fields" => %{"title" => "Identity, from MCP"}
    }

    %{"summary" => "Retitle", "operations" => [op]}
  end

  defp page_context(_c) do
    c = Brando.ProposalFixtures.context()
    Enum.each([c.identity, c.naming], &Brando.Content.create_identifier(Page, &1))
    c
  end

  describe "a tool call over the endpoint" do
    test "is told to the connection's topic as it starts and where it is written to Activity",
         %{tenant: tenant, token: token, grant: grant} do
      Watch.subscribe(grant.id)

      call_tool(tenant, token, "search_entries", %{"query" => "Identity", "content_type" => "Brando.Pages.Page"})

      assert_receive {Watch, %{state: :running, id: id, tool: "search_entries"} = started}
      assert started.details == %{"input" => %{"query" => "Identity", "content_type" => "Brando.Pages.Page"}}

      assert_receive {Watch, %{state: :ok, id: ^id, event_id: event_id} = finished}
      event = Repo.get!(Event, event_id)

      assert %{action: :tool_called, entry_id: entry_id, details: details} = event
      assert entry_id == grant.id
      assert finished.details["input"] == details["input"]
      assert details["tool"] == "search_entries"
    end

    test "a failed call carries its error, cut short", %{tenant: tenant, token: token, grant: grant} do
      Watch.subscribe(grant.id)
      call_tool(tenant, token, "describe_module", %{"module" => "local:0"})

      assert_receive {Watch, %{state: :error, details: %{"error" => error}, event_id: event_id}}
      assert is_binary(error) and error != ""
      assert String.length(error) <= 300
      assert Repo.get!(Event, event_id).details["error"] == error
    end

    test "only the connection's own topic hears it", %{conn: conn, tenant: tenant, token: token, grant: grant} do
      Watch.subscribe(grant.id + 1_000_000)
      call_tool(tenant, token, "list_content_types")
      refute_receive {Watch, _}

      # A second connection of the same person has its own topic
      other = connect!(conn, tenant)
      Watch.subscribe(grant.id)
      call_tool(tenant, other["access_token"], "list_content_types")
      refute_receive {Watch, _}
    end

    test "a proposal is told with its id and preview, and Activity keeps no whole argument",
         %{tenant: tenant, token: token, grant: grant} = c do
      c = Map.merge(c, page_context(c))
      Watch.subscribe(grant.id)

      %{"result" => %{"structuredContent" => review}} =
        call_tool(tenant, token, "prepare_proposal", proposal_args(c))

      assert_receive {Watch, %{state: :ok, tool: "prepare_proposal", details: details}}
      assert details["proposal"] == review["proposal_id"]
      assert details["output"] == %{"version" => 1, "applicable" => true}

      assert details["preview"] ==
               "/admin/assistant/connected/#{review["proposal_id"]}?preview=Brando.Pages.Page:#{c.identity.id}"

      [event] = Repo.all(from e in Event, where: e.action == :tool_called)
      refute inspect(event.details) =~ "Identity, from MCP"
      refute Map.has_key?(event.details["input"] || %{}, "operations")
    end

    test "listing proposals is told with how many, and a cancel with the proposal and its version",
         %{tenant: tenant, token: token, grant: grant} = c do
      c = Map.merge(c, page_context(c))

      %{"result" => %{"structuredContent" => %{"proposal_id" => id}}} =
        call_tool(tenant, token, "prepare_proposal", proposal_args(c))

      Watch.subscribe(grant.id)

      call_tool(tenant, token, "list_proposals")
      assert_receive {Watch, %{state: :ok, tool: "list_proposals", details: listed}}
      assert listed["output"] == %{"proposals" => 1}

      assert BrandoAdmin.Components.ToolSteps.label("list_proposals", %{}, listed["output"]) ==
               [{:text, "Checked 1 of its proposals"}]

      call_tool(tenant, token, "cancel_proposal", %{"proposal_id" => id})
      assert_receive {Watch, %{state: :ok, tool: "cancel_proposal", details: cancelled}}
      assert cancelled["proposal"] == id
      assert cancelled["output"] == %{"version" => 1}

      assert BrandoAdmin.Components.ToolSteps.label("cancel_proposal", %{}, cancelled["output"]) ==
               [{:text, "Cancelled version "}, {:strong, "1"}, {:text, " of a proposal"}]
    end

    test "a proposal replacing an image's file is told with how many it replaces",
         %{tenant: tenant, token: token, grant: grant} do
      old = Brando.ImageFileFixtures.file_image("old", {800, 600})
      new = Brando.ImageFileFixtures.file_image("new", {1600, 1200})
      Watch.subscribe(grant.id)

      op = %{
        "op" => "replace_image_file",
        "asset" => %{"kind" => "image", "id" => old.id},
        "with" => %{"kind" => "image", "id" => new.id}
      }

      %{"result" => %{"structuredContent" => review}} =
        call_tool(tenant, token, "prepare_proposal", %{"summary" => "Better photo", "operations" => [op]})

      assert review["applicable"]
      assert review["effects"]["replaced_images"] == 1

      assert_receive {Watch, %{state: :ok, tool: "prepare_proposal", details: details}}
      assert details["output"] == %{"version" => 1, "applicable" => true, "replaced_images" => 1}

      # The Assistant keeps the whole result, with the count in its effects
      assert BrandoAdmin.Components.ToolSteps.label("prepare_proposal", %{}, review) ==
               BrandoAdmin.Components.ToolSteps.label("prepare_proposal", %{}, details["output"])

      refute BrandoAdmin.Components.ToolSteps.label("prepare_proposal", %{}, details["output"]) ==
               BrandoAdmin.Components.ToolSteps.label("prepare_proposal", %{}, %{"version" => 1, "applicable" => true})
    end
  end

  describe "the link" do
    test "is the last of the server's instructions, for initialize and server/discover",
         %{tenant: tenant, token: token, grant: grant} do
      %{"result" => %{"instructions" => instructions}} =
        rpc(tenant, token, "initialize", %{"protocolVersion" => "2025-06-18"}) |> json_response(200)

      assert String.ends_with?(instructions, Watch.url(grant))
      assert instructions =~ "Give the person this link before you start"
      assert Watch.url(grant) == Brando.endpoint().url() <> "/admin/assistant/connected/live/#{grant.id}"
    end

    test "comes with the first result, and not again until 30 minutes without calls",
         %{tenant: tenant, token: token, grant: grant} do
      url = Watch.url(grant)

      assert %{"result" => %{"structuredContent" => %{"watch_url" => ^url}}} =
               call_tool(tenant, token, "list_content_types")

      %{"result" => %{"structuredContent" => second}} = call_tool(tenant, token, "list_content_types")
      refute Map.has_key?(second, "watch_url")

      # What 30 quiet minutes leave behind: the node's note of the last call expired
      Watch.forget(grant.id)
      assert Watch.due?(grant.id)

      %{"result" => %{"content" => [%{"text" => text}], "structuredContent" => third}} =
        call_tool(tenant, token, "list_content_types")

      assert third["watch_url"] == url
      assert Jason.decode!(text)["watch_url"] == url
    end

    test "waits for a result that can carry it, when the first call fails", %{tenant: tenant, token: token, grant: grant} do
      assert %{"result" => %{"isError" => true} = failed} =
               call_tool(tenant, token, "describe_module", %{"module" => "local:0"})

      refute inspect(failed) =~ Watch.url(grant)
      assert Watch.due?(grant.id)

      assert %{"result" => %{"structuredContent" => %{"watch_url" => _}}} =
               call_tool(tenant, token, "list_content_types")

      refute Watch.due?(grant.id)
    end

    test "is in every prepare_proposal result, next to review_url", %{tenant: tenant, token: token, grant: grant} = c do
      c = Map.merge(c, page_context(c))
      call_tool(tenant, token, "list_content_types")
      refute Watch.due?(grant.id)

      for _ <- 1..2 do
        %{"result" => %{"structuredContent" => review}} =
          call_tool(tenant, token, "prepare_proposal", proposal_args(c))

        assert review["review_url"] =~ "/admin/assistant/connected/"
        assert review["watch_url"] == Watch.url(grant)
      end
    end

    test "is left out rather than failing a result at the size limit", %{grant: grant} do
      # The largest result that encodes within the limit on its own
      fill = String.duplicate("a", MCP.Tools.result_limit() - byte_size(~s({"text":""})))
      data = %{"text" => fill}
      assert byte_size(Jason.encode!(data)) == MCP.Tools.result_limit()

      Watch.forget(grant.id)
      payload = MCP.Tools.encode_result({:ok, data}, %{watch_url: Watch.url(grant)})
      assert {true, %{structuredContent: %{"text" => ^fill} = content}, false} = payload
      refute Map.has_key?(content, "watch_url")
    end
  end

  describe "history/1" do
    test "is the connection's calls of the last hour, newest first, at most 50",
         %{tenant: tenant, token: token, grant: grant} do
      call_tool(tenant, token, "list_content_types")
      call_tool(tenant, token, "search_entries", %{"query" => "x", "content_type" => "Brando.Pages.Page"})

      # Another connection's call, and one from two hours ago, are not in it
      Repo.insert!(%Event{
        action: :tool_called,
        source: :mcp,
        schema: to_string(Grant),
        entry_id: grant.id + 1,
        details: %{"tool" => "list_modules", "ok" => true}
      })

      old =
        Repo.insert!(%Event{
          action: :tool_called,
          source: :mcp,
          schema: to_string(Grant),
          entry_id: grant.id,
          details: %{"tool" => "list_modules", "ok" => true}
        })

      two_hours_ago = DateTime.add(DateTime.utc_now(), -7_200, :second)
      Repo.update_all(from(e in Event, where: e.id == ^old.id), set: [inserted_at: two_hours_ago])

      assert [%{tool: "search_entries", state: :ok}, %{tool: "list_content_types"}] = Watch.history(grant)

      for _ <- 1..55, do: Brando.Activity.tool_called(grant, nil, "list_modules")
      assert length(Watch.history(grant)) == 50
    end
  end
end
