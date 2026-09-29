defmodule BrandoAdmin.HooksPageTitleTest do
  # A screen without a page title of its own takes its menu item's name.
  use ExUnit.Case, async: true

  alias BrandoAdmin.Hooks

  @sections [
    %{
      name: "System",
      items: [
        %{name: "Dashboard", url: "/admin"},
        %{
          name: "Configuration",
          url: nil,
          items: [
            %{name: "Cache", url: "/admin/config/cache"},
            %{name: "Navigation", url: "/admin/config/navigation/menus"}
          ]
        }
      ]
    },
    %{name: "Content", items: [%{name: "Cases", url: "/admin/cases/cases?status=published"}]}
  ]

  test "matches a menu item's URL, ignoring its query" do
    assert Hooks.menu_title(@sections, "/admin") == "Dashboard"
    assert Hooks.menu_title(@sections, "/admin/config/cache") == "Cache"
    assert Hooks.menu_title(@sections, "/admin/cases/cases") == "Cases"
  end

  test "falls back to the item the path is under, but never to the dashboard" do
    assert Hooks.menu_title(@sections, "/admin/config/navigation/menus/update/2") == "Navigation"
    assert Hooks.menu_title(@sections, "/admin/unknown") == nil
  end
end
