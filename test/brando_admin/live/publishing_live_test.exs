defmodule BrandoAdmin.Sites.PublishingLiveTest do
  use Brando.LiveCase

  alias Brando.SSG.Builds
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  setup do
    root = Path.join(System.tmp_dir!(), "brando-publishing-live-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Publishing Acme",
        key: "publishing-acme-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :rsync, target: "deploy@example.test:/srv/www"}
      })

    {:ok, environment} =
      Registry.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    %{site: Registry.get_site(site.id), environment: environment}
  end

  test "queues and renders a static build from the selected environment", context do
    {:ok, view, html} = live(context.conn, "/admin/config/publishing")

    assert html =~ "Publishing"
    assert html =~ "Publishing Acme"
    assert has_element?(view, "#build-static-site")

    Oban.Testing.with_testing_mode(:manual, fn ->
      view
      |> form("#build-static-site",
        build: %{
          environment_id: context.environment.id,
          note: "Campaign release"
        }
      )
      |> render_submit()
    end)

    assert [build] = Builds.list_builds(context.site)
    assert build.version == "v1"
    assert build.note == "Campaign release"
    assert build.environment_id == context.environment.id
    assert has_element?(view, "#ssg-build-#{build.id}", "Campaign release")
  end

  test "hides publishing from dynamically delivered sites", context do
    {:ok, _dynamic_site} = Registry.update_site(context.site, %{delivery_mode: :dynamic})
    Cache.clear()

    assert {:error, {:redirect, %{to: "/admin"}}} =
             live(context.conn, "/admin/config/publishing")
  end

  test "updates the static deployment configuration", context do
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    view
    |> form("#static-deploy-config",
      deploy: %{
        strategy: "s3",
        target: "s3://publishing-site/releases",
        cdn_url: "https://static.example.test",
        webhook_url: "https://hooks.example.test/published",
        retention_count: "20",
        auto_deploy: "true"
      }
    )
    |> render_submit()

    updated = Registry.get_site(context.site.id)
    assert updated.deploy_config.strategy == :s3
    assert updated.deploy_config.target == "s3://publishing-site/releases"
    assert updated.deploy_config.auto_deploy
    assert updated.deploy_config.retention_count == 20
  end

  test "renders nested deployment validation errors without crashing", context do
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    assert render_submit(form(view, "#static-deploy-config"), %{
             "deploy" => %{
               "strategy" => "s3",
               "target" => "not-an-s3-target",
               "webhook_url" => "javascript:alert(1)",
               "retention_count" => "10"
             }
           })

    unchanged = Registry.get_site(context.site.id)
    assert unchanged.deploy_config.strategy == :rsync
    assert unchanged.deploy_config.target == "deploy@example.test:/srv/www"
  end
end
