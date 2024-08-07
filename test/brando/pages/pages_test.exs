defmodule Brando.PagesTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

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
end
