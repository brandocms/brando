defmodule BrandoAdmin.CacheLiveTest do
  # Configuration → Cache: the query cache's entries, a site's under its
  # prefix, listed for those who may use the screen there (#3401).
  use Brando.LiveCase

  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry}
  alias Brando.Users

  @path "/admin/config/cache"

  # Emptying the caches reloads the site's identity, SEO, globals, palettes
  # and navigation into `:cache`.
  setup do
    cached = Map.new([:query, :cache], &{&1, elem(Cachex.export(&1), 1)})
    Cachex.clear(:query)

    on_exit(fn ->
      for {cache, entries} <- cached do
        Cachex.clear(cache)
        Cachex.import(cache, entries)
      end
    end)
  end

  defp account(role),
    do: Factory.insert(:random_user, role: role, language: :en, avatar: nil, config: %Users.UserConfig{})

  defp put_entry(key), do: {:ok, true} = Cachex.put(:query, key, :cached)

  defp cached?(key), do: Cachex.get(:query, key) == {:ok, :cached}

  defp token(key), do: :sha256 |> :crypto.hash(:erlang.term_to_binary(key)) |> Base.url_encode64(padding: false)

  defp row(view, key), do: element(view, "button[phx-value-key='#{token(key)}']")

  describe "with one site" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :none)
    end

    test "lists list and single entries, and skips keys of another shape", %{conn: conn} do
      put_entry({:list, "pages_pages", "AAAA0001"})
      put_entry({:single, "pages_pages", "AAAA0002", 7})
      put_entry({:other, :shape})
      put_entry("a string")
      put_entry({:list, "pages_pages", %{status: :published}})
      put_entry({:tenant, "tenant_a_b", {:starting_modules, :page, "en"}})

      {:ok, view, _html} = live(conn, @path)

      assert has_element?(view, "td code", "AAAA0001")
      assert has_element?(view, "td code", "#7")
      assert has_element?(view, "header span", "2 entries")
      refute has_element?(view, "th", "Site")

      view |> row({:single, "pages_pages", "AAAA0002", 7}) |> render_click()
      refute cached?({:single, "pages_pages", "AAAA0002", 7})
      assert cached?({:list, "pages_pages", "AAAA0001"})
    end
  end

  describe "with several sites, legacy mode" do
    setup :sites

    setup do
      put_test_env(:authorization_mode, :legacy)
      :ok
    end

    test "a site's editor sees and clears only that site's entries", c do
      editor = account(:editor)
      {:ok, _} = Access.grant(editor, c.site_a, :editor)
      assert_site_scoped(c, log_in_user(build_conn(), editor))
    end

    test "a superuser sees every site's entries and those cached outside every site", c do
      {:ok, view, _html} = live(c.conn, @path)

      for key <- [c.key_a, c.single_a, c.key_b, c.public_key], do: assert(has_element?(row(view, key)))
      assert has_element?(view, "td", "Site B · Production")

      render_click(view, "empty_caches", %{})
      for key <- [c.key_a, c.key_b, c.public_key], do: refute(cached?(key))
    end
  end

  describe "with several sites, groups mode" do
    setup :sites

    setup %{current_user: owner, site_a: site_a} do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      editor = account(:editor)

      scope = Scope.site(owner, site_a)

      {:ok, group} =
        Groups.create(scope, %{name: "Cache"}, ~w(brando.admin.access brando.utilities.read brando.utilities.update))

      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
      %{editor: editor}
    end

    test "a member of one site's group sees and clears only that site's entries", c do
      assert_site_scoped(c, log_in_user(build_conn(), c.editor))
    end
  end

  defp assert_site_scoped(c, conn) do
    {:ok, view, _html} = live(conn, @path)

    assert has_element?(row(view, c.key_a))
    assert has_element?(row(view, c.single_a))
    assert has_element?(view, "td", "Site A · Production")
    assert has_element?(view, "td code", "#7")
    refute has_element?(row(view, c.key_b))
    refute has_element?(row(view, c.public_key))
    refute has_element?(view, "td", "Site B")

    # Another site's entry, by its token: not cleared.
    render_click(view, "clear_cache_entry", %{"key" => token(c.key_b)})
    assert cached?(c.key_b)

    view |> row(c.single_a) |> render_click()
    refute cached?(c.single_a)

    # Emptying the caches empties only this viewer's.
    render_click(view, "empty_caches", %{})
    refute cached?(c.key_a)
    assert cached?(c.key_b)
    assert cached?(c.public_key)
  end

  defp sites(_context) do
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()
    Tenant.put_prefix(nil)

    on_exit(fn ->
      Cache.clear()
      Tenant.put_prefix(nil)
    end)

    {site_a, prefix_a} = site("cache-a", "Site A")
    {site_b, prefix_b} = site("cache-b", "Site B")

    keys = %{
      key_a: {:tenant, prefix_a, {:list, "pages_pages", "AAAA0001"}},
      single_a: {:tenant, prefix_a, {:single, "pages_pages", "AAAA0002", 7}},
      key_b: {:tenant, prefix_b, {:list, "pages_pages", "BBBB0001"}},
      public_key: {:list, "pages_pages", "CCCC0001"}
    }

    Enum.each(Map.values(keys), &put_entry/1)
    Map.merge(keys, %{site_a: site_a, site_b: site_b})
  end

  defp site(key, name) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, environment} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    prefix = Tenant.prefix(site, environment)
    copy_tenant_tables(prefix)
    {site, prefix}
  end

  # An environment schema with a copy of every tenant table, inside the test's
  # transaction.
  defp copy_tenant_tables(prefix) do
    Repo.query!(~s(CREATE SCHEMA "#{prefix}"))

    "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")
      Repo.query!(~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
      Repo.query!(~s(INSERT INTO "#{prefix}"."#{escaped}" SELECT * FROM public."#{escaped}"))
    end)
  end
end
