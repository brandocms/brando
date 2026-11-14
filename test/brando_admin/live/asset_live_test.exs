defmodule BrandoAdmin.Sites.AssetLiveTest do
  use Brando.LiveCase

  alias Brando.Assets.SiteAssets

  setup do
    root = Path.join(System.tmp_dir!(), "brando-asset-live-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :none)
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:site_assets_path, Path.join(root, "site_assets"))
    SiteAssets.invalidate_cache()

    on_exit(fn ->
      File.rm_rf(root)
      SiteAssets.invalidate_cache()
    end)

    set_path = Path.join(SiteAssets.sets_root(nil), "20260816_admin")
    File.mkdir_p!(Path.join(set_path, "assets"))
    File.write!(Path.join([set_path, "assets", "main.js"]), "console.log('active')")
    File.write!(Path.join(set_path, "manifest.json"), "{}")
    {:ok, asset_set} = SiteAssets.register_set(set_path, %{revision: "admin-test"})

    %{asset_set: asset_set}
  end

  test "superusers activate and revert registered asset sets", %{conn: conn, asset_set: asset_set} do
    {:ok, view, html} = live(conn, "/admin/config/assets")

    assert html =~ "Frontend assets"
    assert has_element?(view, "#asset-set-#{asset_set.id}", asset_set.name)
    assert has_element?(view, ".frontend-assets-current", "Release assets")
    assert has_element?(view, "#asset-set-#{asset_set.id} button", "Activate build")

    view
    |> element("#asset-set-#{asset_set.id} button", "Activate build")
    |> render_click()

    assert SiteAssets.active_set().id == asset_set.id
    assert has_element?(view, "#asset-set-#{asset_set.id}", "Active")
    assert has_element?(view, ".frontend-assets-current.uploaded", asset_set.name)

    view
    |> element("button", "Use release assets")
    |> render_click()

    refute SiteAssets.active_set()
    assert has_element?(view, "#asset-set-#{asset_set.id}", "Available")
  end

  test "uses the superuser's Norwegian admin locale", %{current_user: current_user} do
    {:ok, norwegian_user} =
      current_user
      |> Ecto.Changeset.change(language: :no)
      |> Repo.update()

    conn = log_in_user(Phoenix.ConnTest.build_conn(), norwegian_user)
    {:ok, view, html} = live(conn, "/admin/config/assets")

    assert html =~ "Frontend-ressurser"
    assert has_element?(view, ".frontend-assets-current", "Frontend-filer fra release")
    assert has_element?(view, ".frontend-assets-library", "Opplastede bygg")
    assert has_element?(view, "button", "Aktiver bygg")
  end

  test "non-superusers are redirected", %{asset_set: _asset_set} do
    editor =
      Brando.Factory.insert(:random_user,
        role: :editor,
        config: %Brando.Users.UserConfig{}
      )

    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)

    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/config/assets")
  end
end

defmodule BrandoAdmin.Sites.AssetLiveEnvironmentsTest do
  # The environments of the selected site, and the set each one uses
  use Brando.LiveCase

  alias Brando.Assets.SiteAssets
  alias Brando.SiteAssetsFixtures
  alias Brando.Tenant.Registry

  for mode <- [:multi, :single] do
    describe "in #{mode}" do
      setup do
        setup_site(unquote(mode))
      end

      test "activates a set for the environment being edited, and clears it", %{
        conn: conn,
        staging: staging,
        next: next,
        one: one
      } do
        {:ok, view, _html} = live(conn, "/admin/config/assets?brando_site_key=acme&brando_environment_key=staging")

        assert has_element?(view, "#asset-environment-#{staging.id}", "The site's")
        assert has_element?(view, "#asset-environment-#{staging.id}", one.name)
        assert has_element?(view, "#asset-environment-#{staging.id}", "Editing now")

        view
        |> element("#asset-set-#{next.id} button", "Activate for Staging")
        |> render_click()

        assert Registry.get_environment(staging.id).asset_set_id == next.id
        assert has_element?(view, "#asset-environment-#{staging.id}", "Its own")
        assert has_element?(view, "#asset-environment-#{staging.id}", next.name)
        assert has_element?(view, "#asset-set-#{next.id}", "Used by Staging")
        refute has_element?(view, "#asset-set-#{next.id} button", "Activate for Staging")
        # The site's set is untouched
        assert SiteAssets.active_set(if(unquote(mode) == :multi, do: Registry.get_site_by_key("acme"))).id == one.id

        view
        |> element("#asset-environment-#{staging.id} button", "Use the site's build")
        |> render_click()

        assert Registry.get_environment(staging.id).asset_set_id == nil
        assert has_element?(view, "#asset-environment-#{staging.id}", "The site's")
      end

      test "the current card names the build the live environment serves", %{conn: conn, next: next, one: one} do
        production = Brando.Tenant.Cache.get_env("acme", "production")
        {:ok, _production} = SiteAssets.activate_environment_set(next.id, production)

        {:ok, view, _html} = live(conn, "/admin/config/assets?brando_site_key=acme&brando_environment_key=staging")

        assert has_element?(view, ".frontend-assets-current.uploaded h2", next.name)
        assert has_element?(view, ".frontend-assets-current", "Production, the live environment, serves this build")
        refute has_element?(view, ".frontend-assets-current h2", one.name)
        refute has_element?(view, ".frontend-assets-current button", "Use release assets")

        view
        |> element("#asset-environment-#{production.id} button", "Use the site's build")
        |> render_click()

        assert has_element?(view, ".frontend-assets-current h2", one.name)
        assert has_element?(view, ".frontend-assets-current", "This uploaded build is serving frontend requests now.")
        assert has_element?(view, ".frontend-assets-current button", "Use release assets")
      end
    end
  end

  defp setup_site(mode) do
    root = Path.join(System.tmp_dir!(), "brando-asset-live-env-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, mode)
    put_test_env(:site_key, "acme")
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:site_assets_path, Path.join(root, "site_assets"))
    SiteAssets.invalidate_cache()
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Brando.Tenant.put_prefix(nil)
      SiteAssets.invalidate_cache()
      Brando.Tenant.Cache.clear()
    end)

    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "acme", "acme.test")

    {:ok, staging} =
      Registry.create_environment(acme, %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"},
        actor: :system
      )

    scope = if mode == :multi, do: Registry.get_site(acme.id)
    {:ok, one} = scope |> register("acme-one") |> Map.fetch!(:id) |> SiteAssets.activate_set()

    %{staging: staging, one: one, next: register(scope, "acme-next")}
  end

  defp register(scope, name) do
    path = SiteAssetsFixtures.create_set(scope, name, "js-#{name}", "#{name}.css")
    {:ok, set} = SiteAssets.register_set(scope, path, %{})
    set
  end
end
