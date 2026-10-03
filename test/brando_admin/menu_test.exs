defmodule BrandoAdmin.MenuTest do
  use ExUnit.Case
  # The menu asks the database whether there are global sets.
  use Brando.ConnCase

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

  test "Globals is only in the menu when there are global sets" do
    refute menu_urls(BrandoAdmin.Menu.get_menu(nil)) =~ "/admin/globals"

    Brando.Repo.insert!(%Brando.Sites.GlobalSet{label: "Gallery", key: "gallery", language: :en})

    assert menu_urls(BrandoAdmin.Menu.get_menu(nil)) =~ "/admin/globals"
  end

  test "submissions are in the content menu once a form is configured" do
    menu = BrandoAdmin.Menu.get_menu(nil)
    assert menu_urls(menu) =~ "/admin/config/forms"
    refute content_urls(menu) =~ "/admin/forms"

    user = Brando.Factory.insert(:random_user)

    {:ok, _} =
      Brando.Forms.create_form(%{"title" => "Contact", "key" => "contact", "language" => "en", "status" => "draft"}, user)

    assert content_urls(BrandoAdmin.Menu.get_menu(nil)) =~ "/admin/forms"
  end

  defp content_urls(menu) do
    menu |> Enum.find(&(&1.name == "Content")) |> Map.fetch!(:items) |> Enum.map_join(" ", & &1.url)
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

  test "an editor gets the editing tools under Configuration, not the setup tools" do
    editor = menu_urls(BrandoAdmin.Menu.get_menu(%{role: :editor}))
    superuser = menu_urls(BrandoAdmin.Menu.get_menu(%{role: :superuser}))

    for url <- ["/admin/config/navigation/menus", "/admin/config/identity", "/admin/config/seo"] do
      assert editor =~ url
    end

    for url <- ["/admin/config/global_sets", "/admin/config/cache", "/admin/config/content/modules"] do
      refute editor =~ url
      assert superuser =~ url
    end
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
