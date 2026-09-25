defmodule Brando.Content.Proposals.ToolsTest do
  use Brando.ConnCase, async: false
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Pages.Page

  setup do
    c = Brando.ProposalFixtures.context()
    Enum.each([c.identity, c.naming], &Brando.Content.create_identifier(Page, &1))

    context = %Context{
      actor: c.user,
      conversation_id: Ecto.UUID.generate(),
      attachments: %{"image1" => %{kind: :image, id: c.image.id, label: "lobby.jpg"}}
    }

    Map.put(c, :context, context)
  end

  defp call!(name, args, context) do
    assert {:ok, result} = Tools.call(name, args, context)
    # Results go back to the model as JSON.
    assert {:ok, _} = Jason.encode(result)
    result
  end

  test "definitions are unique and carry JSON-schema parameters" do
    names = Enum.map(Tools.definitions(), & &1.name)
    assert names == Enum.uniq(names)
    assert Enum.all?(Tools.definitions(), &(&1.parameters.type == "object" and is_binary(&1.description)))
    refute Enum.any?(names, &(&1 =~ ~r/apply|approve|delete/))
  end

  test "tools need an authenticated actor and a known name", c do
    assert {:error, _} = Tools.call("list_content_types", %{}, %{c.context | actor: nil})
    assert {:error, _} = Tools.call("apply_proposal", %{}, c.context)
  end

  test "discovery: content types, fields, entries and outlines", c do
    %{content_types: types} = call!("list_content_types", %{}, c.context)

    assert %{block_fields: [%{field: "blocks"} | _], page_preview: true} =
             Enum.find(types, &(&1.content_type == "Brando.Pages.Page"))

    %{fields: fields} = call!("describe_content_type", %{"content_type" => "Brando.Pages.Page"}, c.context)
    names = Enum.map(fields, & &1.name)
    assert "title" in names and "uri" in names
    refute "status" in names

    %{entries: entries} =
      call!(
        "search_entries",
        # The test suite registers fixture schemas without tables; scope the search.
        %{"query" => "Ident", "content_type" => "Brando.Pages.Page"},
        c.context
      )

    assert [%{content_type: "Brando.Pages.Page", id: id, title: "Identity"}] = entries
    assert id == c.identity.id

    outline = call!("entry_outline", %{"content_type" => "Brando.Pages.Page", "id" => id}, c.context)
    assert outline.live
    assert [%{texts: %{"body" => "Identity 0"}, module_name: "Text"} | _] = outline.blocks.blocks
    assert length(outline.blocks.blocks) == 3

    assert {:error, message} = Tools.call("entry_outline", %{"content_type" => "Nope", "id" => 1}, c.context)
    assert message =~ "list_content_types"
  end

  test "modules and their contracts", c do
    %{modules: modules} = call!("list_modules", %{"content_type" => "Brando.Pages.Page"}, c.context)
    assert Enum.any?(modules, &(&1.module == "local:#{c.case_module.id}"))

    contract = call!("describe_module", %{"module" => "local:#{c.case_module.id}"}, c.context)
    assert contract.insertable
    slots = Map.new(contract.slots, &{&1.name, &1.settable})
    assert slots == %{"cover" => "image", "clip" => "video", "slot" => "image or video"}
    assert [%{key: "heading", settable: true}, %{key: "wide", settable: true}] = contract.variables
  end

  test "attachments and the media library", c do
    assert %{attachments: [%{alias: "image1", kind: "image", id: id}]} = call!("list_attachments", %{}, c.context)
    assert id == c.image.id

    %{assets: assets} = call!("search_assets", %{"kind" => "image", "query" => "Title one"}, c.context)
    assert Enum.any?(assets, &(&1.id == c.image.id))
    assert {:error, _} = Tools.call("search_assets", %{"kind" => "file"}, c.context)
  end

  test "prepare_proposal stores a version for review and refines it", c do
    op = %{
      "op" => "insert_block",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
      "module" => "local:#{c.case_module.id}",
      "values" => %{"heading" => "Lobby"},
      "media" => %{"cover" => "image1"}
    }

    first = call!("prepare_proposal", %{"summary" => "Add the lobby", "operations" => [op]}, c.context)
    assert %{applicable: true, version: 1, effects: %{inserted_blocks: 1, live: [live]}} = first
    assert live == "Brando.Pages.Page:#{c.identity.id}"

    assert {:ok, stored} = Proposals.get(first.proposal_id, c.user)
    assert stored.summary == "Add the lobby"
    assert stored.conversation_id == c.context.conversation_id
    assert [%{media: %{"cover" => {:image, image_id}}}] = stored.operations
    assert image_id == c.image.id

    # Nothing is written by preparing.
    assert length(Brando.Content.Transfer.Catalog.load!(Page, c.identity.id, c.user).entry_blocks) == 3

    context = %{c.context | proposal_id: first.proposal_id}
    wrong = put_in(op, ["media", "cover"], %{"kind" => "video", "id" => c.video.id})
    second = call!("prepare_proposal", %{"summary" => "Add the lobby", "operations" => [wrong]}, context)
    assert %{version: 2, applicable: false, problems: [%{operation: 0, code: :wrong_media_type}]} = second

    assert {:error, message} =
             Tools.call("prepare_proposal", %{"summary" => "x", "operations" => [%{"op" => "drop_table"}]}, context)

    assert message =~ "Operation 0"

    assert {:error, message} =
             Tools.call(
               "prepare_proposal",
               %{"summary" => "x", "operations" => [put_in(op, ["media", "cover"], "image9")]},
               context
             )

    assert message =~ "image9"
  end
end
