defmodule Brando.Pages.PageTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  require Forge
  alias Brando.Page

  setup do
    user = Forge.saved_user(TestRepo)
    Forge.having creator: user do
      page = Forge.saved_page(TestRepo)
    end
    {:ok, %{user: user, page: page}}
  end

  test "search" do
    results = Page.search("en", "text")
    assert length(results) == 1
    p = results |> List.first
    assert p.title == "Page title"
  end

  test "meta", %{page: page} do
    assert Brando.Page.__name__(:singular) == "page"
    assert Brando.Page.__name__(:plural) == "pages"
    assert Brando.Page.__repr__(page) == "Page title"
  end

  test "delete", %{page: page} do
    refute Brando.repo.all(Page) == []
    Page.delete(page.id)
    assert Brando.repo.all(Page) == []
  end
end
