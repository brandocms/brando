defmodule BrandoAdmin.UtilsSystemCheckLiveTest do
  use Brando.LiveCase

  alias Brando.DoctorFixtures.{Healthy, Warns}

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  test "loads the checks after the page and shows each with its status and fix", %{conn: conn} do
    put_test_env(Brando.Doctor, checks: [Healthy, Warns], skip: Brando.Doctor.default_checks())

    {:ok, view, html} = live(conn, "/admin/config/utils")

    # The first render does not wait for the checks
    assert html =~ ~s(aria-busy="true")

    html = render_async(view)
    assert html =~ ~s(aria-busy="false")
    assert has_element?(view, "[data-testid=system-check-tally]", "1 warning")
    assert has_element?(view, "li[data-check=healthy][data-status=ok] h3", "Healthy")
    assert has_element?(view, "li[data-check=warns][data-status=warning] small", "do the thing")
    assert has_element?(view, "li[data-check=warns] details li", "a")

    view |> element("#system-check button", "Run again") |> render_click()
    assert render_async(view) =~ ~s(aria-busy="false")
  end

  test "links a failing check to the screen that fixes it", %{conn: conn} do
    put_test_env(Brando.Doctor, skip: Brando.Doctor.default_checks() -- [Brando.Doctor.Checks.Modules])

    user = Brando.Factory.insert(:random_user)
    module = Brando.Factory.insert(:module)

    Brando.Repo.insert!(
      Ecto.Changeset.change(%Brando.Content.Block{}, %{
        uid: Brando.Utils.generate_uid(),
        type: :module,
        module_id: module.id,
        module_version: nil,
        creator_id: user.id,
        sequence: 0
      })
    )

    {:ok, view, _html} = live(conn, "/admin/config/utils")
    render_async(view)

    assert has_element?(view, "li[data-check=modules] a[href$='/config/content/modules/stale-blocks']", "Resolve blocks")
  end

  describe "video providers" do
    setup do
      put_test_env(Brando.Doctor, skip: Brando.Doctor.default_checks() -- [Brando.Doctor.Checks.VideoProviders])
      put_test_env(Brando.Videos.Uploaders.Mux, [])
      put_test_env(Brando.Videos.Uploaders.Bunny, [])
      put_test_env(Brando.Videos.Uploaders.Cloudflare, [])
      put_test_env(Brando.Videos.Uploaders.Vimeo, [])
      put_test_env(:default_video_upload_strategy, :local)
      :ok
    end

    test "lists each problem the boot check finds as a warning", %{conn: conn} do
      put_test_env(:default_video_upload_strategy, :bunny)
      put_test_env(Brando.Videos.Uploaders.Mux, access_token_id: "id")

      {:ok, view, _html} = live(conn, "/admin/config/utils")
      render_async(view)

      assert has_element?(view, "li[data-check=video_providers][data-status=warning]")

      problems = Brando.Videos.ProviderConfigCheck.problems()
      assert length(problems) == 2

      for problem <- problems do
        assert has_element?(view, "li[data-check=video_providers] details li", problem)
      end
    end

    test "lists nothing when there are no problems", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/config/utils")
      render_async(view)

      assert has_element?(view, "li[data-check=video_providers][data-status=ok]")
      refute has_element?(view, "li[data-check=video_providers] details")
    end
  end

  # Other sites' deploy destinations are what a site administrator could pick
  # on Publishing, so they see that some overlap, not which
  describe "overlapping deploy targets" do
    setup %{current_user: superuser} do
      root = Path.join(System.tmp_dir!(), "brando-system-check-#{System.unique_integer([:positive])}")
      put_test_env(:media_path, Path.join(root, "media"))
      put_test_env(:sites_path, Path.join(root, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi)
      put_test_env(Brando.Doctor, skip: Brando.Doctor.default_checks() -- [Brando.Doctor.Checks.Configuration])

      put_test_env(Brando.Sites.DeployConfig,
        s3_targets: %{"acme" => ["s3://shared-bucket/"], "beta" => ["s3://shared-bucket/beta"]}
      )

      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()

      on_exit(fn ->
        File.rm_rf(root)
        Brando.Tenant.put_prefix(nil)
        Brando.Tenant.Cache.clear()
        Brando.TenantCaches.clear(~w(tenant_acme_production))
      end)

      {:ok, acme} =
        Brando.Tenant.Setup.create_site(
          %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
          superuser,
          environments: [%{name: "Production", key: "production", live: true, domain: "acme.test"}]
        )

      {:ok, _beta} =
        Brando.Tenant.Registry.create_site(%{
          name: "Beta",
          key: "beta",
          languages: ["en"],
          default_language: "en",
          status: :active
        })

      %{acme: acme}
    end

    test "a superuser sees which entries reach the same destination", %{conn: conn} do
      {:ok, view, _html} = live(Plug.Conn.put_session(conn, "brando_site_key", "acme"), "/admin/config/utils")
      render_async(view)

      assert has_element?(view, "li[data-check=configuration] details li", "s3://shared-bucket/beta for beta")
    end

    test "a site administrator sees that some do, and not which", %{acme: acme} do
      admin = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      {:ok, _grant} = Brando.Tenant.Access.grant(admin, acme, :admin)

      conn =
        Brando.Test.Support.admin_conn()
        |> Brando.Test.log_in_user(admin)
        |> Plug.Conn.put_session("brando_site_key", "acme")

      {:ok, view, _html} = live(conn, "/admin/config/utils")
      render_async(view)

      assert has_element?(view, "li[data-check=configuration] p", "deploy targets shared between sites")
      assert has_element?(view, "li[data-check=configuration] details li", "1 pair of sites' entries")
      assert has_element?(view, "li[data-check=configuration] details li", "a superuser can see which")
      refute render(view) =~ "shared-bucket"
    end

    test "a superuser who loses the superuser group stops seeing which, groups mode", %{acme: acme, current_user: owner} do
      alias Brando.Authorization.{Groups, Migration, Scope}

      put_test_env(:authorization_mode, :groups)
      held = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()

      site_scope = Scope.site(owner, acme)
      {:ok, utilities} = Groups.create(site_scope, %{name: "Utilities"}, ~w(brando.admin.access brando.utilities.read))
      {:ok, :ok} = Groups.add_member(site_scope, utilities.id, held.id)

      conn =
        Brando.Test.Support.admin_conn()
        |> Brando.Test.log_in_user(held)
        |> Plug.Conn.put_session("brando_site_key", "acme")

      {:ok, view, _html} = live(conn, "/admin/config/utils")
      render_async(view)
      assert has_element?(view, "li[data-check=configuration] details li", "s3://shared-bucket/beta for beta")

      installation = Scope.installation(owner)
      {:ok, groups} = Groups.list(installation)
      for group <- groups, do: Groups.remove_member(installation, group.id, held.id)
      refute Brando.Authorization.Boundary.superuser?(held)

      render_async(view)
      refute render(view) =~ "shared-bucket"
      assert has_element?(view, "li[data-check=configuration] details li", "a superuser can see which")

      view |> element("#system-check button", "Run again") |> render_click()
      render_async(view)
      refute render(view) =~ "shared-bucket"
      assert has_element?(view, "li[data-check=configuration] details li", "a superuser can see which")
    end
  end

  test "Brando's own checks render", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/config/utils")
    render_async(view, 30_000)

    for id <- ~w(versions migrations oban configuration image_configs modules sitemap json_ld alt_text) do
      assert has_element?(view, "li[data-check=#{id}]")
    end

    # Which Brando is running, and from where
    assert has_element?(view, "li[data-check=versions] p", "Brando #{Brando.version()} (this checkout)")
  end
end
