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
  query {
    pages {
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
  """

  test "pages", %{opts: opts} do
    p1 = Factory.insert(:page)
    p2 = Factory.insert(:page, parent_id: p1.id)

    pf1 = Factory.insert(:page_fragment, page_id: p1.id)

    assert Absinthe.run(
             @pages_query,
             Brando.Integration.TestSchema,
             opts
           ) ==
             {
               :ok,
               %{
                 data: %{
                   "pages" => [
                     %{
                       "children" => [
                         %{"id" => to_string(p2.id), "title" => "Title"}
                       ],
                       "fragments" => [%{"id" => to_string(pf1.id), "title" => nil}],
                       "id" => to_string(p1.id),
                       "title" => "Title"
                     }
                   ]
                 }
               }
             }
  end

  @page_id_query """
  query page($pageId: ID) {
    page(pageId: $pageId) {
      id
      title
    }
  }
  """
  test "page(id)", %{opts: opts} do
    p1 = Factory.insert(:page)

    assert Absinthe.run(
             @page_id_query,
             Brando.Integration.TestSchema,
             opts ++ [variables: %{"pageId" => p1.id}]
           ) ==
             {:ok, %{data: %{"page" => %{"id" => to_string(p1.id), "title" => "Title"}}}}
  end
end
