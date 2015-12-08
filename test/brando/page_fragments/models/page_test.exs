defmodule Brando.Pages.PageFragmentTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  require Forge
  alias Brando.PageFragment

  setup do
    user = Forge.saved_user(TestRepo)
    Forge.having creator: user do
      page = Forge.saved_page_fragment(TestRepo)
    end
    {:ok, %{user: user, page: page}}
  end

  test "meta", %{page: page} do
    assert Brando.PageFragment.__name__(:singular) == "page fragment"
    assert Brando.PageFragment.__name__(:plural) == "page fragments"
    assert Brando.PageFragment.__repr__(page) == "key/path"
  end

  test "delete", %{page: page} do
    refute Brando.repo.all(PageFragment) == []
    PageFragment.delete(page.id)
    assert Brando.repo.all(PageFragment) == []
  end

  test "encode data", %{page: page} do
    assert Brando.PageFragment.encode_data(%{data: "test"})
           == %{data: "test"}
    assert Brando.PageFragment.encode_data(%{data: [%{data: "test"}]})
           == %{data: ~s([{"data":"test"}])}
  end
end
