defmodule BrandoAdmin.MenuTest do
  use ExUnit.Case

  defmodule MenuItemBlueprint do
    use BrandoAdmin.Menu

    menus do
      menu_item Brando.BlueprintTest.Project
    end
  end

  defmodule MenuItemCustom do
    use BrandoAdmin.Menu

    menus do
      menu_item "Custom item", "https://customurl.com"
    end
  end

  defmodule MenuItemSubitem do
    use BrandoAdmin.Menu

    menus do
      menu_item "Projects" do
        menu_subitem "Index", "/admin/projects"
        menu_subitem "Create", "/admin/projects/new"
      end
    end
  end

  test "menu_item blueprint" do
    assert __MODULE__.MenuItemBlueprint.__menus__() == [
             %{name: "Projects", url: "/admin/projects/projects?status=published"}
           ]
  end

  test "menu_item custom" do
    assert __MODULE__.MenuItemCustom.__menus__() == [
             %{name: "Custom item", url: "https://customurl.com"}
           ]
  end

  test "menu_item subitem" do
    assert __MODULE__.MenuItemSubitem.__menus__() == [
             %{
               name: "Projects",
               items: [
                 %{name: "Index", url: "/admin/projects"},
                 %{name: "Create", url: "/admin/projects/new"}
               ],
               url: nil
             }
           ]
  end
end
