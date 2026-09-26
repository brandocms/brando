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
    assert [%{key: "heading", settable: "a string"}, %{key: "wide", settable: "true or false"}] = contract.variables
  end

  test "attachments and the media library", c do
    assert %{attachments: [%{alias: "image1", kind: "image", id: id}]} = call!("list_attachments", %{}, c.context)
    assert id == c.image.id

    %{assets: assets} = call!("search_assets", %{"kind" => "image", "query" => "Title one"}, c.context)
    assert Enum.any?(assets, &(&1.id == c.image.id))
    assert {:ok, %{assets: []}} = Tools.call("search_assets", %{"kind" => "file"}, c.context)
    assert {:error, _} = Tools.call("search_assets", %{"kind" => "gallery"}, c.context)
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

  test "guidance cannot make the assistant invent modules or settings", c do
    # Guidance names modules and settings the way editors see them. Whatever
    # the model makes of it, a setting the module lacks or a module the field
    # does not allow is a problem, never a write.
    base = %{
      "op" => "insert_block",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
      "module" => "local:#{c.case_module.id}"
    }

    narrow =
      call!(
        "prepare_proposal",
        %{"summary" => "Portrait pair", "operations" => [Map.put(base, "values", %{"narrow" => true})]},
        c.context
      )

    assert %{applicable: false, problems: [%{operation: 0}]} = narrow

    invented =
      call!(
        "prepare_proposal",
        %{"summary" => "Lede", "operations" => [Map.put(base, "module", "local:999999")]},
        c.context
      )

    assert %{applicable: false, problems: [%{operation: 0}]} = invented

    assert length(Brando.Content.Transfer.Catalog.load!(Page, c.identity.id, c.user).entry_blocks) == 3
  end

  describe "media by folder" do
    alias Brando.AI.Agent
    alias Brando.Factory
    alias Brando.Media.Folder
    alias Brando.Repo

    setup c do
      {:ok, conversation} = Agent.start_conversation(c.user)

      folder = fn scope, path, parent ->
        Repo.insert!(%Folder{scope: scope, name: Path.basename(path), path: path, parent_id: parent && parent.id})
      end

      a_form = folder.("images/default", "a_form", nil)
      details = folder.("images/default", "a_form/details", a_form)
      other = folder.("images/default", "clients/a_form", nil)
      empty = folder.("images/default", "empty", nil)

      image = fn folder, name ->
        Factory.insert(:image, creator_id: c.user.id, folder_id: folder.id, path: "images/default/#{folder.path}/#{name}")
      end

      # Inserted out of name order: the folder's order is by file name.
      images = for n <- Enum.shuffle(1..25), do: image.(a_form, "photo-#{String.pad_leading("#{n}", 2, "0")}.jpg")
      nested = [image.(details, "detail-1.jpg"), image.(details, "detail-2.jpg")]
      image.(other, "client.jpg")

      Factory.insert(:image,
        creator_id: c.user.id,
        folder_id: a_form.id,
        path: "images/default/a_form/zz-gone.jpg",
        deleted_at: DateTime.utc_now()
      )

      ordered = Enum.sort_by(images, & &1.path)
      context = %{c.context | conversation_id: conversation.id, attachments: %{}}

      %{
        conversation: conversation,
        context: context,
        a_form: a_form,
        details: details,
        other: other,
        empty: empty,
        ordered: ordered,
        nested: nested
      }
    end

    test "a folder name resolves to exact folders, and an ambiguous name returns every match", c do
      %{folders: folders, more: false} = call!("find_media_folders", %{"kind" => "image", "name" => "A_Form"}, c.context)

      assert [
               %{id: a_form, path: "images/default/a_form", items: 25, items_with_subfolders: 27, subfolders: 1},
               %{id: other, path: "images/default/clients/a_form", items: 1, subfolders: 0}
             ] = folders

      assert {a_form, other} == {c.a_form.id, c.other.id}

      assert %{folders: [%{id: id}]} =
               call!("find_media_folders", %{"kind" => "image", "name" => "default/a_form/"}, c.context)

      assert id == c.a_form.id

      # A partial name matches paths.
      assert %{folders: [%{id: id}]} = call!("find_media_folders", %{"kind" => "image", "name" => "detail"}, c.context)
      assert id == c.details.id

      # An empty folder is still found, and reported as empty.
      assert %{folders: [%{items: 0, items_with_subfolders: 0}]} =
               call!("find_media_folders", %{"kind" => "image", "name" => "empty"}, c.context)

      assert %{folders: []} = call!("find_media_folders", %{"kind" => "image", "name" => "nowhere"}, c.context)

      # No images in them: video folders are empty here.
      assert %{folders: [%{items: 0}, %{items: 0}]} =
               call!("find_media_folders", %{"kind" => "video", "name" => "a_form"}, c.context)

      assert {:error, _} = Tools.call("find_media_folders", %{"kind" => "image", "name" => " "}, c.context)
    end

    test "all of a folder is attached page by page, in file name order, and never stops at 20", c do
      first = call!("attach_folder", %{"kind" => "image", "folder_id" => c.a_form.id, "limit" => 10}, c.context)

      assert %{total: 25, offset: 0, next_offset: 10, remaining: 15, subfolders: false} = first
      assert first.note =~ "10 of 25"
      assert Enum.map(first.attached, & &1.alias) == Enum.map(1..10, &"image#{&1}")
      assert Enum.map(first.attached, & &1.id) == Enum.map(Enum.take(c.ordered, 10), & &1.id)

      rest =
        call!("attach_folder", %{"kind" => "image", "folder_id" => c.a_form.id, "offset" => 10, "limit" => 50}, c.context)

      assert %{total: 25, next_offset: nil, remaining: 0, unavailable: []} = rest
      assert rest.note == "All 25 are attached."
      assert Enum.map(rest.attached, & &1.alias) == Enum.map(11..25, &"image#{&1}")

      {:ok, conversation} = Agent.get_conversation(c.conversation.id, c.user)
      assert Enum.map(conversation.attachments, & &1["id"]) == Enum.map(c.ordered, & &1.id)

      # Selecting the folder again keeps every alias.
      again = call!("attach_folder", %{"kind" => "image", "folder_id" => c.a_form.id}, c.context)
      assert Enum.all?(again.attached, &(&1.new == false))
      assert Enum.map(again.attached, & &1.alias) == Enum.map(1..25, &"image#{&1}")
      {:ok, conversation} = Agent.get_conversation(c.conversation.id, c.user)
      assert length(conversation.attachments) == 25
    end

    test "subfolders are only included when asked for", c do
      with_nested =
        call!("attach_folder", %{"kind" => "image", "folder_id" => c.a_form.id, "subfolders" => true}, c.context)

      assert %{total: 27, subfolders: true, next_offset: nil} = with_nested
      ids = Enum.map(with_nested.attached, & &1.id)
      assert Enum.all?(c.nested, &(&1.id in ids))

      assert %{total: 0, attached: [], note: "The folder is empty."} =
               call!("attach_folder", %{"kind" => "image", "folder_id" => c.empty.id}, c.context)
    end

    test "folders are attached only in the user's own conversation", c do
      assert {:error, message} =
               Tools.call("attach_folder", %{"kind" => "image", "folder_id" => c.a_form.id}, %{
                 c.context
                 | conversation_id: nil
               })

      assert message =~ "conversation"

      someone = Factory.insert(:random_user)

      assert {:error, _} =
               Tools.call("attach_folder", %{"kind" => "image", "folder_id" => c.a_form.id}, %{c.context | actor: someone})

      assert {:error, _} = Tools.call("attach_folder", %{"kind" => "image", "folder_id" => -1}, c.context)

      {:ok, conversation} = Agent.get_conversation(c.conversation.id, c.user)
      assert conversation.attachments == []
    end
  end

  describe "child blocks" do
    setup c do
      c = Brando.ProposalFixtures.multi_context(c)
      c.video |> Ecto.Changeset.change(width: 720, height: 900) |> Brando.Repo.update!()
      c
    end

    test "entry_outline nests children with media dimensions and link titles", c do
      outline = call!("entry_outline", %{"content_type" => "Brando.Pages.Page", "id" => c.work.id}, c.context)

      assert [%{uid: intro} = text, %{uid: multi, multi: true, module_name: "Projects", children: children}] =
               outline.blocks.blocks

      assert intro == c.intro_uid and multi == c.multi_uid
      refute Map.has_key?(text, :children)
      assert Enum.map(children, & &1.uid) == c.child_uids
      assert Enum.map(children, & &1.type) == ~w(module_entry module_entry module_entry)
      assert Enum.map(children, & &1.values["size"]) == ~w(100 100 50)

      assert [%{media: %{"clip" => clip}, texts: %{"info" => "Alpha"}} | _] = children
      assert clip == %{kind: :video, id: c.video.id, width: 720, height: 900, orientation: "portrait"}
      refute outline[:note]
    end

    test "entry_outline shows switched-off refs, link titles and the entry's own media", c do
      [alpha | _] = c.child_uids
      block = Brando.Repo.get_by!(Brando.Content.Block, uid: alpha) |> Brando.Repo.preload(:refs)
      Enum.each(block.refs, &(&1 |> Ecto.Changeset.change(active: &1.name != "clip") |> Brando.Repo.update!()))

      Brando.Content.create_identifier(Page, c.identity)
      {:ok, identifier} = Brando.Content.get_identifier(Page, c.identity)

      Brando.Repo.insert!(%Brando.Content.Var{
        block_id: block.id,
        type: :link,
        key: "project",
        label: "Project",
        link_type: :identifier,
        identifier_id: identifier.id
      })

      c.work |> Ecto.Changeset.change(meta_image_id: c.image.id) |> Brando.Repo.update!()

      outline = call!("entry_outline", %{"content_type" => "Brando.Pages.Page", "id" => c.work.id}, c.context)
      [_, %{children: [first | _]}] = outline.blocks.blocks
      assert first.refs_off == ["clip"]
      assert first.values["project"] == %{entry: "Identity", content_type: "Brando.Pages.Page", id: c.identity.id}
      assert %{"meta_image" => %{kind: :image, id: id, width: _, height: _}} = outline.media
      assert id == c.image.id
    end

    test "settings are described, outlined and changes that do nothing are reported", c do
      [alpha | _] = c.child_uids
      contract = call!("describe_module", %{"module" => "local:#{c.project_module.id}"}, c.context)
      clip = Enum.find(contract.slots, &(&1.name == "clip"))
      assert Enum.any?(clip.settings, &(&1.key == :autoplay))
      info = Enum.find(contract.slots, &(&1.name == "info"))
      assert [%{key: :type, type: "one of", values: values}] = info.settings
      assert :lead in values

      target = %{"content_type" => "Brando.Pages.Page", "id" => c.work.id}

      ops = [
        %{
          "op" => "set_ref_config",
          "target" => target,
          "block_uid" => alpha,
          "ref" => "clip",
          "config" => %{"loop" => true}
        },
        %{"op" => "set_block_active", "target" => target, "block_uid" => alpha, "active" => true}
      ]

      result = call!("prepare_proposal", %{"summary" => "Loop", "operations" => ops}, c.context)
      assert %{applicable: true, unchanged: %{operations: [%{operation: 1, message: message}]}} = result
      assert message =~ "already on"

      {:ok, proposal} = Proposals.get(result.proposal_id, c.user)
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)

      outline = call!("entry_outline", %{"content_type" => "Brando.Pages.Page", "id" => c.work.id}, c.context)
      [_, %{children: [first | _]}] = outline.blocks.blocks
      assert first.settings == %{"clip" => %{loop: true}}
    end

    test "list_modules offers multi modules at the root", c do
      %{modules: modules} = call!("list_modules", %{"content_type" => "Brando.Pages.Page"}, c.context)
      assert %{multi: true, name: "Projects"} = Enum.find(modules, &(&1.module == "local:#{c.projects_module.id}"))
      refute Enum.any?(modules, &(&1.module == "local:#{c.project_module.id}"))
    end

    test "describe_module lists a multi module's entry modules and their variables", c do
      contract = call!("describe_module", %{"module" => "local:#{c.projects_module.id}"}, c.context)
      refute contract.insertable
      assert contract.note =~ "parent"
      assert [%{module: module, name: "Project", variables: [size]}] = contract.entries
      assert module == "local:#{c.project_module.id}"
      assert %{key: "size", options: [%{value: "50", label: "Half"}, %{value: "100", label: "Full"}]} = size

      entry = call!("describe_module", %{"module" => module}, c.context)
      assert entry.entry_of == "local:#{c.projects_module.id}"
    end

    test "prepare_proposal changes, moves and inserts children", c do
      [alpha, beta, gamma] = c.child_uids
      target = %{"content_type" => "Brando.Pages.Page", "id" => c.work.id}

      ops = [
        %{"op" => "set_block_values", "target" => target, "block_uid" => beta, "values" => %{"size" => "50"}},
        %{"op" => "move_block", "target" => target, "block_uid" => alpha, "placement" => %{"after" => gamma}},
        %{
          "op" => "insert_block",
          "target" => target,
          "module" => "local:#{c.project_module.id}",
          "parent" => c.multi_uid,
          "placement" => %{"before" => beta},
          "values" => %{"size" => "50"}
        }
      ]

      result = call!("prepare_proposal", %{"summary" => "Pair the projects", "operations" => ops}, c.context)
      assert %{applicable: true, effects: %{updated_blocks: 1, moved_blocks: 1, inserted_blocks: 1}} = result

      bad = [%{"op" => "move_block", "target" => target, "block_uid" => alpha, "placement" => %{"after" => c.intro_uid}}]
      result = call!("prepare_proposal", %{"summary" => "x", "operations" => bad}, c.context)
      # Next to a root block means to the root, which takes no project entries.
      assert %{applicable: false, problems: [%{code: :module_not_allowed}]} = result
    end
  end
end
