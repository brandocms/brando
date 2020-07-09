defmodule Brando.PagesTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Pages
  alias Brando.Factory

  test "get page in various forms" do
    p1 = Factory.insert(:page, key: "test/path")

    {:ok, page} = Pages.get_page(["test", "path"])
    assert page.id == p1.id
    assert page.key == "test/path"

    {:ok, page} = Pages.get_page("test/path")
    assert page.id == p1.id
    assert page.key == "test/path"

    {:ok, page} = Pages.get_page("test/path", "en")
    assert page.id == p1.id
    assert page.key == "test/path"

    {:error, _} = Pages.get_page("test/path", "sv")

    # {:ok, page} = Pages.get_page_with_children("test/path", "en")
    # assert page.id == p1.id
    # assert page.key == "test/path"

    {:ok, page} = Pages.get_page(nil, "test/path", "en")
    assert page.id == p1.id
    assert page.key == "test/path"

    p2 = Factory.insert(:page, key: "another", parent_id: p1.id)
    {:ok, page} = Pages.get_page("test/path", "another", "en")
    assert page.id == p2.id
    assert page.key == "another"
  end
end
