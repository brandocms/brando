defmodule Brando.Content.Proposals.ToolsScopeTest do
  # The tools that describe content types and modules, and the entries they
  # list, answer only for what the actor may see: for the Assistant's own
  # calls and for a tool connected over MCP alike.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

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

  describe "entries from other content types" do
    # A datasource lists what its own code queries, and an outline names the
    # entries its blocks choose and link to: whatever the person may not read
    # stays out, for the Assistant and over MCP alike.
    setup c do
      featured =
        Brando.ProposalFixtures.module!(c.user, "Featured", "<div></div>",
          datasource: true,
          datasource_type: :selection,
          datasource_module: "Elixir.BrandoIntegration.ModuleWithDatasource",
          datasource_query: "page_identifiers"
        )

      {:ok, identity} = Brando.Content.create_identifier(Brando.Pages.Page, c.identity)
      Map.merge(c, %{featured: featured, identifier: identity})
    end

    test "list_selection_options leaves out entries the actor cannot read", c do
      args = %{"module" => "local:#{c.featured.id}"}

      # May edit fragments, so may use modules, but may not read pages
      user =
        member(c, [
          "brando.admin.access",
          "brando.assistant.use",
          "brando.pages_fragments.read",
          "brando.pages_fragments.update"
        ])

      assert {:ok, %{options: [], total: 0}} =
               Tools.call("list_selection_options", args, %Context{actor: user, conversation_id: 1})

      reader = member(c, ["brando.admin.access", "brando.assistant.use", "brando.pages.read", "brando.pages.update"])

      assert {:ok, %{options: options}} =
               Tools.call("list_selection_options", args, %Context{actor: reader, conversation_id: 1})

      assert c.identifier.id in Enum.map(options, & &1.identifier_id)
    end

    test "over MCP too", c do
      tenant = MCP.tenant(nil, nil) |> switch!()
      args = %{"module" => "local:#{c.featured.id}"}

      user =
        c
        |> member([
          "brando.admin.access",
          "brando.mcp.connect",
          "brando.pages_fragments.read",
          "brando.pages_fragments.update"
        ])
        |> enable_two_factor()

      %{"access_token" => token} = connect!(log_in_user(build_conn(), user), tenant)

      assert %{"result" => %{"structuredContent" => %{"options" => [], "total" => 0}}} =
               call_tool(tenant, token, "list_selection_options", args)

      reader =
        c
        |> member(["brando.admin.access", "brando.mcp.connect", "brando.pages.read", "brando.pages.update"])
        |> enable_two_factor()

      %{"access_token" => token} = connect!(log_in_user(build_conn(), reader), tenant)

      assert %{"result" => %{"structuredContent" => %{"options" => options}}} =
               call_tool(tenant, token, "list_selection_options", args)

      assert c.identifier.id in Enum.map(options, & &1["identifier_id"])
    end

    test "entry_outline names only the chosen and linked entries the actor can read", c do
      %{block_id: block_id} =
        Repo.one!(
          from(b in Brando.Pages.Page.Blocks, where: b.entry_id == ^c.identity.id, order_by: b.sequence, limit: 1)
        )

      secret =
        Repo.insert!(%Brando.Content.Identifier{
          schema: Brando.BlueprintTest.Project,
          entry_id: 4242,
          title: "Secret project",
          language: :en,
          status: :published
        })

      for {identifier, n} <- Enum.with_index([c.identifier, secret]) do
        Repo.insert!(%Brando.Content.BlockIdentifier{block_id: block_id, identifier_id: identifier.id, sequence: n})
      end

      for {identifier, key} <- [{c.identifier, "own"}, {secret, "secret"}] do
        Repo.insert!(%Brando.Content.Var{
          block_id: block_id,
          type: :link,
          key: key,
          label: key,
          link_type: :identifier,
          identifier_id: identifier.id
        })
      end

      reader = member(c, ["brando.admin.access", "brando.assistant.use", "brando.pages.read", "brando.pages.update"])
      args = %{"content_type" => @page, "id" => c.identity.id}

      assert {:ok, outline} = Tools.call("entry_outline", args, %Context{actor: reader, conversation_id: 1})
      refute inspect(outline) =~ "Secret project"

      [first | _] = outline.blocks.blocks
      assert [%{identifier_id: own, title: "Identity"}, %{identifier_id: hidden} = unreadable] = first.selection
      assert own == c.identifier.id
      assert hidden == secret.id
      refute Map.has_key?(unreadable, :title)

      assert %{entry: "Identity"} = first.values["own"]
      assert first.values["secret"] == %{unreadable: true}

      # Over MCP, the same
      tenant = MCP.tenant(nil, nil) |> switch!()

      connected =
        c
        |> member(["brando.admin.access", "brando.mcp.connect", "brando.pages.read", "brando.pages.update"])
        |> enable_two_factor()

      %{"access_token" => token} = connect!(log_in_user(build_conn(), connected), tenant)
      result = call_tool(tenant, token, "entry_outline", args)
      refute result["result"]["isError"]
      refute Jason.encode!(result) =~ "Secret project"
    end
  end
end
