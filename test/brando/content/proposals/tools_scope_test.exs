defmodule Brando.Content.Proposals.ToolsScopeTest do
  # The tools that describe content types and modules answer only for what
  # the actor may see: for the Assistant's own calls and for a tool
  # connected over MCP alike.
  use Brando.LiveCase

  import Brando.MCPHelpers

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.MCP

  setup do
    # Content first, as legacy authorization allows; then groups decide.
    c = Brando.ProposalFixtures.context()
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    setup_fetcher()
    owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    {:ok, _} = Migration.run()
    Map.merge(c, %{scope: Scope.standalone(owner)})
  end

  defp member(c, keys) do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
    user
  end

  @page "Brando.Pages.Page"

  defp calls(c) do
    [
      {"describe_content_type", %{"content_type" => @page}},
      {"list_modules", %{"content_type" => @page}},
      {"describe_module", %{"module" => "local:#{c.case_module.id}"}},
      {"list_selection_options", %{"module" => "local:#{c.case_module.id}"}}
    ]
  end

  describe "the Assistant's calls" do
    test "someone who cannot read the content type learns nothing about it", c do
      user = member(c, ["brando.admin.access", "brando.assistant.use"])
      context = %Context{actor: user, conversation_id: 1}

      for {name, args} <- calls(c) do
        assert {:error, message} = Tools.call(name, args, context), name
        refute message =~ "Case", name
      end
    end

    test "someone who may edit pages describes them and their modules", c do
      user = member(c, ["brando.admin.access", "brando.assistant.use", "brando.pages.read", "brando.pages.update"])
      context = %Context{actor: user, conversation_id: 1}

      assert {:ok, %{content_type: @page}} = Tools.call("describe_content_type", %{"content_type" => @page}, context)
      assert {:ok, %{modules: _}} = Tools.call("list_modules", %{"content_type" => @page}, context)
      assert {:ok, %{module: _}} = Tools.call("describe_module", %{"module" => "local:#{c.case_module.id}"}, context)
    end
  end

  describe "a tool connected over MCP" do
    test "gets the same answers as the person", c do
      tenant = MCP.tenant(nil, nil) |> switch!()
      user = member(c, ["brando.admin.access", "brando.mcp.connect"]) |> enable_two_factor()
      conn = log_in_user(build_conn(), user)
      %{"access_token" => token} = connect!(conn, tenant)

      for {name, args} <- calls(c) do
        assert %{"result" => %{"isError" => true}} = call_tool(tenant, token, name, args), name
      end

      reader = member(c, ["brando.admin.access", "brando.mcp.connect", "brando.pages.read", "brando.pages.update"])
      reader = enable_two_factor(reader)
      %{"access_token" => token} = connect!(log_in_user(build_conn(), reader), tenant)

      assert %{"result" => %{"structuredContent" => %{"content_type" => @page}}} =
               call_tool(tenant, token, "describe_content_type", %{"content_type" => @page})
    end
  end
end
