defmodule Brando.Content.Proposals.PalettesTest do
  # Palettes are design, not content: a proposal from the Assistant or a
  # tool connected over MCP may pick an existing palette (search it, read it,
  # link a block to it), but not create or change one, in both authorization
  # modes, whatever the actor's palette permissions say. A refused proposal
  # stores nothing, and a stored one that touches a palette, from before the
  # upgrade, is neither approved nor applied.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Catalog, Groups, Migration, Scope}
  alias Brando.Content.Palette
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{CreateEntry, Record, SetFields, Tools}
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.MCP
  alias Brando.Pages.Page
  alias Brando.Test.Users, as: TestUsers

  @palette_fields %{
    "name" => "Planted",
    "key" => "planted",
    "namespace" => "site",
    "colors" => [%{"name" => "Background", "key" => "bg", "hex_value" => "#000000"}]
  }

  setup do
    c = Brando.ProposalFixtures.context()
    palette = Factory.insert(:palette, name: "Evening", key: "evening", creator_id: c.user.id)
    {:ok, _} = Brando.Content.create_identifier(Palette, palette)
    Map.put(c, :palette, palette)
  end

  defp contexts(actor) do
    [
      assistant: %Context{actor: actor, origin: :assistant, conversation_id: Ecto.UUID.generate()},
      mcp: %Context{actor: actor, origin: :mcp, client: "Test client"}
    ]
  end

  defp prepare(ops, context), do: Tools.call("prepare_proposal", %{"summary" => "x", "operations" => ops}, context)

  defp create(content_type, fields),
    do: %{"op" => "create_entry", "content_type" => content_type, "ref" => "x", "fields" => fields}

  defp set_fields(palette),
    do: %{
      "op" => "set_fields",
      "target" => %{"content_type" => "Brando.Content.Palette", "id" => palette.id},
      "fields" => %{"name" => "Renamed", "key" => "renamed"}
    }

  defp records, do: Repo.aggregate(Record, :count)
  defp palettes, do: Repo.all(from(p in Palette, select: {p.id, p.name, p.key}, order_by: p.id))

  defp assert_refused(actor, c) do
    before = {records(), palettes()}

    for {origin, context} <- contexts(actor),
        op <- [create("Brando.Content.Palette", @palette_fields), set_fields(c.palette)] do
      assert {:error, message} = prepare([op], context), "#{origin}: #{op["op"]} on a palette was accepted"
      assert message =~ "Brando.Content.Palette"
      assert message =~ "list_content_types"
    end

    # An Elixir caller building the operations is refused the same way.
    for op <- [
          %CreateEntry{schema: Palette, ref: "x", fields: @palette_fields},
          %SetFields{target: {Palette, c.palette.id}, fields: %{"name" => "Renamed"}}
        ] do
      assert {:error, message} = Proposals.propose([op], actor)
      assert message =~ "list_content_types"
    end

    assert {records(), palettes()} == before
  end

  # Palettes stay readable: search and outline find them, though
  # list_content_types no longer offers them for change.
  defp assert_readable(actor, c) do
    for {_origin, context} <- contexts(actor) do
      assert {:ok, %{content_types: types}} = Tools.call("list_content_types", %{}, context)
      assert Enum.any?(types, &(&1.content_type == "Brando.Pages.Page"))
      refute Enum.any?(types, &(&1.content_type == "Brando.Content.Palette"))

      assert {:ok, %{content_type: "Brando.Content.Palette"}} =
               Tools.call("entry_outline", %{"content_type" => "Brando.Content.Palette", "id" => c.palette.id}, context)

      assert {:ok, %{content_type: "Brando.Content.Palette"}} =
               Tools.call("describe_content_type", %{"content_type" => "Brando.Content.Palette"}, context)
    end
  end

  defp assert_searchable(actor, c) do
    for {_origin, context} <- contexts(actor) do
      args = %{"query" => c.palette.name, "content_type" => "Brando.Content.Palette"}
      assert {:ok, %{entries: found}} = Tools.call("search_entries", args, context)
      assert Enum.any?(found, &(&1.id == c.palette.id and &1.content_type == "Brando.Content.Palette"))
    end
  end

  # Without a content type, palettes and the entries to change come back
  # together, in title order, and the limit counts both.
  defp assert_searched_together(actor, c) do
    page = Brando.ProposalFixtures.page!(c.user, "Evening walk", c.text_module)
    {:ok, _} = Brando.Content.create_identifier(Page, page)

    for {_origin, context} <- contexts(actor) do
      assert {:ok, %{entries: found}} = Tools.call("search_entries", %{"query" => "Evening"}, context)

      assert Enum.sort(Enum.map(found, &{&1.content_type, &1.id})) ==
               [{"Brando.Content.Palette", c.palette.id}, {"Brando.Pages.Page", page.id}]

      assert Enum.map(found, & &1.title) == Enum.sort(Enum.map(found, & &1.title))

      assert {:ok, %{entries: [first]}} =
               Tools.call("search_entries", %{"query" => "Evening", "limit" => 1}, context)

      assert first == hd(found)
    end
  end

  # A block still picks an existing palette: a link variable that links to
  # palettes takes one, and the proposal applies.
  defp assert_palette_picked(actor, c) do
    module =
      Brando.ProposalFixtures.module!(c.user, "Swatch", "<p>{{ heading }}</p>",
        vars: [
          %{type: "string", key: "heading", label: "Heading"},
          %{type: "link", key: "scheme", label: "Scheme", link_identifier_schemas: ["Brando.Content.Palette"]}
        ]
      )

    for {origin, context} <- contexts(actor) do
      op = %{
        "op" => "insert_block",
        "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
        "field" => "blocks",
        "module" => "local:#{module.id}",
        "placement" => "append",
        "values" => %{
          "heading" => "Picked #{origin}",
          "scheme" => %{"content_type" => "Brando.Content.Palette", "id" => c.palette.id}
        }
      }

      assert {:ok, %{proposal_id: id, applicable: true}} = prepare([op], context)
      %{version: version} = Repo.get!(Record, id)
      assert {:ok, _} = Proposals.approve(id, version, actor)
      assert {:ok, _} = Proposals.apply(id, version, actor)
    end

    {:ok, identifier} = Brando.Content.get_identifier(Palette, %{id: c.palette.id})

    linked =
      Repo.all(
        from(v in Brando.Content.Var,
          join: b in Brando.Content.Block,
          on: v.block_id == b.id,
          where: b.module_id == ^module.id and v.key == "scheme",
          select: v.identifier_id
        )
      )

    assert linked == [identifier.id, identifier.id]
  end

  # A record as an earlier version stored it: a page proposal with its
  # target swapped for a palette.
  defp stored_palette_change(actor, c) do
    op = %{
      "op" => "set_fields",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
      "fields" => %{"title" => "Renamed"}
    }

    {:ok, %{proposal_id: id}} = prepare([op], contexts(actor)[:assistant])
    record = Repo.get!(Record, id)
    [stored] = record.operations
    target = %{"content_type" => "Brando.Content.Palette", "id" => c.palette.id}

    record
    |> Ecto.Changeset.change(operations: [%{stored | "target" => target, "fields" => %{"name" => "Renamed"}}])
    |> Repo.update!()
  end

  defp assert_stored_refused(actor, c) do
    before = palettes()
    record = stored_palette_change(actor, c)

    assert {:error, message} = Proposals.approve(record.id, record.version, actor)
    assert message =~ "list_content_types"

    # Approved before the upgrade, say.
    record |> Ecto.Changeset.change(status: "approved") |> Repo.update!()
    assert {:error, message} = Proposals.apply(record.id, record.version, actor)
    assert message =~ "list_content_types"

    assert palettes() == before
  end

  describe "legacy authorization" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      :ok
    end

    test "an editor's proposal may not create or change a palette, but may pick one", c do
      editor = TestUsers.insert_user(role: :editor)
      # The boundary alone would let a legacy editor change palettes.
      assert :ok = Boundary.authorize(editor, :create, Palette)
      assert :ok = Boundary.authorize(editor, :update, c.palette)

      assert_refused(editor, c)
      assert_readable(editor, c)
      assert_searchable(editor, c)
      assert_palette_picked(editor, c)
    end

    test "nor a superuser's", c do
      superuser = TestUsers.insert_user(role: :superuser)
      assert_refused(superuser, c)
      assert_palette_picked(superuser, c)
    end

    test "a stored proposal changing a palette is neither approved nor applied", c do
      assert_stored_refused(TestUsers.insert_user(role: :editor), c)
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

    defp palette_keys, do: for(action <- [:read, :create, :update], do: Catalog.get(action, Palette).key)

    test "an Editor-preset member may pick a palette but not create or change one", c do
      editor = member(c, Catalog.preset_permissions(:editor, :standalone) ++ ["brando.assistant.use"])
      # The preset reads palettes and does not change them.
      assert :ok = Boundary.authorize(editor, :read, c.palette)
      refute Boundary.authorize(editor, :update, c.palette) == :ok

      assert_refused(editor, c)
      assert_readable(editor, c)
      assert_searchable(editor, c)
      assert_searched_together(editor, c)
      assert_palette_picked(editor, c)
    end

    test "a member who may not read palettes finds none", c do
      keys = Catalog.preset_permissions(:editor, :standalone) -- [Catalog.get(:read, Palette).key]
      member = member(c, keys ++ ["brando.assistant.use"])
      refute Boundary.authorize(member, :read, c.palette) == :ok
      {:ok, _} = Brando.Content.create_identifier(Page, c.identity)

      for {_origin, context} <- contexts(member) do
        assert {:ok, %{entries: found}} = Tools.call("search_entries", %{"query" => ""}, context)
        assert Enum.any?(found, &(&1.content_type == "Brando.Pages.Page"))
        refute Enum.any?(found, &(&1.content_type == "Brando.Content.Palette"))
      end
    end

    test "a member who may create and change palettes still cannot through a proposal", c do
      member = member(c, Catalog.preset_permissions(:editor, :standalone) ++ palette_keys() ++ ["brando.assistant.use"])
      assert :ok = Boundary.authorize(member, :create, Palette)
      assert :ok = Boundary.authorize(member, :update, c.palette)

      assert_refused(member, c)
      assert_searchable(member, c)
      assert_palette_picked(member, c)
      assert_stored_refused(member, c)
    end

    test "over MCP the tool gets the refusal as a tool error", c do
      tenant = MCP.tenant(nil, nil) |> switch!()
      keys = Catalog.preset_permissions(:editor, :standalone) ++ palette_keys() ++ ["brando.mcp.connect"]
      editor = c |> member(keys) |> enable_two_factor()
      %{"access_token" => token} = connect!(log_in_user(build_conn(), editor), tenant)
      before = {records(), palettes()}

      for op <- [create("Brando.Content.Palette", @palette_fields), set_fields(c.palette)] do
        assert %{"result" => %{"isError" => true, "content" => [%{"text" => text} | _]}} =
                 call_tool(tenant, token, "prepare_proposal", %{"summary" => "x", "operations" => [op]})

        assert text =~ "list_content_types"
      end

      assert {records(), palettes()} == before
    end
  end
end
