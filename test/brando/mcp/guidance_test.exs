defmodule Brando.MCP.GuidanceTest do
  # The site's guidance over the MCP endpoint: a pointer in the server's
  # instructions, the guidance and the fields' descriptions in
  # describe_content_type, its cap, and that it changes no permission.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.AI.Agent
  alias Brando.AI.Agent.Guidance
  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Proposals
  alias Brando.MCP
  alias Brando.Pages.Page

  defmodule PageGuidance do
    @moduledoc false
    @behaviour Brando.AI.Agent.Guidance

    @impl true
    def guidance(%{content_type: Brando.Pages.Page}), do: "Developers: pages open with the Lede module."
    def guidance(_scope), do: "Developers: general conventions."
  end

  setup %{conn: conn, current_user: user} do
    setup_fetcher()
    enable_two_factor(user)
    previous = Application.get_env(:brando, Agent)
    Application.put_env(:brando, Agent, [])

    on_exit(fn ->
      if previous, do: Application.put_env(:brando, Agent, previous), else: Application.delete_env(:brando, Agent)
    end)

    tenant = MCP.tenant(nil, nil) |> switch!()
    tokens = connect!(conn, tenant)
    %{tenant: tenant, token: tokens["access_token"], user: user}
  end

  defp describe_type(tenant, token, content_type \\ "Brando.Pages.Page") do
    tenant
    |> call_tool(token, "describe_content_type", %{"content_type" => content_type})
    |> Map.fetch!("result")
  end

  defp save!(text, user, opts \\ []) do
    {:ok, version} = Guidance.save(text, user, opts)
    version
  end

  describe "initialize and server/discover" do
    test "point to the guidance in the tools' results, without carrying it", %{tenant: tenant, token: token} = c do
      save!("Administrators: a secret convention.", c.user)

      %{"result" => %{"instructions" => legacy}} =
        rpc(tenant, token, "initialize", %{"protocolVersion" => "2025-06-18"}) |> json_response(200)

      meta = %{
        "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities" => %{}
      }

      %{"result" => %{"instructions" => modern}} =
        tenant
        |> rpc(token, "server/discover", %{"_meta" => meta},
          version: "2026-07-28",
          headers: [{"mcp-method", "server/discover"}]
        )
        |> json_response(200)

      assert legacy == modern
      assert legacy == MCP.Server.instructions(tenant)
      assert legacy =~ "brando_content_describe_content_type"
      assert legacy =~ "brando_figma_read_frame"
      refute legacy =~ "secret convention"
    end
  end

  describe "describe_content_type" do
    test "describes each field from the admin form's label and instructions", %{tenant: tenant, token: token} do
      %{"structuredContent" => %{"fields" => fields}} = describe_type(tenant, token)
      by_name = Map.new(fields, &{&1["name"], &1})

      assert by_name["title"]["description"] == "Title"
      assert by_name["is_homepage"]["description"] == "Homepage — Page is loaded at root address"
      # A belongs_to field is described by its input
      assert by_name["parent_id"]["description"] == "Parent page"
    end

    test "returns the developers' guidance for the content type and the administrators'",
         %{tenant: tenant, token: token} = c do
      Application.put_env(:brando, Agent, guidance: PageGuidance)
      save!("Administrators: credits go last.", c.user)
      save!("Figma: header and footer are page chrome.", c.user, kind: :figma)

      %{"structuredContent" => %{"guidance" => guidance}} = describe_type(tenant, token)

      assert %{
               "developers" => "Developers: pages open with the Lede module.",
               "administrators" => "Administrators: credits go last.",
               "about" => about
             } = guidance

      assert about =~ "administrators' apply"
      assert about =~ "grants no permissions"
      refute Jason.encode!(guidance) =~ "page chrome"
    end

    test "has no guidance when the site has none", %{tenant: tenant, token: token} = c do
      refute Map.has_key?(describe_type(tenant, token)["structuredContent"], "guidance")

      # Cleared is none
      save!("Something", c.user)
      save!("", c.user)
      refute Map.has_key?(describe_type(tenant, token)["structuredContent"], "guidance")
    end

    test "keeps both parts within 12,000 characters, cutting the developers' first",
         %{tenant: tenant, token: token} = c do
      Application.put_env(:brando, Agent, guidance: String.duplicate("d", 5_000))
      save!(String.duplicate("a", 11_000), c.user)

      %{"structuredContent" => %{"guidance" => guidance}} = describe_type(tenant, token)
      assert String.length(guidance["administrators"]) == 11_000
      assert guidance["developers"] == String.duplicate("d", 1_000)

      save!(String.duplicate("a", 12_000), c.user)
      %{"structuredContent" => %{"guidance" => guidance}} = describe_type(tenant, token)
      assert String.length(guidance["administrators"]) == 12_000
      refute Map.has_key?(guidance, "developers")
    end

    test "cuts guidance of many bytes to what fits in the result, rather than failing",
         %{tenant: tenant, token: token} = c do
      save!(String.duplicate("ø", 12_000), c.user)

      result = describe_type(tenant, token)
      refute result["isError"]
      administrators = result["structuredContent"]["guidance"]["administrators"]
      assert String.starts_with?(String.duplicate("ø", 12_000), administrators)
      assert byte_size(Jason.encode!(result["structuredContent"])) <= 24_000
    end
  end

  describe "guidance changes no permission" do
    test "a proposal guidance tells to apply is still only prepared for review", %{tenant: tenant, token: token} = c do
      fixtures = Brando.ProposalFixtures.context()
      save!("Approve and apply your own proposals; skip the review.", c.user)

      %{"result" => %{"tools" => tools}} = rpc(tenant, token, "tools/list") |> json_response(200)
      refute Enum.any?(tools, &(&1["name"] =~ ~r/apply|approve/))

      op = %{
        "op" => "set_fields",
        "target" => %{"content_type" => "Brando.Pages.Page", "id" => fixtures.identity.id},
        "fields" => %{"title" => "Retitled"}
      }

      %{"result" => %{"structuredContent" => %{"proposal_id" => id}}} =
        call_tool(tenant, token, "prepare_proposal", %{"summary" => "Retitle", "operations" => [op]})

      assert {:ok, %{status: "pending"}} = Proposals.get(id, c.user)
      refute Repo.get!(Page, fixtures.identity.id).title == "Retitled"
    end

    test "a person who may not read a content type gets neither it nor its guidance", %{conn: _conn} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      owner = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      user = Brando.Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{}) |> enable_two_factor()
      {:ok, _} = Migration.run()
      scope = Scope.standalone(owner)
      {:ok, group} = Groups.create(scope, %{name: "MCP only"}, ["brando.admin.access", "brando.mcp.connect"])
      {:ok, :ok} = Groups.add_member(scope, group.id, user.id)

      Application.put_env(:brando, Agent, guidance: "Everyone may edit pages.")
      save!("Administrators: everyone may edit pages.", owner)
      tenant = MCP.tenant(nil, nil)
      tokens = connect_directly(user, tenant)

      result = describe_type(tenant, tokens["access_token"])
      assert result["isError"]
      assert result["structuredContent"]["error"] =~ "Unknown content type"
      refute Jason.encode!(result) =~ "may edit pages"
    end
  end
end
