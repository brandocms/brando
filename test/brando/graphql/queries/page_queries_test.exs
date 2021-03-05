defmodule Brando.GraphQL.Queries.PageQueriesTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory

  setup do
    u1 = Factory.insert(:random_user)
    opts = [context: %{current_user: u1}]

    {:ok, %{user: u1, opts: opts}}
  end

  @pages_query """
  query Pages ($order: Order, $limit: Int, $offset: Int, $filter: PageFilter, $status: String) {
    pages (order: $order, limit: $limit, offset: $offset, filter: $filter, status: $status) {
      entries {
        id
        title

        fragments {
          id
          title
        }

        children {
          id
          title
        }
      }
    }
  }
  """

  test "pages", %{opts: opts} do
    p1 = Factory.insert(:page, parent_id: nil)
    p2 = Factory.insert(:page, parent_id: p1.id)

    pf1 = Factory.insert(:page_fragment, page_id: p1.id)

    opts_with_filter =
      opts ++
        [
          variables: %{
            "filter" => %{"parents" => true}
          }
        ]

    assert Absinthe.run(
             @pages_query,
             BrandoIntegration.TestSchema,
             opts_with_filter
           ) ==
             {
               :ok,
               %{
                 data: %{
                   "pages" => %{
                     "entries" => [
                       %{
                         "children" => [
                           %{"id" => to_string(p2.id), "title" => "Title"}
                         ],
                         "fragments" => [
                           %{"id" => to_string(pf1.id), "title" => nil}
                         ],
                         "id" => to_string(p1.id),
                         "title" => "Title"
                       }
                     ]
                   }
                 }
               }
             }
  end

  @filtered_query """
    query Pages ($order: Order, $limit: Int, $offset: Int, $filter: PageFilter, $status: String) {
      pages (order: $order, limit: $limit, offset: $offset, filter: $filter, status: $status) {
        entries { title }
      }
    }
  """
  test "filtered pages", %{opts: opts} do
    _p1 = Factory.insert(:page, title: "test 1")
    _p2 = Factory.insert(:page, title: "hello 2")

    assert Absinthe.run(
             @filtered_query,
             BrandoIntegration.TestSchema,
             opts ++
               [
                 variables: %{
                   "order" => "desc id",
                   "filter" => %{"title" => "test"},
                   "status" => "published"
                 }
               ]
           ) ==
             {:ok, %{data: %{"pages" => %{"entries" => [%{"title" => "test 1"}]}}}}
  end

  @single_page_query """
  query page($matches: PageMatches) {
    page(matches: $matches) {
      id
      title
    }
  }
  """
  test "page(args)", %{opts: opts} do
    p1 = Factory.insert(:page)

    assert Absinthe.run(
             @single_page_query,
             BrandoIntegration.TestSchema,
             opts ++ [variables: %{"matches" => %{"id" => p1.id}}]
           ) ==
             {:ok, %{data: %{"page" => %{"id" => to_string(p1.id), "title" => "Title"}}}}
  end
end
