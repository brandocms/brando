defmodule Brando.Guides.WorkflowsTest do
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Navigation
  alias Brando.Pages

  @seeds Path.expand("../../..", __DIR__)
         |> Path.join("priv/templates/brando.install/repo/seeds.exs")

  setup do
    put_test_env(:tenancy_mode, :none)
    put_test_env(:authorization_mode, :legacy)
    user = Factory.insert(:random_user, role: :superuser)
    %{user: user}
  end

  test "fresh-install seeds render translated homepages that can be edited and reloaded", %{user: user} do
    # Use the account created by this sandbox rather than requiring sequence ID 1.
    @seeds
    |> EEx.eval_file(application_module: "BrandoIntegration")
    |> String.replace("Repo.get_by!(Brando.Users.User, id: 1)", "Repo.get_by!(Brando.Users.User, id: #{user.id})")
    |> Code.eval_string()

    for language <- ["en", "no"] do
      assert {:ok, page} =
               Pages.get_page(%{
                 matches: %{path: ["index"], language: language, has_url: true},
                 status: :published
               })

      assert page.template == "default.html"
      assert page.rendered_blocks =~ "<h1>Welcome to Brando!</h1>"
      assert {:ok, menu} = Navigation.get_menu("main", language)
      assert length(menu.items) == 3
      assert Enum.all?(menu.items, &(&1.link.type == :link))
    end

    {:ok, page} = Pages.get_page(%{matches: %{path: ["index"], language: "en"}})
    assert {:ok, _} = Pages.update_page(page, %{title: "Studio homepage"}, user)
    assert {:ok, reloaded} = Pages.get_page(page.id)
    assert reloaded.title == "Studio homepage"
    assert reloaded.rendered_blocks =~ "Welcome to Brando!"
  end

  test "the navigation recipe saves nested links and keeps menu languages separate", %{user: user} do
    for {language, text, url} <- [{"en", "About us", "/about"}, {"no", "Om oss", "/no/om"}] do
      assert {:ok, menu} =
               Navigation.create_menu(
                 %{
                   title: "Main navigation",
                   key: "guide-main",
                   language: language,
                   status: :published,
                   items: [
                     %{
                       key: "about",
                       status: :published,
                       sequence: 0,
                       link: %{
                         type: :link,
                         key: "link",
                         label: "Link",
                         link_type: :url,
                         link_text: text,
                         value: url
                       }
                     }
                   ]
                 },
                 user
               )

      [parent] = menu.items

      assert {:ok, _} =
               Navigation.create_item(
                 %{
                   parent_id: parent.id,
                   key: "team",
                   sequence: 0,
                   status: :published,
                   link: %{
                     type: :link,
                     key: "link",
                     label: "Link",
                     link_type: :url,
                     link_text: "Team",
                     value: url <> "/team"
                   }
                 },
                 user
               )

      assert {:ok, reloaded} = Navigation.get_menu("guide-main", language)
      assert [item] = reloaded.items
      assert item.link.value == url
      assert [child] = item.children
      assert child.link.value == url <> "/team"
    end

    assert {:error, {:menu, :not_found}} = Navigation.get_menu("missing-menu", "en")
  end

  test "published URL queries omit drafts and pages without public URLs", %{user: user} do
    for {language, uri, status, has_url} <- [
          {"en", "about", :published, true},
          {"no", "om", :published, true},
          {"en", "unfinished", :draft, true},
          {"en", "internal", :published, false}
        ] do
      {:ok, _page} =
        Pages.create_page(
          %{
            title: uri,
            uri: uri,
            language: language,
            status: status,
            template: "default.html",
            has_url: has_url
          },
          user
        )
    end

    {:ok, pages} =
      Pages.list_pages(%{
        filter: %{has_url: true},
        status: :published,
        select: {:struct, [:id, :title, :uri, :language, :updated_at]}
      })

    assert Enum.sort(Enum.map(pages, & &1.uri)) == ["about", "om"]
    assert Enum.all?(pages, &(Brando.Blueprint.URL.resolve(&1, :with_host) =~ "http://localhost/"))
  end
end
