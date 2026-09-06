defmodule Brando.Authorization.SiteContextTest do
  use Brando.ConnCase
  import Phoenix.LiveViewTest
  alias Brando.Authorization.{Boundary, Groups, Media, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Boundary.put_scope(nil)
    owner = Factory.insert(:random_user, role: :superuser)
    user = Factory.insert(:random_user, role: :editor)
    page = Factory.insert(:page, title: "Public original", status: :draft)
    alpha = site("Authorization Alpha", "authorization-alpha")
    beta = site("Authorization Beta", "authorization-beta")
    alpha_live = environment(alpha, "production")
    alpha_stage = environment(alpha, "staging")
    beta_live = environment(beta, "production")
    {:ok, _} = Migration.run()
    owner_scope = Scope.site(owner, alpha, alpha_live)

    {:ok, group} =
      Groups.create(owner_scope, %{name: "Alpha editors"}, [
        "brando.admin.access",
        "brando.pages.read",
        "brando.pages.update",
        "brando.files.read",
        "brando.files.create"
      ])

    {:ok, :ok} = Groups.add_member(owner_scope, group.id, user.id)

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Boundary.put_scope(nil)
      Tenant.Cache.clear()
    end)

    %{
      owner: owner,
      user: user,
      page: page,
      alpha: alpha,
      beta: beta,
      live: Scope.site(user, alpha, alpha_live),
      staging: Scope.site(user, alpha, alpha_stage),
      beta_scope: Scope.site(user, beta, beta_live),
      group: group
    }
  end

  test "identical record IDs are read from only the authorized environment", c do
    Repo.update_all(from(p in Page, where: p.id == ^c.page.id), [set: [title: "Alpha production"]], prefix: c.live.prefix)
    Repo.update_all(from(p in Page, where: p.id == ^c.page.id), [set: [title: "Alpha staging"]], prefix: c.staging.prefix)

    for {scope, title} <- [{c.live, "Alpha production"}, {c.staging, "Alpha staging"}] do
      Boundary.with_scope(scope, fn ->
        assert {:ok, page} = Pages.get_page(c.page.id)
        assert page.title == title
        assert page.__meta__.prefix == scope.prefix
      end)
    end

    Boundary.with_scope(c.beta_scope, fn ->
      assert {:ok, []} = Pages.list_pages(%{})
      assert {:error, {:page, :not_found}} = Pages.get_page(c.page.id)
    end)
  end

  test "a scoped context update cannot change public content or another environment", c do
    assert {:ok, updated} = Pages.update_page(c.page.id, %{title: "Scoped update"}, c.live)
    assert updated.__meta__.prefix == c.live.prefix
    assert Repo.get!(Page, c.page.id, prefix: "public").title == "Public original"
    assert Repo.get!(Page, c.page.id, prefix: c.staging.prefix).title == "Public original"
    assert Repo.get!(Page, c.page.id, prefix: c.beta_scope.prefix).title == "Public original"
    assert {:error, :forbidden} = Pages.update_page(c.page.id, %{title: "Wrong site"}, c.beta_scope)
  end

  test "a forged changeset from another site's identically numbered record is rejected", c do
    foreign = Repo.get!(Page, c.page.id, prefix: c.beta_scope.prefix)
    assert {:error, :forbidden} = Pages.update_page(Ecto.Changeset.change(foreign, title: "Forged"), c.live)
    assert Repo.get!(Page, c.page.id, prefix: c.live.prefix).title == "Public original"
  end

  test "upload completion uses its captured environment even after process navigation", c do
    token = Tenant.with_prefix(c.live.prefix, fn -> Media.token(c.user) end)

    Tenant.with_prefix(c.staging.prefix, fn ->
      assert c.live.prefix == Media.with_intent(%{"scope_token" => token}, c.user, &Tenant.current_prefix/0)
      assert Tenant.current_prefix() == c.staging.prefix
    end)

    {:ok, _} = Registry.update_site(c.alpha, %{status: :suspended})
    assert {:error, _} = Media.with_intent(%{"scope_token" => token}, c.user, fn -> flunk("suspended upload") end)
  end

  test "a stale unrelated process prefix does not override a scoped read", c do
    Repo.update_all(from(p in Page, where: p.id == ^c.page.id), [set: [title: "Private beta"]],
      prefix: c.beta_scope.prefix
    )

    Tenant.with_prefix(c.beta_scope.prefix, fn ->
      Boundary.with_scope(c.live, fn ->
        assert {:ok, page} = Pages.get_page(c.page.id)
        assert page.title == "Public original"
        assert page.__meta__.prefix == c.live.prefix
      end)
    end)
  end

  test "collaboration topics differ across sites, environments and resource types", c do
    topics =
      Enum.map([c.live, c.staging, c.beta_scope], fn scope ->
        Tenant.with_prefix(scope.prefix, fn -> Tenant.Topic.entry("field_sync", Page, c.page.id) end)
      end)

    assert length(Enum.uniq(topics)) == 3

    for event <- ["field_sync", "dirty_fields", "active_field", "block_presence", "blocks:blocks"] do
      Tenant.with_prefix(c.live.prefix, fn ->
        refute Tenant.Topic.entry(event, Page, c.page.id) ==
                 Tenant.Topic.entry(event, Brando.Pages.Fragment, c.page.id)
      end)
    end
  end

  test "mutation notifications require record access in the receiving environment", c do
    alias Brando.Authorization.Realtime
    payload = %{authorization: %{prefix: c.live.prefix, schema: Page, entry_id: c.page.id}}
    assert Realtime.notification_allowed?(c.live, payload)
    refute Realtime.notification_allowed?(c.staging, payload)
    refute Realtime.notification_allowed?(c.beta_scope, payload)
    refute Realtime.notification_allowed?(c.live, %{payload: "Unscoped notification"})
    {:ok, :ok} = Groups.remove_member(Scope.site(c.owner, c.alpha), c.group.id, c.user.id)
    refute Realtime.notification_allowed?(c.live, payload)
  end

  test "the activity directory excludes other sites and refreshes membership removal", c do
    foreign = Factory.insert(:random_user, role: :user, avatar: nil)
    {:ok, beta_group} = Groups.create(Scope.site(c.owner, c.beta), %{name: "Beta only"}, ["brando.admin.access"])
    {:ok, :ok} = Groups.add_member(Scope.site(c.owner, c.beta), beta_group.id, foreign.id)
    token = Brando.Users.generate_user_session_token(c.owner)

    {:ok, view, _} =
      live_isolated(build_conn(), BrandoAdmin.Chrome,
        session: %{
          "user_token" => token,
          "brando_site_key" => c.alpha.key,
          "brando_environment_key" => "production"
        }
      )

    assert has_element?(view, "[data-user-id='#{c.user.id}']")
    refute has_element?(view, "[data-user-id='#{foreign.id}']")
    {:ok, :ok} = Groups.remove_member(Scope.site(c.owner, c.alpha), c.group.id, c.user.id)
    refute has_element?(view, "[data-user-id='#{c.user.id}']")
  end

  test "live preview recovery cannot cross sites or environments and suspension revokes the cache", c do
    alias Brando.Authorization.Preview
    key = "SITE-PREVIEW-#{Ecto.UUID.generate()}"
    page = Repo.get!(Page, c.page.id, prefix: c.live.prefix)
    changeset = Ecto.Changeset.change(page)
    assert :ok = Boundary.with_scope(c.live, fn -> Preview.register(key, changeset) end)
    on_exit(fn -> Preview.cleanup(key) end)
    assert :ok = Preview.authorize(key, c.user.id)

    for scope <- [c.staging, c.beta_scope] do
      other = Repo.get!(Page, c.page.id, prefix: scope.prefix)

      assert {:error, :forbidden} =
               Boundary.with_scope(scope, fn ->
                 Preview.authorize_write(key, Ecto.Changeset.change(other))
               end)
    end

    {:ok, _} = Registry.update_site(c.alpha, %{status: :suspended})
    assert {:error, :forbidden} = Preview.authorize(key, c.user.id)
  end

  test "presence metadata is isolated across environments even for the same account", c do
    alias Brando.Authorization.Realtime
    assert Realtime.visible_meta?(c.live, %{scope: c.live})
    refute Realtime.visible_meta?(c.live, %{scope: c.staging})
    refute Realtime.visible_meta?(c.live, %{scope: c.beta_scope})
    refute Realtime.visible_meta?(c.live, %{url: "/admin/pages"})
  end

  defp site(name, key) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    site
  end

  defp environment(site, key) do
    {:ok, environment} = Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
    prefix = Tenant.prefix(site, environment)
    Ecto.Adapters.SQL.query!(Repo, ~s(CREATE SCHEMA "#{prefix}"))
    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo, "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")

    rows
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")
      Ecto.Adapters.SQL.query!(Repo, ~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
      Ecto.Adapters.SQL.query!(Repo, ~s(INSERT INTO "#{prefix}"."#{escaped}" SELECT * FROM public."#{escaped}"))
    end)

    environment
  end
end
