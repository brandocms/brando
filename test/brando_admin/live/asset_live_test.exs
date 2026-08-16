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
    assert has_element?(view, "#asset-set-#{asset_set.id} button", "Activate")

    view
    |> element("#asset-set-#{asset_set.id} button", "Activate")
    |> render_click()

    assert SiteAssets.active_set().id == asset_set.id
    assert has_element?(view, "#asset-set-#{asset_set.id}", "Active")

    view
    |> element("button", "Revert to release assets")
    |> render_click()

    refute SiteAssets.active_set()
    assert has_element?(view, "#asset-set-#{asset_set.id}", "Available")
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
