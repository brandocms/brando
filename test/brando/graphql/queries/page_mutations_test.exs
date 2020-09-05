defmodule Brando.GraphQL.Mutations.PageMutationsTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory

  setup do
    u1 = Factory.insert(:random_user)
    opts = [context: %{current_user: u1}]

    {:ok, %{user: u1, opts: opts}}
  end

  @update_page """
  mutation UpdatePage($pageId: ID!, $pageParams: PageParams) {
    updatePage(
      pageId: $pageId,
      pageParams: $pageParams
    ) {
      title
    }
  }
  """

  test "update page", %{opts: opts} do
    p1 = Factory.insert(:page)

    assert Absinthe.run(
             @update_page,
             BrandoIntegration.TestSchema,
             opts ++
               [
                 variables: %{
                   "pageId" => p1.id,
                   "pageParams" => %{
                     "title" => "A new title!"
                   }
                 }
               ]
           ) ==
             {:ok, %{data: %{"updatePage" => %{"title" => "A new title!"}}}}
  end
end
