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

  defmodule Builder do
    @moduledoc false
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      {:ok, %{file_count: 0, total_size: 0, url_count: 0, processed_urls: 0, failed_urls: []}}
    end
  end

  test "queues and renders a static build from the selected environment", context do
    put_test_env(:ssg_builder, Builder)
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

    # The build ran inline in the LiveView's process, and reported on its
    # row, which keeps it out of a toast
    BrandoAdmin.Work.Registry.sync()
    assert has_element?(view, "#ssg-build-#{build.id} .work-status[data-status=finished]", "Static build v1 is ready")
  end

  test "a deploy reports on the build's row", context do
    {:ok, build} = Builds.request_build(context.site, context.environment, [])
    {:ok, ready} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
    user = :sys.get_state(view.pid).socket.assigns.current_user

    # The job runs inline: without a strategy it fails at once, with retries
    # left, rather than calling out
    {:ok, _site} = Registry.update_site(context.site, %{deploy_config: %{strategy: nil, target: nil}})
    view |> element("#ssg-build-#{ready.id} button[phx-click=deploy]") |> render_click()

    BrandoAdmin.Work.Registry.sync()
    assert has_element?(view, "#ssg-build-#{ready.id} .work-status[data-status=running]", "Deploying v1")
    BrandoAdmin.Work.finish(user, Brando.Worker.SSGBuild.work_key(ready.id), nil, global: true)
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
        webhook_url: "https://hooks.example.com/published",
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

  test "an rsync target must be a remote destination", context do
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    for target <- ["/tmp/local-dest", "--log-file=/tmp/marker.log", "u@-oProxyCommand=true:/srv/www"] do
      render_submit(form(view, "#static-deploy-config"), %{"deploy" => %{"strategy" => "rsync", "target" => target}})
      assert Registry.get_site(context.site.id).deploy_config.target == "deploy@example.test:/srv/www"
    end

    render_submit(form(view, "#static-deploy-config"), %{
      "deploy" => %{"strategy" => "rsync", "target" => "web@static.example.test:/srv/site"}
    })

    assert Registry.get_site(context.site.id).deploy_config.target == "web@static.example.test:/srv/site"
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
