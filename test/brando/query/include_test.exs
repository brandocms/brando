defmodule Brando.Query.IncludeTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Pages.Page

  defmodule Context do
    use Brando.Query

    import Ecto.Query

    query :list, Page do
      fn query -> from(entry in query) end
    end

    filters Page do
      fn
        {:title, title}, query -> from entry in query, where: entry.title == ^title
      end
    end

    query :single, Page do
      fn query -> from(entry in query) end
    end

    matches Page do
      fn
        {:id, id}, query -> from entry in query, where: entry.id == ^id
      end
    end
  end

  test "recursively selects, orders, and loads included associations" do
    parent = Factory.insert(:page, title: "Include parent")
    alpha_child = Factory.insert(:page, title: "Alpha child", parent_id: parent.id)
    zulu_child = Factory.insert(:page, title: "Zulu child", parent_id: parent.id)
    grandchild = Factory.insert(:page, title: "Grandchild", parent_id: zulu_child.id)

    {:ok, [result]} =
      Context.list_pages(%{
        filter: %{title: parent.title},
        select: {:struct, [:id, :title]},
        include: [
          children: [
            select: [:id, :parent_id, :title],
            order: "desc title",
            include: [
              children: [select: [:id, :parent_id, :title]]
            ]
          ]
        ]
      })

    assert result.id == parent.id
    assert result.uri == nil
    assert Enum.map(result.children, & &1.title) == [zulu_child.title, alpha_child.title]

    included_zulu_child = Enum.find(result.children, &(&1.id == zulu_child.id))
    assert Enum.map(included_zulu_child.children, & &1.id) == [grandchild.id]

    included_alpha_child = Enum.find(result.children, &(&1.id == alpha_child.id))
    assert included_alpha_child.children == []
  end

  test "supports include on single queries" do
    parent = Factory.insert(:page, title: "Single include parent")
    child = Factory.insert(:page, title: "Single include child", parent_id: parent.id)

    assert {:ok, result} =
             Context.get_page(%{
               matches: %{id: parent.id},
               select: {:struct, [:id, :title]},
               include: [children: [select: [:id, :parent_id, :title]]]
             })

    assert result.id == parent.id
    assert Enum.map(result.children, & &1.id) == [child.id]

    bang_result =
      Context.get_page!(%{
        matches: %{id: parent.id},
        select: {:struct, [:id, :title]},
        include: [children: [select: [:id, :parent_id, :title]]]
      })

    assert Enum.map(bang_result.children, & &1.id) == [child.id]
  end

  test "adds included associations to map selections" do
    parent = Factory.insert(:page, title: "Map include parent")
    child = Factory.insert(:page, title: "Map include child", parent_id: parent.id)

    assert {:ok, [result]} =
             Context.list_pages(%{
               filter: %{title: parent.title},
               select: [:id, :title],
               include: [children: [select: [:id, :parent_id, :title]]]
             })

    assert result.id == parent.id
    assert Enum.map(result.children, & &1.id) == [child.id]
  end

  test "accepts a custom query as an include starting point" do
    parent = Factory.insert(:page, title: "Custom query parent")
    included_child = Factory.insert(:page, title: "Included child", parent_id: parent.id)
    _excluded_child = Factory.insert(:page, title: "Excluded child", parent_id: parent.id)

    children_query =
      from child in Page,
        where: child.title == "Included child",
        select: [:id, :parent_id, :title]

    {:ok, [result]} =
      Context.list_pages(%{
        filter: %{title: parent.title},
        include: [
          children: [query: children_query]
        ]
      })

    assert Enum.map(result.children, & &1.id) == [included_child.id]
  end

  test "requires parent association keys in partial selections" do
    query = Brando.Query.with_select(Page, {:struct, [:title]})

    assert_raise ArgumentError, ~r/include :children requires :id to be selected/, fn ->
      Brando.Query.with_include(query, [:children])
    end

    query = Brando.Query.with_select(Page, {:struct, [:id]})

    assert_raise ArgumentError, ~r/include :parent requires :parent_id to be selected/, fn ->
      Brando.Query.with_include(query, [:parent])
    end
  end

  test "rejects associations configured through both preload and include" do
    query = Brando.Query.with_preload(Page, [:children])

    assert_raise ArgumentError, ~r/configured through both :preload and :include/, fn ->
      Brando.Query.with_include(query, [:children])
    end

    parent = Factory.insert(:page, title: "Default preload parent")
    child = Factory.insert(:page, title: "Default preload child", parent_id: parent.id)

    assert_raise ArgumentError, ~r/configured through both :preload and :include/, fn ->
      Brando.Pages.get_page(%{matches: %{id: child.id}, include: [:parent]})
    end
  end

  test "allows legacy preloads and includes for different associations" do
    query =
      Page
      |> Brando.Query.with_preload([:parent])
      |> Brando.Query.with_include([:children])

    assert :parent in query.preloads
    assert Keyword.has_key?(query.preloads, :children)
  end

  test "reports unknown associations and include options" do
    assert_raise ArgumentError, ~r/has no association named :unknown/, fn ->
      Brando.Query.with_include(Page, [:unknown])
    end

    assert_raise ArgumentError, ~r/unsupported options \[:limit\]/, fn ->
      Brando.Query.with_include(Page, children: [limit: 1])
    end

    assert_raise ArgumentError, ~r/unsupported options \[:order_by\]/, fn ->
      Brando.Query.with_include(Page, children: [order_by: [asc: :title]])
    end
  end
end
