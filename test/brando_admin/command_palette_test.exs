defmodule BrandoAdmin.CommandPaletteTest do
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Content.Identifier
  alias Brando.Factory
  alias BrandoAdmin.CommandPalette

  @content ~w(brando.admin.access brando.pages.read brando.pages.update)

  defp identify(page, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Identifier{
          schema: Brando.Pages.Page,
          entry_id: page.id,
          title: page.title,
          status: page.status,
          language: String.to_atom(to_string(page.language)),
          updated_at: DateTime.utc_now(:second)
        },
        attrs
      )
    )
  end

  defp page(title, attrs \\ []) do
    page = Factory.insert(:page, Keyword.merge([title: title, status: :published, language: :en], attrs))
    identify(page)
    page
  end

  defp titles(items), do: Enum.map(items, & &1.label)

  describe "entries with groups" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      owner = Factory.insert(:random_user, role: :superuser)
      user = Factory.insert(:random_user, role: :user)
      {:ok, _} = Migration.run()
      %{scope: Scope.standalone(owner), user: user, owner: owner}
    end

    test "rank an exact title, then titles starting with the query, then the rest", c do
      grant(c, @content)
      page("Hotel Sommerro")
      page("Sommerro rooftop")
      page("Sommerro")
      page("Somewhere else")

      assert titles(CommandPalette.entries(c.user, "sommerro")) == ["Sommerro", "Sommerro rooftop", "Hotel Sommerro"]
      assert titles(CommandPalette.entries(c.user, "  SOMMERRO ")) == ["Sommerro", "Sommerro rooftop", "Hotel Sommerro"]
    end

    test "published entries come before pending ones and drafts of the same rank", c do
      grant(c, @content)
      page("Sommerro draft", status: :draft)
      page("Sommerro gone", status: :disabled)
      page("Sommerro pending", status: :pending)
      page("Sommerro published", status: :published)

      assert titles(CommandPalette.entries(c.user, "somm")) ==
               ["Sommerro published", "Sommerro pending", "Sommerro draft", "Sommerro gone"]
    end

    test "the user's content language comes first among equals, and rows name their language", c do
      grant(c, @content)
      page("Sommerro", language: :en)
      page("Sommerro", language: :no)

      assert [%{language: "NO"}, %{language: "EN"}] = CommandPalette.entries(c.user, "sommerro", language: "no")
      assert [%{language: "EN"}, %{language: "NO"}] = CommandPalette.entries(c.user, "sommerro", language: "en")
    end

    test "a row has what the identifier row shows and opens the entry's editor", c do
      grant(c, @content)
      page = page("Sommerro", status: :draft)

      assert [entry] = CommandPalette.entries(c.user, "somm")
      assert entry.url == "/admin/pages/update/#{page.id}"
      assert entry.status == :draft
      assert entry.type == Brando.Blueprint.get_singular(Brando.Pages.Page)
      assert entry.icon == Brando.Blueprint.get_icon(Brando.Pages.Page)
    end

    test "nobody sees an entry they cannot open", c do
      page("Sommerro")

      assert CommandPalette.entries(c.user, "somm") == []

      group = grant(c, ~w(brando.admin.access brando.pages.read))
      assert CommandPalette.entries(c.user, "somm") == [], "reading alone does not open the editor"

      {:ok, _} = Groups.update(c.scope, group.id, %{name: group.name}, @content, group.lock_version)
      assert titles(CommandPalette.entries(c.user, "somm")) == ["Sommerro"]
    end

    test "entries of a content type the user has no grant for are left out, and a superuser sees both", c do
      grant(c, @content)
      page("Lighthouse page")

      {:ok, article} =
        Brando.SyncTest.create_article(
          %{title: "Lighthouse case", slug: "lighthouse-case", language: "en", status: "published"},
          c.owner
        )

      # Creating the article gives it an identifier, as for any entry
      assert Repo.get_by(Identifier, schema: Brando.SyncTest.Article, entry_id: article.id)

      assert titles(CommandPalette.entries(c.user, "lighthouse")) == ["Lighthouse page"]

      # A superuser's search reaches every content type, including test-only
      # Blueprints without a table; give those an empty one in this test.
      for schema <- Brando.Authorization.Catalog.schemas(),
          is_binary(schema.__schema__(:source)),
          table = schema.__schema__(:source),
          Repo.query!("SELECT to_regclass($1)::text", [table]).rows == [[nil]] do
        Repo.query!(~s[CREATE TABLE "#{table}" (id bigserial PRIMARY KEY)])
      end

      assert c.owner |> CommandPalette.entries("lighthouse") |> titles() |> Enum.sort() ==
               ["Lighthouse case", "Lighthouse page"]
    end

    test "deleted entries are left out even when their identifier remains", c do
      grant(c, @content)
      page = page("Sommerro")
      Repo.update!(Ecto.Changeset.change(page, deleted_at: DateTime.utc_now(:second)))

      assert CommandPalette.entries(c.user, "somm") == []
    end

    test "LIKE wildcards in the query match themselves", c do
      grant(c, @content)
      page("100% wool")
      page("1000 wool")

      assert titles(CommandPalette.entries(c.user, "100%")) == ["100% wool"]
      assert CommandPalette.entries(c.user, "_") == []
    end

    test "the menu decides the settings, create actions, utilities and assets", c do
      grant(c, ~w(brando.admin.access brando.pages.read brando.pages.update))
      context = CommandPalette.context(Repo.reload!(c.user))
      assert context.content_types == []
      assert context.utilities == []
      assert context.assets == []
      refute Enum.any?(context.settings, &(&1.url == "/admin/config/utils"))

      grant(c, ~w(brando.pages.create brando.utilities.read brando.images.read))
      context = CommandPalette.context(Repo.reload!(c.user))

      assert [%{schema: Brando.Pages.Page, url: "/admin/pages/create"}] = context.content_types
      assert Enum.any?(context.utilities, &(&1.url == "/admin/config/utils#utils-sitemap"))
      assert Enum.any?(context.settings, &(&1.url == "/admin/config/utils"))
      assert context.assets == [images: "/admin/assets/images"]
    end

    test "the assistant is offered only when it is configured and the user may use it", c do
      grant(c, ~w(brando.admin.access brando.assistant.use))
      refute CommandPalette.context(c.user).assistant?

      Brando.AIStub.configure()
      assert CommandPalette.context(c.user).assistant?

      other = Factory.insert(:random_user, role: :user)
      {:ok, group} = Groups.create(c.scope, %{name: "Backend only"}, ~w(brando.admin.access))
      {:ok, :ok} = Groups.add_member(c.scope, group.id, other.id)
      refute CommandPalette.context(other).assistant?
    end
  end

  describe "results" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :none)
      user = Factory.insert(:random_user, role: :superuser)
      %{user: user, context: CommandPalette.context(user)}
    end

    test "an empty query shows recent places and common actions", c do
      recent = [
        %{"path" => "/admin/config/seo", "title" => "SEO | Brando"},
        %{"path" => "/admin/pages/update/1", "title" => "About — Page"},
        %{"path" => "https://evil.example/admin", "title" => "Elsewhere"},
        %{"path" => "//evil.example/admin", "title" => "Elsewhere"},
        %{"path" => "/admin/login", "title" => "Log in"},
        %{"path" => "/admin", "title" => "Dashboard"}
      ]

      assert [%{key: :recent, items: places}, %{key: :actions, items: actions}] =
               CommandPalette.results(c.context, "", recent, current_path: "/admin")

      assert titles(places) == [gettext_configuration() <> " → SEO", "About — Page"]
      assert Enum.any?(actions, &(&1.label == "Create page…"))
    end

    test "recent places are kept to eight", c do
      recent = for n <- 1..12, do: %{"path" => "/admin/pages/update/#{n}", "title" => "Page #{n}"}
      assert [%{key: :recent, items: places} | _] = CommandPalette.results(c.context, "", recent)
      assert length(places) == 8
    end

    test "a query lists entries, actions and settings", c do
      page("Sommerro")
      assert groups = CommandPalette.results(c.context, "somm")
      assert [:entries, :actions] = Enum.map(groups, & &1.key)
      # The entries end with the way to the search page
      assert [%{label: "Sommerro"}, %{kind: :search, url: "/admin/search?q=somm"}] = hd(groups).items
      # The best entry is a page, so "Create page…" is offered
      assert Enum.any?(Enum.at(groups, 1).items, &(&1.label == "Create page…"))

      # No title matches: the search page's row goes last, after the setting
      assert [
               %{key: :settings, items: [%{label: "SEO", url: "/admin/config/seo"}]},
               %{key: :entries, items: [%{kind: :search}]}
             ] = CommandPalette.results(c.context, "seo")
    end

    test "the search page's row carries the query, encoded", c do
      assert %{url: "/admin/search?q=fish+%26+chips", label: label} = CommandPalette.search_all("fish & chips")
      assert label =~ "fish & chips"

      assert [%{key: :entries, items: [%{id: "palette-search-all"}]}] =
               CommandPalette.results(c.context, "zzqx nothing")
    end

    test "> lists commands only", c do
      page("Sitemap notes")
      groups = CommandPalette.results(c.context, ">")
      assert Enum.map(groups, & &1.key) == [:actions, :settings]
      assert Enum.any?(hd(groups).items, &(&1.label == "Create page…"))

      assert [%{key: :actions, items: items}] = CommandPalette.results(c.context, "> sitemap")
      assert titles(items) == ["Generate sitemap"]
    end

    test "images matching the query link to the library filtered by it", c do
      Factory.insert(:image, path: "images/site/sommerro-1.jpg")
      Factory.insert(:image, path: "images/site/sommerro-2.jpg")
      Factory.insert(:image, path: "images/site/other.jpg")

      context = %{c.context | assets: [images: "/admin/assets/images"]}
      [%{key: :actions, items: actions}, %{key: :entries}] = CommandPalette.results(context, "sommerro")
      assert %{count: 2, url: url} = Enum.find(actions, &(&1.id == "palette-assets-images"))
      assert url == "/admin/assets/images?filter%3Afolder_id=all&filter%3Apath=sommerro"
    end

    test "images in nested library folders count, images in hidden folders never do", c do
      site = Repo.insert!(%Brando.Media.Folder{scope: "images", name: "site", path: "site"})
      nested = Repo.insert!(%Brando.Media.Folder{scope: "images", name: "press", path: "site/press", parent_id: site.id})
      hidden = Brando.Media.Folders.hidden_folder_id("visitor-uploads")

      Factory.insert(:image, path: "images/site/press/sommerro-1.jpg", folder_id: nested.id)
      Factory.insert(:image, path: "images/hidden/sommerro-2.jpg", folder_id: hidden)
      Factory.insert(:image, path: "images/hidden/sommerro-3.jpg", folder_id: hidden)

      context = %{c.context | assets: [images: "/admin/assets/images"]}
      [%{key: :actions, items: actions}, %{key: :entries}] = CommandPalette.results(context, "sommerro")
      assert %{count: 1} = Enum.find(actions, &(&1.id == "palette-assets-images"))

      Repo.delete_all(from(i in Brando.Images.Image, where: i.folder_id == ^nested.id))
      items = context |> CommandPalette.results("sommerro") |> Enum.flat_map(& &1.items)
      refute Enum.find(items, &(&1.id == "palette-assets-images"))
    end
  end

  describe "tenancy" do
    @prefix "tenant_palette_other"

    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :multi)
      user = Factory.insert(:random_user, role: :superuser)

      Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))
      Repo.query!(~s|CREATE TABLE "#{@prefix}".pages (LIKE public.pages INCLUDING ALL)|)
      Repo.query!(~s|CREATE TABLE "#{@prefix}".content_identifiers (LIKE public.content_identifiers INCLUDING ALL)|)
      on_exit(fn -> Brando.Tenant.put_prefix(nil) end)

      %{user: user}
    end

    test "entries come from the current site and environment only", c do
      page("Sommerro public")

      Brando.Tenant.with_prefix(@prefix, fn ->
        # Through Brando.Repo, which writes to the process's tenant schema
        page =
          Brando.Repo.insert!(%Brando.Pages.Page{
            title: "Sommerro tenant",
            uri: "sommerro",
            language: :en,
            status: :published,
            template: "default.html",
            creator_id: c.user.id
          })

        Brando.Repo.insert!(%Identifier{
          schema: Brando.Pages.Page,
          entry_id: page.id,
          title: page.title,
          status: :published,
          language: :en
        })

        assert titles(CommandPalette.entries(c.user, "somm")) == ["Sommerro tenant"]
      end)
    end
  end

  defp gettext_configuration, do: Gettext.dgettext(Brando.Gettext, "default", "Configuration")

  defp grant(c, keys) do
    {:ok, group} = Groups.create(c.scope, %{name: "Palette #{System.unique_integer([:positive])}"}, keys)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
    group
  end
end
