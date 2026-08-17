defmodule BrandoAdmin.MenuTest do
  use ExUnit.Case

  defmodule MenuItemBlueprint do
    @moduledoc false
    use BrandoAdmin.Menu

    menus do
      menu_item Brando.BlueprintTest.Project
    end
  end

  defmodule MenuItemCustom do
    @moduledoc false
    use BrandoAdmin.Menu

    menus do
      menu_item "Custom item", "https://customurl.com"
    end
  end

  defmodule MenuItemSubitem do
    @moduledoc false
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

  test "publishing is only present for the selected static site" do
    static_menu = BrandoAdmin.Menu.get_menu(nil, %Brando.Sites.Site{delivery_mode: :static})
    dynamic_menu = BrandoAdmin.Menu.get_menu(nil, %Brando.Sites.Site{delivery_mode: :dynamic})

    assert menu_urls(static_menu) =~ "/admin/config/publishing"
    refute menu_urls(dynamic_menu) =~ "/admin/config/publishing"
  end

  test "frontend assets is translated in the Norwegian menu" do
    menu_names =
      Gettext.with_locale("no", fn ->
        %{role: :superuser}
        |> BrandoAdmin.Menu.get_menu()
        |> menu_names()
      end)

    assert "Frontend-ressurser" in menu_names
  end

  defp menu_urls(menus) do
    menus
    |> Enum.flat_map(fn menu -> List.wrap(menu[:url]) ++ List.wrap(menu[:items] && menu_urls(menu.items)) end)
    |> Enum.join(" ")
  end

  defp menu_names(menus) do
    Enum.flat_map(menus, fn menu -> [menu.name | menu_names(List.wrap(menu[:items]))] end)
  end
end
