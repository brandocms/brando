defmodule BrandoAdmin.Sites.SiteDeployTargetsLiveTest do
  # The Delivery section's allowed deploy targets on the Sites screen, which
  # only a superuser reaches
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Sites.DeployConfig
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry

  @rsync "deploy@static.example.test:/srv/sites/acme"
  @s3 "s3://acme-www"

  setup %{current_user: user} do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(DeployConfig, [])
    Brando.Tenant.Cache.clear()
    on_exit(&Brando.Tenant.Cache.clear/0)
    Brando.endpoint().subscribe("user:#{user.id}")

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static
      })

    %{site: Registry.get_site(site.id)}
  end

  defp form_id(site), do: "#deploy-targets-site-#{site.id}"

  defp submit(view, site, rsync, s3) do
    view
    |> element(form_id(site))
    |> render_submit(%{
      "deploy_targets" => %{
        "id" => to_string(site.id),
        "allowed_rsync_targets" => rsync ++ [""],
        "allowed_s3_targets" => s3 ++ [""]
      }
    })
  end

  defp targets(site) do
    site = Registry.get_site(site.id)
    {site.allowed_rsync_targets, site.allowed_s3_targets}
  end

  test "a superuser saves both lists at once", %{conn: conn, site: site} do
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")

    assert has_element?(view, "#{form_id(site)} button[type=submit]", "Save deploy targets")
    assert has_element?(view, form_id(site), "a parent ending in /")

    submit(view, site, [@rsync], [@s3, "s3://static-bucket/sites/"])

    assert targets(site) == {[@rsync], [@s3, "s3://static-bucket/sites/"]}
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Deploy targets for Acme saved."}}
    assert has_element?(view, ~s(#{form_id(site)} input[value="#{@rsync}"]))

    # Emptied again
    submit(view, site, [], [])
    assert targets(site) == {[], []}
  end

  test "each refused entry's error shows by its list, and what was typed stays", %{conn: conn, site: site} do
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")

    submit(view, site, ["deploy@localhost:/srv/www", @rsync], ["s3://bucket/sites/{site_key}"])

    assert targets(site) == {[], []}

    assert has_element?(
             view,
             "#{form_id(site)} #deploy-targets-site-#{site.id}_allowed_rsync_targets-field-wrapper",
             "deploy@localhost:/srv/www must be on another server"
           )

    assert has_element?(
             view,
             "#{form_id(site)} #deploy-targets-site-#{site.id}_allowed_s3_targets-field-wrapper",
             "already belongs to this site"
           )

    refute has_element?(
             view,
             "#{form_id(site)} #deploy-targets-site-#{site.id}_allowed_s3_targets-field-wrapper",
             "must be on another server"
           )

    assert has_element?(view, ~s(#{form_id(site)} input[value="#{@rsync}"]))
    assert has_element?(view, ~s(#{form_id(site)} input[value="s3://bucket/sites/{site_key}"]))
  end

  test "what is typed stays while the form changes", %{conn: conn, site: site} do
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")

    view
    |> element(form_id(site))
    |> render_change(%{
      "deploy_targets" => %{"id" => to_string(site.id), "allowed_rsync_targets" => [@rsync], "allowed_s3_targets" => [""]}
    })

    assert has_element?(view, ~s(#{form_id(site)} input[value="#{@rsync}"]))
    assert targets(site) == {[], []}
  end

  test "shows what config grants the site, read-only", %{conn: conn, site: site} do
    put_test_env(DeployConfig,
      rsync_targets: ["deploy@static.example.test:/srv/sites/{site_key}"],
      s3_targets: %{"beta" => ["s3://beta-www"]}
    )

    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")

    assert has_element?(
             view,
             "#{form_id(site)} .site-configured-targets li",
             "deploy@static.example.test:/srv/sites/acme"
           )

    refute has_element?(view, "#{form_id(site)} .site-configured-targets li", "s3://beta-www")
  end

  test "says when the site's saved target is allowed by neither, so its next deploy is refused", %{
    conn: conn,
    site: site
  } do
    {:ok, _site} = Registry.update_site_deploy_targets(site, %{allowed_s3_targets: [@s3]}, :system)
    {:ok, site} = Registry.update_site(Registry.get_site(site.id), %{deploy_config: %{strategy: :s3, target: @s3}})

    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")
    refute has_element?(view, "#{form_id(site)} .site-hint--warning")

    submit(view, site, [], [])

    assert has_element?(view, "#{form_id(site)} .site-hint--warning", "s3://acme-www")
    assert has_element?(view, "#{form_id(site)} .site-hint--warning", "next deploy will be refused")
  end

  test "show on a static site, and on a dynamic one only while it has entries", %{conn: conn, site: site} do
    {:ok, site} = Registry.update_site(site, %{delivery_mode: :dynamic})
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")
    refute has_element?(view, form_id(site))

    {:ok, _site} = Registry.update_site_deploy_targets(site, %{allowed_s3_targets: [@s3]}, :system)
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")
    assert has_element?(view, form_id(site))
  end

  test "a site administrator cannot reach the screen", %{site: site} do
    admin = Brando.Factory.insert(:random_user, role: :user)
    {:ok, _grant} = Access.grant(admin, site, :admin)
    conn = log_in_user(Phoenix.ConnTest.build_conn(), admin)

    assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/sites")
    assert to in ["/admin", "/admin/access-denied"]
  end

  test "the event is refused for a user who is no longer a superuser", %{
    conn: conn,
    site: site,
    current_user: user
  } do
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")

    Process.flag(:trap_exit, true)
    Brando.Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :admin])

    # The screen stops for a changed authority, before the event saves anything
    catch_exit(submit(view, site, [], [@s3]))
    assert_receive {:EXIT, _pid, {:shutdown, :authority_changed}}
    assert targets(site) == {[], []}
  end
end
