defmodule Brando.TenantFailClosedTest do
  # Audit F31: in multi-site mode an admin with no site to enter (never
  # assigned, revoked, or only on a suspended site) resolved no tenant and
  # read the public schema's copy of the content a tenant migration leaves
  # behind, and exported its form submissions.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry}

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    key = "fail-closed-#{System.unique_integer([:positive])}"

    {:ok, site} =
      Registry.create_site(%{name: key, key: key, languages: ["en"], default_language: "en", status: :active})

    {:ok, _environment} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    %{site: Registry.get_site(site.id)}
  end

  describe "an editor with no site" do
    setup %{site: site} do
      never = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      revoked = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      {:ok, _} = Access.grant(revoked, site, :editor)
      :ok = Access.revoke(revoked, site)
      %{editors: [never, revoked]}
    end

    test "is sent to the access-denied page from every admin screen", %{editors: editors} do
      for editor <- editors do
        conn = log_in_user(build_conn(), editor)

        for path <- ["/admin/pages", "/admin/sites", "/admin/users"] do
          assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, path)
        end
      end
    end

    test "cannot export form submissions", %{editors: editors} do
      for editor <- editors do
        conn = build_conn() |> log_in_user(editor) |> get("/admin/forms/contact/submissions/export")
        assert redirected_to(conn) == "/admin/access-denied"
      end
    end

    test "still reaches the access-denied page and signs out", %{editors: [editor | _]} do
      conn = log_in_user(build_conn(), editor)
      assert html_response(get(conn, "/admin/access-denied"), 403)
      assert redirected_to(delete(conn, "/admin/logout"))
    end
  end

  test "an editor with a site still gets in", %{site: site} do
    editor = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    {:ok, _} = Access.grant(editor, site, :editor)
    Tenant.with_prefix(Tenant.prefix(site, hd(site.environments)), fn -> clone_public_tables() end)

    assert {:ok, _view, _html} = live(log_in_user(build_conn(), editor), "/admin/pages")
  end

  test "a superuser with no active site reaches the installation's screens only", %{conn: conn, site: site} do
    {:ok, _} = Registry.update_site(site, %{status: :suspended})

    assert {:ok, _view, html} = live(conn, "/admin/sites")
    assert html =~ site.name
    assert {:ok, _view, _html} = live(conn, "/admin/users")
    assert {:error, {:redirect, %{to: "/admin/sites"}}} = live(conn, "/admin/pages")
  end

  test "with group authorization, an installation grant reaches its screen with no site", %{conn: conn} do
    put_test_env(:authorization_mode, :groups)
    owner = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    admin = Brando.Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    {:ok, _} = Brando.Authorization.Migration.run()
    installation = Brando.Authorization.Scope.installation(owner)
    keys = ["brando.admin.access", "brando.sites.read"]
    {:ok, group} = Brando.Authorization.Groups.create(installation, %{name: "Site managers"}, keys)
    {:ok, :ok} = Brando.Authorization.Groups.add_member(installation, group.id, admin.id)
    conn = log_in_user(conn, admin)

    assert {:ok, _view, _html} = live(conn, "/admin/sites")
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/pages")
  end

  describe "Brando.Repo with no tenant prefix" do
    test "refuses a site table" do
      for query <- [Page, from(page in Page, select: page.id), "pages"] do
        assert_raise Brando.Exception.MissingTenantError, fn -> Brando.Repo.all(query) end
      end

      assert_raise Brando.Exception.MissingTenantError, fn -> Brando.Repo.insert(%Page{title: "Nowhere"}) end
    end

    test "refuses a site table joined to a shared one" do
      joined = from(user in "users", join: page in "pages", on: page.creator_id == user.id, select: page.title)
      creators = from(page in Page, select: page.creator_id)
      in_subquery = from(user in "users", where: user.id in subquery(creators), select: user.id)

      for query <- [joined, in_subquery] do
        assert_raise Brando.Exception.MissingTenantError, fn -> Brando.Repo.all(query) end
      end

      # A shared schema reads `public` by design, its joins included (avatars)
      assert is_list(Brando.Repo.all(from(user in Brando.Users.User, join: avatar in assoc(user, :avatar))))
    end

    # A Brando data migration that reads content with Brando.Repo
    test "does not refuse a migration Ecto runs" do
      Process.put(:ecto_migration, %{runner: self(), prefix: nil})
      on_exit(fn -> Process.delete(:ecto_migration) end)
      assert is_list(Brando.Repo.all(Page))
    end

    test "reads shared tables, and the public copy when asked for" do
      assert is_list(Brando.Repo.all(Brando.Users.User))
      assert is_list(Brando.Repo.all(Oban.Job))
      assert is_list(Brando.Repo.all(Page, prefix: "public"))
      assert is_list(Brando.Repo.all(from(page in Page, prefix: "public")))
    end

    test "does not refuse without several sites" do
      for mode <- [:none, :single] do
        put_test_env(:tenancy_mode, mode)
        assert is_list(Brando.Repo.all(Page))
      end
    end
  end

  defp clone_public_tables do
    prefix = Tenant.current_prefix()
    Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)
    %{rows: rows} = Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")

    for [table] <- rows, not Tenant.SharedTables.member?(table) do
      Repo.query!(~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
    end
  end
end
