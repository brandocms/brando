defmodule Brando.Guides.WorkflowsTest do
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Navigation
  alias Brando.Pages

  setup do
    put_test_env(:tenancy_mode, :none)
    put_test_env(:authorization_mode, :legacy)
    user = Factory.insert(:random_user, role: :superuser)
    %{user: user}
  end

  # Brando.Setup.Seeds refills the identity, SEO and navigation caches from
  # this test's sandboxed rows, which roll back while the caches stay.
  defp restore_caches do
    cached = Map.new(~w(identity seo navigation)a, &{&1, Brando.Cache.get(&1)})

    on_exit(fn ->
      Enum.each(cached, fn
        {key, nil} -> Brando.Cache.del(key)
        {key, value} -> Brando.Cache.put(key, value, :infinite)
      end)
    end)
  end

  test "fresh-install seeds render translated homepages that can be edited and reloaded", %{user: user} do
    restore_caches()
    # What `mix brando.setup` seeds, for every configured language.
    {:ok, _report} = Brando.Setup.Seeds.run(user)

    for language <- ["en", "no"] do
      assert {:ok, page} =
               Pages.get_page(%{
                 matches: %{path: ["index"], language: language, has_url: true},
                 status: :published
               })

      assert page.template == "index.html"
      assert page.rendered_blocks =~ "<h1>"
      assert page.rendered_blocks =~ "mix brando.setup"
      assert {:ok, menu} = Navigation.get_menu("main", language)
      assert length(menu.items) == 2
      assert Enum.all?(menu.items, &(&1.link.type == :link))
    end

    {:ok, page} = Pages.get_page(%{matches: %{path: ["index"], language: "en"}})
    assert {:ok, _} = Pages.update_page(page, %{title: "Studio homepage"}, user)
    assert {:ok, reloaded} = Pages.get_page(page.id)
    assert reloaded.title == "Studio homepage"
    assert reloaded.rendered_blocks =~ "mix brando.setup"
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
