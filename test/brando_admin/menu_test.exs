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

  defmodule MenuItemIcons do
    @moduledoc false
    use BrandoAdmin.Menu

    menus do
      menu_item Brando.Pages.Page, icon: "house"
      menu_item "Custom item", "https://customurl.com", icon: "globe"

      menu_item "Projects", icon: "folder" do
        menu_subitem "Index", "/admin/projects", icon: "list"
        menu_subitem Brando.Pages.Page
      end
    end
  end

  test "menu_item blueprint" do
    assert __MODULE__.MenuItemBlueprint.__menus__() == [
             %{name: "Projects", url: "/admin/projects/projects?status=published", icon: "file"}
           ]
  end

  test "menu_item custom" do
    assert __MODULE__.MenuItemCustom.__menus__() == [
             %{name: "Custom item", url: "https://customurl.com", icon: "dot"}
           ]
  end

  test "menu_item subitem" do
    assert __MODULE__.MenuItemSubitem.__menus__() == [
             %{
               name: "Projects",
               items: [
                 %{name: "Index", url: "/admin/projects", icon: "dot"},
                 %{name: "Create", url: "/admin/projects/new", icon: "dot"}
               ],
               url: nil,
               icon: "dot"
             }
           ]
  end

  test "menu items take an icon option, and blueprint items default to the blueprint's" do
    [page, custom, projects] = __MODULE__.MenuItemIcons.__menus__()

    assert page.icon == "house"
    assert custom.icon == "globe"
    assert projects.icon == "folder"
    assert [%{icon: "list"}, %{icon: "file-text"}] = projects.items
  end

  test "unknown menu icons fail at compile time" do
    assert_raise ArgumentError, ~r/unknown menu icon "nope", see https:\/\/lucide.dev\/icons/, fn ->
      Code.compile_quoted(
        quote do
          defmodule BrandoAdmin.MenuTest.BadIcon do
            use BrandoAdmin.Menu

            menus do
              menu_item "Bad", "/admin/bad", icon: "nope"
            end
          end
        end
      )
    end

    assert_raise ArgumentError, ~r/use "house"/, fn ->
      Code.compile_quoted(
        quote do
          defmodule BrandoAdmin.MenuTest.AliasIcon do
            use BrandoAdmin.Menu

            menus do
              menu_item "Old", "/admin/old", icon: "home"
            end
          end
        end
      )
    end
  end

  test "every system menu item has an icon" do
    menu = BrandoAdmin.Menu.get_menu(%Brando.Users.User{role: :superuser})

    for section <- menu, item <- section.items, entry <- [item | Map.get(item, :items) || []] do
      assert Brando.Icons.exists?(entry[:icon]), "#{inspect(entry.name)} has no valid icon"
    end
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

  describe "Configuration's groups" do
    test "a superuser gets every group, in order, with its items in order" do
      assert [
               {:site,
                [
                  "/admin/config/navigation/menus",
                  "/admin/config/forms",
                  "/admin/config/identity",
                  "/admin/config/seo",
                  "/admin/config/global_sets"
                ]},
               {:publishing, ["/admin/config/scheduled_publishing", "/admin/config/import-export"]},
               {:building_blocks,
                [
                  "/admin/config/content/modules",
                  "/admin/config/content/module_sets",
                  "/admin/config/content/containers",
                  "/admin/config/content/templates",
                  "/admin/config/content/table_templates",
                  "/admin/config/content/palettes",
                  "/admin/config/markdown-sources"
                ]},
               {:system,
                [
                  "/admin/groups",
                  "/admin/config/activity",
                  "/admin/config/integrations",
                  "/admin/config/assistant",
                  "/admin/config/assets",
                  "/admin/config/cache",
                  "/admin/config/utils"
                ]}
             ] = configuration_groups(%{role: :superuser})
    end

    test "the flat item list keeps every item, in group order" do
      configuration = configuration(%{role: :superuser})

      assert Enum.map(configuration.items, & &1.url) ==
               configuration |> BrandoAdmin.Menu.grouped_items() |> Enum.flat_map(& &1.items) |> Enum.map(& &1.url)

      assert Enum.all?(configuration.items, &(&1.group in [:site, :publishing, :building_blocks, :system]))
    end

    test "a static site's Publishing joins the publishing group" do
      groups = configuration_groups(%{role: :superuser}, %Brando.Sites.Site{delivery_mode: :static})

      assert {:publishing, ["/admin/config/scheduled_publishing", "/admin/config/publishing", _]} =
               List.keyfind(groups, :publishing, 0)
    end

    test "a group with nothing left for the user is left out, heading and all" do
      assert [:site, :publishing] = Keyword.keys(configuration_groups(%{role: :editor}))
      assert [:site, :publishing, :system] = Keyword.keys(configuration_groups(%{role: :admin}))

      assert {:system, ["/admin/config/activity" | _]} =
               List.keyfind(configuration_groups(%{role: :admin}), :system, 0)
    end

    test "the group names are translated" do
      names =
        Gettext.with_locale("no", fn ->
          %{role: :superuser} |> configuration() |> BrandoAdmin.Menu.grouped_items() |> Enum.map(& &1.name)
        end)

      assert names == ["Nettsted", "Publisering", "Byggeklosser", "System"]
    end
  end

  describe "grouped_items/1" do
    test "a submenu without groups is one group without a heading" do
      items = [%{name: "Index", url: "/admin/projects"}, %{name: "Create", url: "/admin/projects/new"}]

      assert [%{key: nil, name: nil, items: ^items}] = BrandoAdmin.Menu.grouped_items(%{name: "Projects", items: items})
    end

    test "items outside the groups come last, without a heading, and empty groups are dropped" do
      a = %{name: "A", url: "/a", group: :one}
      b = %{name: "B", url: "/b"}
      c = %{name: "C", url: "/c", group: :unknown}

      item = %{name: "X", items: [b, a, c], groups: [%{key: :one, name: "One"}, %{key: :two, name: "Two"}]}

      assert [%{key: :one, name: "One", items: [^a]}, %{key: nil, name: nil, items: [^b, ^c]}] =
               BrandoAdmin.Menu.grouped_items(item)
    end

    test "a link has no groups" do
      assert [] = BrandoAdmin.Menu.grouped_items(%{name: "Users", url: "/admin/users"})
    end
  end

  defp configuration(user, site \\ nil) do
    user
    |> BrandoAdmin.Menu.get_menu(site)
    |> Enum.flat_map(& &1.items)
    |> Enum.find(&(&1[:key] == :configuration))
  end

  defp configuration_groups(user, site \\ nil) do
    user
    |> configuration(site)
    |> BrandoAdmin.Menu.grouped_items()
    |> Enum.map(&{&1.key, Enum.map(&1.items, fn item -> item.url end)})
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
