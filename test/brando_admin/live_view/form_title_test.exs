defmodule BrandoAdmin.LiveView.Form.TitleTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias BrandoAdmin.LiveView.Form.Hooks

  test "an entry's tab is titled by what it is" do
    page = Brando.Factory.insert(:page, title: "About")
    assert Hooks.form_title(Brando.Pages.Page, page.id) == "About — Page"
  end

  test "a new entry, and one that can't be found" do
    assert Hooks.form_title(Brando.Pages.Page, nil) == "New page"
    assert Hooks.form_title(Brando.Pages.Page, 0) == "Page"
  end
end
