defmodule Brando.Content.Proposals.SchemaAllowlistTest do
  # A proposal names only the content types in the catalogue, the ones
  # `list_content_types` lists. Brando's internal schemas (users, global
  # sets, menus, vars, modules, site settings) are refused before anything
  # is stored, for the Assistant and a tool connected over MCP, in both
  # authorization modes, whatever the actor's create permission says.
  #
  # Before, a create_entry naming one was stored and approved. Applying it
  # ran the context's create inside the transaction, and only a later read
  # rolled it back: a global set's and a menu's caches kept the rolled-back
  # rows, so a legacy editor could put a global set, which only superusers
  # define, in front of the site's templates.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Catalog, Groups, Migration, Scope}
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{CreateEntry, Record, Tools}
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.MCP
  alias Brando.Test.Users, as: TestUsers

  @internal [
    {"Brando.Users.User",
     %{"name" => "Back Door", "email" => "door@example.com", "password" => "hunter2hunter2", "language" => "en"}},
    {"Brando.Users.UserConfig", %{}},
    {"Brando.Sites.GlobalSet",
     %{
       "label" => "Planted",
       "key" => "planted",
       "language" => "en",
       "vars" => [%{"type" => "string", "key" => "msg", "label" => "Msg", "value" => "MARKER"}]
     }},
    {"Brando.Navigation.Menu", %{"title" => "Planted", "key" => "planted", "language" => "en"}},
    {"Brando.Content.Var", %{"type" => "string", "key" => "planted", "label" => "Planted", "value" => "MARKER"}},
    {"Brando.Content.Module", %{"name" => "Planted", "namespace" => "general", "code" => "<p>MARKER</p>"}},
    {"Brando.Content.ModuleSet", %{"title" => "Planted"}},
    {"Brando.Sites.Identity", %{"name" => "Planted"}},
    {"Brando.Sites.Config", %{}}
  ]

  setup do
    Map.put(Brando.ProposalFixtures.context(), :caches, warm_caches())
  end

  defp warm_caches do
    preserve_cache([:globals, :navigation])
    Brando.Cache.Globals.set()
    Brando.Cache.Navigation.set()
    caches()
  end

  defp caches, do: {Brando.Cache.Globals.get("en"), Brando.Cache.Navigation.get("planted", "en")}

  defp contexts(actor) do
    [
      assistant: %Context{actor: actor, origin: :assistant, conversation_id: Ecto.UUID.generate()},
      mcp: %Context{actor: actor, origin: :mcp, client: "Test client"}
    ]
  end

  defp create(content_type, fields),
    do: %{"op" => "create_entry", "content_type" => content_type, "ref" => "x", "fields" => fields}

  defp records, do: Repo.aggregate(Record, :count)

  # Every internal schema is refused at prepare, with a message that names
  # it and points to list_content_types. Nothing is stored, nothing created,
  # and the caches are as they were.
  defp assert_refused(actor, c) do
    before = records()

    for {origin, context} <- contexts(actor), {content_type, fields} <- @internal do
      ops = [create(content_type, fields)]

      assert {:error, message} = Tools.call("prepare_proposal", %{"summary" => "x", "operations" => ops}, context),
             "#{origin}: #{content_type} was accepted"

      assert message =~ content_type
      assert message =~ "list_content_types"

      # Targets and link values naming one are refused alike.
      target = %{"content_type" => content_type, "id" => c.user.id}
      set = %{"op" => "set_fields", "target" => target, "fields" => %{"title" => "x"}}
      assert {:error, _} = Tools.call("prepare_proposal", %{"summary" => "x", "operations" => [set]}, context)
    end

    assert records() == before
    assert caches() == c.caches
    refute Repo.exists?(from(u in Brando.Users.User, where: u.email == "door@example.com"))
    refute Repo.exists?(from(s in Brando.Sites.GlobalSet, where: s.key == "planted"))
    refute Repo.exists?(from(m in Brando.Navigation.Menu, where: m.key == "planted"))

    # An Elixir caller building the operation is refused the same way.
    for {content_type, _} <- @internal do
      schema = Module.safe_concat([content_type])
      assert {:error, message} = Proposals.propose([%CreateEntry{schema: schema, ref: "x", fields: %{}}], actor)
      assert message =~ "list_content_types"
    end

    assert records() == before
  end

  # A content type in the catalogue still takes a create.
  defp assert_page_accepted(actor) do
    for {_origin, context} <- contexts(actor) do
      op =
        create("Brando.Pages.Page", %{
          "title" => "Rooms",
          "uri" => "rooms-#{System.unique_integer([:positive])}",
          "language" => "en"
        })

      assert {:ok, %{applicable: true}} =
               Tools.call("prepare_proposal", %{"summary" => "x", "operations" => [op]}, context)
    end
  end

  describe "legacy authorization" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      :ok
    end

    test "an editor's proposal naming an internal schema is refused", c do
      editor = TestUsers.insert_user(role: :editor)
      # The boundary alone would let a legacy editor create these.
      assert :ok = Boundary.authorize(editor, :create, Brando.Sites.GlobalSet)
      assert :ok = Boundary.authorize(editor, :create, Brando.Users.User)

      assert_refused(editor, c)
      assert_page_accepted(editor)
    end

    test "an admin's too", c do
      assert_refused(TestUsers.insert_user(role: :admin), c)
    end

    test "a stored proposal naming one is neither approved nor applied", c do
      editor = TestUsers.insert_user(role: :editor)
      record = stored_with(editor, "Brando.Sites.GlobalSet", elem(Enum.at(@internal, 2), 1))

      assert {:error, message} = Proposals.approve(record.id, record.version, editor)
      assert message =~ "list_content_types"

      # Approved before the upgrade, say.
      record |> Ecto.Changeset.change(status: "approved") |> Repo.update!()
      assert {:error, _} = Proposals.apply(record.id, record.version, editor)

      assert caches() == c.caches
      refute Repo.exists?(from(s in Brando.Sites.GlobalSet, where: s.key == "planted"))
    end
  end

  describe "groups authorization" do
    setup c do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      setup_fetcher()
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()
      Map.put(c, :scope, Scope.standalone(owner))
    end

    defp member(c, keys) do
      user = TestUsers.insert_user(role: :editor)
      {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
      user
    end

    test "an Editor-preset member's proposal naming an internal schema is refused", c do
      editor = member(c, Catalog.preset_permissions(:editor, :standalone) ++ ["brando.assistant.use"])
      assert_refused(editor, c)
      assert_page_accepted(editor)
    end

    test "a member who may create users and global sets elsewhere still cannot through a proposal", c do
      keys =
        for schema <- [Brando.Users.User, Brando.Sites.GlobalSet, Brando.Navigation.Menu],
            action <- [:read, :create],
            do: Catalog.get(action, schema).key

      admin = member(c, Catalog.preset_permissions(:admin, :standalone) ++ keys)
      assert :ok = Boundary.authorize(admin, :create, Brando.Sites.GlobalSet)
      assert_refused(admin, c)
    end

    test "over MCP the tool gets the refusal as a tool error", c do
      tenant = MCP.tenant(nil, nil) |> switch!()
      editor = member(c, Catalog.preset_permissions(:editor, :standalone) ++ ["brando.mcp.connect"])
      editor = enable_two_factor(editor)
      %{"access_token" => token} = connect!(log_in_user(build_conn(), editor), tenant)
      before = records()

      for {content_type, fields} <- @internal do
        args = %{"summary" => "x", "operations" => [create(content_type, fields)]}

        assert %{"result" => %{"isError" => true, "content" => [%{"text" => text} | _]}} =
                 call_tool(tenant, token, "prepare_proposal", args)

        assert text =~ "list_content_types"
      end

      assert records() == before
      assert caches() == c.caches
    end
  end

  # A record as an earlier version stored it, before the catalogue was
  # checked: a page proposal with its content type swapped.
  defp stored_with(actor, content_type, fields) do
    op = create("Brando.Pages.Page", %{"title" => "Rooms", "uri" => "rooms-stored", "language" => "en"})

    {:ok, %{proposal_id: id}} =
      Tools.call("prepare_proposal", %{"summary" => "x", "operations" => [op]}, hd(contexts(actor)) |> elem(1))

    record = Repo.get!(Record, id)
    [stored] = record.operations

    record
    |> Ecto.Changeset.change(operations: [%{stored | "content_type" => content_type, "fields" => fields}])
    |> Repo.update!()
  end
end
