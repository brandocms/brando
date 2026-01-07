defmodule Brando.PagesTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  import Ecto.Query

  alias Brando.Pages
  alias Brando.Factory

  test "get page in various forms" do
    p1 = Factory.insert(:page, uri: "test/path")

    {:ok, page} = Pages.get_page(%{matches: %{path: ["test", "path"]}})
    assert page.id == p1.id
    assert page.uri == "test/path"

    {:ok, page} = Pages.get_page(%{matches: %{path: "test/path"}})
    assert page.id == p1.id
    assert page.uri == "test/path"

    {:ok, page} = Pages.get_page(%{matches: %{path: "test/path", language: "en"}})
    assert page.id == p1.id
    assert page.uri == "test/path"

    assert {:error, {:page, :not_found}} =
             Pages.get_page(%{matches: %{path: "test/path", language: "no"}})
  end

  test "get_fragment" do
    pf1 = Factory.insert(:fragment, key: "frag")
    {:ok, pf2} = Pages.get_fragment(%{matches: %{key: "frag"}})
    assert pf1.id == pf2.id

    {:ok, pf2} = Pages.get_fragment(pf1.id)
    assert pf1.id == pf2.id
  end

  test "get_fragments" do
    _pf1 = Factory.insert(:fragment, key: "frag1", parent_key: "parent")
    _pf2 = Factory.insert(:fragment, key: "frag2", parent_key: "parent")
    _pf3 = Factory.insert(:fragment, key: "frag3", parent_key: "parent")

    {:ok, frag_map} = Pages.get_fragments(%{filter: %{parent_key: "parent"}})

    f1 = Map.get(frag_map, "frag1")
    assert f1.key == "frag1"

    f2 = Map.get(frag_map, "frag2")
    assert f2.key == "frag2"
  end

  test "get_fragment from %Page{}" do
    p = Factory.insert(:page)

    _pf1 = Factory.insert(:fragment, key: "frag1", parent_key: "parent", page_id: p.id)
    _pf2 = Factory.insert(:fragment, key: "frag2", parent_key: "parent", page_id: p.id)
    _pf3 = Factory.insert(:fragment, key: "frag3", parent_key: "parent", page_id: p.id)

    {:ok, page} = Pages.get_page(%{matches: %{id: p.id}})
    frag = Pages.get_fragment(page, "frag1")
    assert frag.key == "frag1"
  end

  test "list_fragments" do
    _pf1 = Factory.insert(:fragment, key: "frag1", parent_key: "parent")

    _pf2 =
      Factory.insert(:fragment,
        key: "frag2",
        parent_key: "parent",
        deleted_at: DateTime.utc_now()
      )

    _pf3 = Factory.insert(:fragment, key: "frag3", parent_key: "parent")

    {:ok, fragments} = Pages.list_fragments(%{filter: %{parent_key: "parent"}})
    assert Enum.count(fragments) == 2

    {:ok, fragments} = Pages.list_fragments(%{filter: %{parent_key: "parent", language: "no"}})

    assert Enum.empty?(fragments)
  end

  test "list_fragments_translations" do
    _pf1 = Factory.insert(:fragment, key: "frag1", parent_key: "parent", sequence: 0)
    _pf2 = Factory.insert(:fragment, key: "frag2", parent_key: "parent", sequence: 3)
    _pf3 = Factory.insert(:fragment, key: "frag3", parent_key: "parent", sequence: 6)

    _pf4 =
      Factory.insert(:fragment,
        key: "frag1",
        parent_key: "parent",
        language: "no",
        sequence: 1
      )

    _pf5 =
      Factory.insert(:fragment,
        key: "frag2",
        parent_key: "parent",
        language: "no",
        sequence: 4
      )

    _pf6 =
      Factory.insert(:fragment,
        key: "frag3",
        parent_key: "parent",
        language: "no",
        sequence: 7
      )

    {:ok, frags} = Pages.list_fragments_translations("parent")

    assert Map.keys(frags) == ["frag1", "frag2", "frag3"]

    frag_tree = Enum.map(frags, fn {k, v} -> {k, Enum.map(v, & &1.language)} end)

    assert frag_tree == [
             {"frag1", [:en, :no]},
             {"frag2", [:en, :no]},
             {"frag3", [:en, :no]}
           ]

    {:ok, frags} = Pages.list_fragments_translations("parent", exclude_language: "en")

    frag_tree = Enum.map(frags, fn {k, v} -> {k, Enum.map(v, & &1.language)} end)

    assert frag_tree == [
             {"frag1", [:no]},
             {"frag2", [:no]},
             {"frag3", [:no]}
           ]
  end

  test "get_fragments/2" do
    _pf1 = Factory.insert(:fragment, key: "frag1", parent_key: "parent", language: "no")
    _pf2 = Factory.insert(:fragment, key: "frag2", parent_key: "parent", language: "no")
    _pf3 = Factory.insert(:fragment, key: "frag3", parent_key: "parent", language: "no")

    {:ok, frags} = Pages.get_fragments(%{filter: %{parent_key: "parent", language: "no"}})
    assert Map.keys(frags) == ["frag1", "frag2", "frag3"]

    {:ok, frags} = Pages.get_fragments(%{filter: %{parent_key: "parent", language: "en"}})
    assert frags == %{}
  end

  test "update_fragment" do
    u1 = Factory.insert(:random_user)
    pf1 = Factory.insert(:fragment, key: "frag1", parent_key: "parent", language: "no")
    {:ok, pf2} = Pages.update_fragment(pf1.id, %{key: "frag2"}, u1)
    assert pf2.key == "frag2"
    refute pf1.key == pf2.key
  end

  test "delete_fragment" do
    pf1 = Factory.insert(:fragment, key: "frag1", parent_key: "parent", language: "no")
    {:ok, pf2} = Pages.delete_fragment(pf1.id)
    refute pf2.deleted_at == nil
  end

  test "fetch_fragment non existing" do
    assert Pages.fetch_fragment("non_existing") |> Phoenix.HTML.safe_to_string() ==
             "<div class=\"page-fragment-missing\">\n             <strong>Missing page fragment</strong> <br />\n             key..: non_existing<br />\n             lang.: en\n           </div>"
  end

  test "fetch_fragment" do
    _pf1 =
      Factory.insert(:fragment,
        key: "frag1",
        parent_key: "parent",
        language: "no",
        rendered_blocks: "hello!"
      )

    assert Pages.fetch_fragment("frag1", "no") |> Phoenix.HTML.safe_to_string() == "hello!"
  end

  test "render_fragment" do
    pf1 =
      Factory.insert(:fragment,
        key: "frag1",
        parent_key: "parent",
        language: "no",
        rendered_blocks: "hello!"
      )

    assert Pages.render_fragment(pf1) |> Phoenix.HTML.safe_to_string() == "hello!"
  end

  test "render_fragment map of fragments" do
    _pf1 =
      Factory.insert(:fragment,
        key: "frag1",
        parent_key: "parent",
        language: "no",
        rendered_blocks: "fragment content!"
      )

    _pf2 =
      Factory.insert(:fragment,
        key: "frag2",
        parent_key: "parent",
        language: "no",
        rendered_blocks: "fragment content! 2"
      )

    _pf3 =
      Factory.insert(:fragment,
        key: "frag3",
        parent_key: "parent",
        language: "no",
        rendered_blocks: "fragment content! 3"
      )

    frags = Pages.get_fragments("parent", "no")

    assert Pages.render_fragment(frags, "non_existing") |> Phoenix.HTML.safe_to_string() =~
             "Missing page fragment"

    assert Pages.render_fragment(frags, "frag1") |> Phoenix.HTML.safe_to_string() ==
             "fragment content!"
  end

  test "render_fragment parent_key + key" do
    _pf1 =
      Factory.insert(:fragment,
        key: "frag1",
        parent_key: "parent",
        language: "no",
        rendered_blocks: "fragment content!"
      )

    _pf2 =
      Factory.insert(:fragment,
        key: "frag2",
        parent_key: "parent",
        language: "no",
        rendered_blocks: "fragment content! 2"
      )

    _pf3 =
      Factory.insert(:fragment,
        key: "frag3",
        parent_key: "parent",
        language: "no",
        rendered_blocks: "fragment content! 3"
      )

    assert Pages.render_fragment("parent", "non_existing") |> Phoenix.HTML.safe_to_string() =~
             "Missing page fragment"

    assert Pages.render_fragment("parent", "frag1") |> Phoenix.HTML.safe_to_string() ==
             "fragment content!"
  end

  test "duplicate_page duplicates fragments and child pages with their blocks and vars" do
    user = Factory.insert(:random_user)

    # Create a module for blocks
    module_params =
      Factory.params_for(:module, %{
        name: "test_module",
        namespace: "test",
        code: "<div>{{ test_var }}</div>",
        refs: [],
        vars: []
      })

    {:ok, module} = Brando.Content.create_module(module_params, user)

    # Helper to create a block with vars and refs
    create_page_block_with_vars = fn ->
      %Brando.Pages.Page.Blocks{
        block: %Brando.Content.Block{
          type: :module,
          source: "Elixir.Brando.Pages.Page.Blocks",
          module_id: module.id,
          uid: Brando.Utils.generate_uid(),
          refs: [
            %Brando.Content.Ref{
              name: "test_ref",
              description: "A test ref",
              uid: Brando.Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{text: "Hello from ref"}
              },
              sequence: 0
            }
          ],
          vars: [
            %Brando.Content.Var{
              type: :text,
              label: "Test Var",
              key: "test_var",
              value: "test value",
              creator: user
            }
          ]
        }
      }
      |> Ecto.Changeset.change()
      |> Map.put(:action, :insert)
    end

    create_fragment_block_with_vars = fn ->
      %Brando.Pages.Fragment.Blocks{
        block: %Brando.Content.Block{
          type: :module,
          source: "Elixir.Brando.Pages.Fragment.Blocks",
          module_id: module.id,
          uid: Brando.Utils.generate_uid(),
          refs: [
            %Brando.Content.Ref{
              name: "fragment_ref",
              description: "A fragment ref",
              uid: Brando.Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{text: "Hello from fragment ref"}
              },
              sequence: 0
            }
          ],
          vars: [
            %Brando.Content.Var{
              type: :text,
              label: "Test Var",
              key: "test_var",
              value: "test value",
              creator: user
            }
          ]
        }
      }
      |> Ecto.Changeset.change()
      |> Map.put(:action, :insert)
    end

    # Create parent page with blocks
    page_params = Factory.params_for(:page, %{title: "Parent Page", uri: "parent-page"})

    page_cs =
      %Brando.Pages.Page{}
      |> Brando.Pages.Page.changeset(page_params, user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [
        create_page_block_with_vars.()
      ])
      |> Ecto.Changeset.put_assoc(:vars, [
        %Brando.Content.Var{
          type: :text,
          label: "Page Var",
          key: "page_var",
          value: "page var value",
          creator: user
        }
      ])
      |> Map.put(:action, :insert)

    {:ok, parent_page} = Pages.create_page(page_cs, user)

    # Create fragments for the parent page
    fragment_params =
      Factory.params_for(:fragment, %{
        parent_key: "parent_page",
        key: "header",
        page_id: parent_page.id
      })

    fragment_cs =
      %Brando.Pages.Fragment{}
      |> Brando.Pages.Fragment.changeset(fragment_params, user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [
        create_fragment_block_with_vars.()
      ])
      |> Map.put(:action, :insert)

    {:ok, _fragment} = Pages.create_fragment(fragment_cs, user)

    # Create child page with blocks
    child_page_params =
      Factory.params_for(:page, %{
        title: "Child Page",
        uri: "child-page",
        parent_id: parent_page.id
      })

    child_page_cs =
      %Brando.Pages.Page{}
      |> Brando.Pages.Page.changeset(child_page_params, user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [
        create_page_block_with_vars.()
      ])
      |> Ecto.Changeset.put_assoc(:vars, [
        %Brando.Content.Var{
          type: :text,
          label: "Child Var",
          key: "child_var",
          value: "child var value",
          creator: user
        }
      ])
      |> Map.put(:action, :insert)

    {:ok, _child_page} = Pages.create_page(child_page_cs, user)

    # Duplicate the parent page
    {:ok, duplicated_page} = Pages.duplicate_page(parent_page.id, user)

    # Reload the duplicated page with all associations
    {:ok, duplicated_page} =
      Pages.get_page(%{
        matches: %{id: duplicated_page.id},
        preload: [
          :vars,
          entry_blocks: [block: [:vars, :refs]],
          fragments:
            from(f in Brando.Pages.Fragment,
              where: is_nil(f.deleted_at),
              order_by: [asc: f.sequence, asc: f.key],
              preload: [entry_blocks: [block: [:vars, :refs]]]
            ),
          children: [:vars, entry_blocks: [block: [:vars, :refs]]]
        ]
      })

    # Reload original page to ensure it still has its associations
    {:ok, original_page} =
      Pages.get_page(%{
        matches: %{id: parent_page.id},
        preload: [
          :vars,
          entry_blocks: [block: [:vars, :refs]],
          fragments:
            from(f in Brando.Pages.Fragment,
              where: is_nil(f.deleted_at),
              order_by: [asc: f.sequence, asc: f.key],
              preload: [entry_blocks: [block: [:vars, :refs]]]
            ),
          children: [:vars, entry_blocks: [block: [:vars, :refs]]]
        ]
      })

    # Assert duplicated page has different ID
    refute duplicated_page.id == parent_page.id

    # Assert page blocks are duplicated
    assert length(duplicated_page.entry_blocks) == 1
    duplicated_page_block = hd(duplicated_page.entry_blocks)
    original_page_block = hd(original_page.entry_blocks)
    refute duplicated_page_block.id == original_page_block.id
    refute duplicated_page_block.block.id == original_page_block.block.id

    # Assert page block vars are duplicated
    assert length(duplicated_page_block.block.vars) == 1
    duplicated_page_block_var = hd(duplicated_page_block.block.vars)
    original_page_block_var = hd(original_page_block.block.vars)
    refute duplicated_page_block_var.id == original_page_block_var.id
    assert duplicated_page_block_var.value == original_page_block_var.value

    # Assert page block refs are duplicated
    assert length(duplicated_page_block.block.refs) == 1
    duplicated_page_block_ref = hd(duplicated_page_block.block.refs)
    original_page_block_ref = hd(original_page_block.block.refs)
    refute duplicated_page_block_ref.id == original_page_block_ref.id
    refute duplicated_page_block_ref.uid == original_page_block_ref.uid
    assert duplicated_page_block_ref.name == original_page_block_ref.name

    # Assert page vars are duplicated
    assert length(duplicated_page.vars) == 1
    duplicated_page_var = hd(duplicated_page.vars)
    original_page_var = hd(original_page.vars)
    refute duplicated_page_var.id == original_page_var.id
    assert duplicated_page_var.value == original_page_var.value

    # Debug: Check if fragments were created correctly
    {:ok, all_fragments} = Pages.list_fragments(%{})

    fragments_for_original = Enum.filter(all_fragments, &(&1.page_id == original_page.id))
    _fragments_for_duplicated = Enum.filter(all_fragments, &(&1.page_id == duplicated_page.id))

    # Assert fragments are duplicated (not moved!)
    # Currently this will fail because fragments are being MOVED, not duplicated
    assert length(fragments_for_original) == 1,
           "Original page should still have its fragment, but fragment was moved. Fragment page_id: #{inspect(hd(all_fragments).page_id)}, Expected: #{original_page.id}"

    assert length(duplicated_page.fragments) == 1
    assert length(original_page.fragments) == 1

    duplicated_fragment = hd(duplicated_page.fragments)
    original_fragment = hd(original_page.fragments)

    refute duplicated_fragment.id == original_fragment.id
    assert duplicated_fragment.page_id == duplicated_page.id
    assert original_fragment.page_id == original_page.id
    assert duplicated_fragment.key == original_fragment.key

    # Assert fragment blocks are duplicated
    assert length(duplicated_fragment.entry_blocks) == 1
    duplicated_fragment_block = hd(duplicated_fragment.entry_blocks)
    original_fragment_block = hd(original_fragment.entry_blocks)
    refute duplicated_fragment_block.id == original_fragment_block.id
    refute duplicated_fragment_block.block.id == original_fragment_block.block.id

    # Assert fragment block vars are duplicated
    assert length(duplicated_fragment_block.block.vars) == 1

    # Assert child pages are duplicated
    assert length(duplicated_page.children) == 1
    assert length(original_page.children) == 1

    duplicated_child = hd(duplicated_page.children)
    original_child = hd(original_page.children)

    refute duplicated_child.id == original_child.id
    assert duplicated_child.parent_id == duplicated_page.id
    assert original_child.parent_id == original_page.id
    # Child title is appended with _dupl to distinguish it
    assert duplicated_child.title == "#{original_child.title}_dupl"

    # Assert child page blocks are duplicated
    assert length(duplicated_child.entry_blocks) == 1
    duplicated_child_block = hd(duplicated_child.entry_blocks)
    original_child_block = hd(original_child.entry_blocks)
    refute duplicated_child_block.id == original_child_block.id
    refute duplicated_child_block.block.id == original_child_block.block.id

    # Assert child page block vars are duplicated
    assert length(duplicated_child_block.block.vars) == 1

    # Assert child page vars are duplicated
    assert length(duplicated_child.vars) == 1
    duplicated_child_var = hd(duplicated_child.vars)
    original_child_var = hd(original_child.vars)
    refute duplicated_child_var.id == original_child_var.id
    assert duplicated_child_var.value == original_child_var.value
  end
end
