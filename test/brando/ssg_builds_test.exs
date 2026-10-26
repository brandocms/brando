defmodule Brando.SSGBuildsTest.TenantRouter do
  @moduledoc false
  use Phoenix.Router
  import Brando.Router

  pipeline :site do
    plug Brando.Plug.Tenant
  end

  scope "/" do
    pipe_through :site
    page_routes(catch_all: false)
  end
end

defmodule Brando.SSGBuildsTest do
  use Brando.ConnCase

  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.SSGBuildsTest.TenantRouter
  alias Brando.Worker.SSGBuild

  defmodule SuccessfulBuilder do
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), "built")

      {:ok,
       %{
         file_count: 1,
         total_size: 5,
         url_count: 2,
         processed_urls: 2,
         failed_urls: []
       }}
    end
  end

  defmodule FailedBuilder do
    def build(_site, _environment, _opts) do
      {:error, :url_failures,
       %{
         file_count: 1,
         total_size: 5,
         url_count: 2,
         processed_urls: 2,
         failed_urls: ["/broken (HTTP 500)"]
       }}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-ssg-builds-#{System.unique_integer([:positive])}")
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
        name: "Static Acme",
        key: "static-acme-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{
          strategy: :rsync,
          target: "deploy@example.test:/srv/www",
          retention_count: 2
        }
      })

    {:ok, environment} =
      Registry.create_environment(site, %{
        name: "Production",
        key: "production",
        domain: "#{site.key}.test",
        live: true
      })

    %{site: Registry.get_site(site.id), environment: environment, root: root}
  end

  test "assigns monotonic versions and executes the successful worker lifecycle", context do
    first = request_build(context.site, context.environment)
    second = request_build(context.site, context.environment)

    assert first.version == "v1"
    assert second.version == "v2"
    assert first.status == :queued
    assert second.build_path == Path.join(Builds.build_root(context.site), "v2")

    put_test_env(:ssg_builder, SuccessfulBuilder)
    assert :ok = perform_job(SSGBuild, %{"build_id" => first.id})

    ready = Builds.get_build(first.id)
    assert ready.status == :ready
    assert ready.file_count == 1
    assert ready.processed_urls == 2
    assert ready.built_at
    assert ready.build_log =~ "Build completed"
    assert File.read!(Path.join(ready.build_path, "index.html")) == "built"
  end

  test "reports the build to its creator as it is queued, built and ready", context do
    creator = Brando.Factory.insert(:random_user)
    BrandoAdmin.Work.subscribe(creator)
    build = request_build(context.site, context.environment, creator_id: creator.id)
    key = SSGBuild.work_key(build.id)

    assert_receive {:work, ^key, :running, %BrandoAdmin.Work{message: "Static build v1 is queued", prefix: nil}}

    put_test_env(:ssg_builder, SuccessfulBuilder)
    assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})

    assert_receive {:work, ^key, :running, %BrandoAdmin.Work{message: "Building static version v1"}}
    assert_receive {:work, ^key, :finished, %BrandoAdmin.Work{message: "Static build v1 is ready"}}

    failed = request_build(context.site, context.environment, creator_id: creator.id)
    failed_key = SSGBuild.work_key(failed.id)
    put_test_env(:ssg_builder, FailedBuilder)
    assert {:error, :url_failures} = perform_job(SSGBuild, %{"build_id" => failed.id})
    assert_receive {:work, ^failed_key, :failed, %BrandoAdmin.Work{message: "Static build v2 failed"}}
  end

  test "a build requested inside a caller's transaction reports only when it runs", context do
    creator = Brando.Factory.insert(:random_user)
    BrandoAdmin.Work.subscribe(creator)

    {:ok, build} =
      Brando.Repo.transaction(fn -> request_build(context.site, context.environment, creator_id: creator.id) end)

    key = SSGBuild.work_key(build.id)
    refute_receive {:work, ^key, _, _}, 100

    put_test_env(:ssg_builder, SuccessfulBuilder)
    assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})
    assert_receive {:work, ^key, :finished, %BrandoAdmin.Work{message: "Static build v1 is ready"}}
  end

  # Killed at its timeout three times: Oban gives the job up, and the work fails
  test "a build job Oban gives up on fails its work", context do
    creator = Brando.Factory.insert(:random_user)
    BrandoAdmin.Work.subscribe(creator)
    build = request_build(context.site, context.environment, creator_id: creator.id)
    key = SSGBuild.work_key(build.id)
    assert_receive {:work, ^key, :running, _}

    [job] = all_enqueued(worker: SSGBuild, args: %{"build_id" => build.id})
    :telemetry.execute([:oban, :job, :exception], %{}, %{job: job, state: :discard})
    assert_receive {:work, ^key, :failed, %BrandoAdmin.Work{message: "Static build v1 failed"}}
  end

  test "persists failed URLs and a terminal failure log", context do
    build = request_build(context.site, context.environment)
    put_test_env(:ssg_builder, FailedBuilder)

    assert {:error, :url_failures} = perform_job(SSGBuild, %{"build_id" => build.id})

    failed = Builds.get_build(build.id)
    assert failed.status == :failed
    assert failed.failed_urls == ["/broken (HTTP 500)"]
    assert failed.build_log =~ "Build failed"
  end

  test "schedules the Oban job for a future build", context do
    scheduled_at = DateTime.add(DateTime.utc_now(), 3_600, :second)
    build = request_build(context.site, context.environment, scheduled_at: scheduled_at)

    assert DateTime.diff(build.scheduled_at, scheduled_at, :second) == 0
    assert [job] = all_enqueued(worker: SSGBuild, args: %{"build_id" => build.id})
    assert abs(DateTime.diff(job.scheduled_at, scheduled_at, :second)) <= 1
  end

  test "keeps a successful artifact ready when automatic deployment fails", context do
    {:ok, site} = Registry.update_site(context.site, %{deploy_config: %{strategy: nil, target: nil}})
    build = request_build(site, context.environment, auto_deploy: true)
    put_test_env(:ssg_builder, SuccessfulBuilder)

    assert {:error, {:deploy_failed, :deploy_strategy_not_configured}} =
             perform_job(SSGBuild, %{"build_id" => build.id})

    ready = Builds.get_build(build.id)
    assert ready.status == :ready
    assert ready.build_log =~ "Automatic deployment failed"
  end

  test "deploys a build, archives its predecessor, and rolls back safely", context do
    first = ready_build(context.site, context.environment)
    second = ready_build(context.site, context.environment)
    test_pid = self()

    runner = fn command, args, _opts ->
      send(test_pid, {:command, command, args})
      {"deployed", 0}
    end

    assert {:ok, deployed_first} = Deploy.deploy(first, runner: runner)
    assert deployed_first.status == :deployed
    assert_receive {:command, "rsync", ["-az", "--delete", _, "deploy@example.test:/srv/www"]}

    assert {:ok, deployed_second} = Deploy.deploy(second, runner: runner)
    assert deployed_second.status == :deployed
    assert Builds.get_build(first.id).status == :archived

    assert {:ok, rolled_back} = Deploy.rollback(context.site, first, runner: runner)
    assert rolled_back.status == :deployed
    assert Builds.get_build(second.id).status == :archived
  end

  # Audit F26: the completion webhook may only reach a public address, is
  # posted to the address checked without following redirects, and the build
  # log does not say what answered.
  describe "the completion webhook" do
    defp deploy_with_webhook(context, url) do
      build = ready_build(context.site, context.environment)
      {:ok, build} = Builds.update(build, %{deploy_config: Map.put(build.deploy_config, "webhook_url", url)})
      assert {:ok, deployed} = Deploy.deploy(build, runner: fn _command, _args, _opts -> {"deployed", 0} end)
      Builds.get_build(deployed.id)
    end

    test "must be https to a public address when saved", context do
      for {url, error} <- [
            {"http://127.0.0.1:6379/", "must start with https://"},
            {"https://169.254.169.254/latest/meta-data", "points to a private or local network address"},
            {"https://hooks.internal.test/x", "points to a private or local network address"},
            {"https://user:pass@hooks.example.com/x", "must not contain a user name or password"}
          ] do
        assert {:error, changeset} =
                 Registry.update_site(context.site, %{
                   deploy_config: %{strategy: :rsync, target: "deploy@example.test:/srv/www", webhook_url: url}
                 })

        assert {^error, _} = changeset.changes.deploy_config.errors[:webhook_url], url
      end

      assert {:ok, site} =
               Registry.update_site(context.site, %{
                 deploy_config: %{
                   strategy: :rsync,
                   target: "deploy@example.test:/srv/www",
                   webhook_url: "https://hooks.example.com/published"
                 }
               })

      assert site.deploy_config.webhook_url == "https://hooks.example.com/published"
    end

    test "is not posted to a private address saved before the check", context do
      receiver = Brando.WebhookReceiver.start()
      build = deploy_with_webhook(context, Brando.WebhookReceiver.url(receiver, "/hook"))

      refute_receive {:webhook_request, _}, 200
      assert build.status == :deployed
      assert build.build_log =~ "Deployment webhook not sent: its URL must start with https://"
    end

    test "is posted to the address checked, and a redirect is not followed", context do
      put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})

      receiver =
        Brando.WebhookReceiver.start(fn
          %{path: "/hook"} -> {302, [{"location", "/elsewhere"}], ""}
          _request -> {200, "ok"}
        end)

      build = deploy_with_webhook(context, "http://pinned.test:#{receiver.port}/hook")

      assert_receive {:webhook_request, %{method: "POST", path: "/hook", headers: headers, body: body}}
      assert headers["host"] == "pinned.test:#{receiver.port}"
      assert %{"event" => "deploy", "status" => "deployed"} = Jason.decode!(body)
      refute_receive {:webhook_request, %{path: "/elsewhere"}}, 200

      assert build.build_log =~ "Deployment webhook failed"
      refute build.build_log =~ "302"
    end

    test "answered with a success leaves the log alone", context do
      put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})
      receiver = Brando.WebhookReceiver.start()

      build = deploy_with_webhook(context, "http://pinned.test:#{receiver.port}/hook")

      assert_receive {:webhook_request, %{method: "POST", path: "/hook"}}
      refute build.build_log =~ "webhook"
    end
  end

  test "S3 deployment removes stale target keys before uploading the artifact", context do
    build = ready_build(context.site, context.environment)

    {:ok, build} =
      Builds.update(build, %{
        deploy_config: %{
          "strategy" => "s3",
          "target" => "s3://static-bucket/sites/acme",
          "retention_count" => 2
        }
      })

    test_pid = self()

    request = fn
      %ExAws.Operation.S3{http_method: :get} ->
        {:ok,
         %{
           body: %{
             contents: [%{key: "sites/acme/stale.js"}],
             is_truncated: "false"
           }
         }}

      %ExAws.Operation.S3DeleteAllObjects{objects: objects} ->
        send(test_pid, {:deleted, objects})
        {:ok, %{}}

      %ExAws.Operation.S3{http_method: :put, path: path} ->
        send(test_pid, {:uploaded, path})
        {:ok, %{}}
    end

    assert {:ok, deployed} = Deploy.deploy(build, s3_request: request)
    assert deployed.status == :deployed
    assert_receive {:deleted, ["sites/acme/stale.js"]}
    assert_receive {:uploaded, "sites/acme/index.html"}
  end

  test "serves ready previews and rejects pruned artifacts", context do
    build = ready_build(context.site, context.environment)

    conn = preview(build, "#{context.site.key}.test")
    assert response(conn, 200) == build.version
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]

    {:ok, _pruned} = Builds.update(build, %{pruned_at: DateTime.utc_now()})

    missing = preview(build, "#{context.site.key}.test")
    assert response(missing, 404) == "Static preview not found"
  end

  # Audit F15: the artifact carries the site's raw markup, so it must not run
  # in another site's origin.
  test "serves a preview only on its own site's host, sandboxed", context do
    {:ok, other_site} =
      Registry.create_site(%{
        name: "Static Beta",
        key: "static-beta-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static
      })

    {:ok, _environment} =
      Registry.create_environment(other_site, %{
        name: "Production",
        key: "production",
        domain: "#{other_site.key}.test",
        live: true
      })

    build = ready_build(context.site, context.environment)

    own = preview(build, "#{context.site.key}.test")
    assert response(own, 200) == build.version
    assert [policy] = get_resp_header(own, "content-security-policy")
    assert policy =~ "sandbox allow-scripts"
    refute policy =~ "allow-same-origin"
    assert get_resp_header(own, "x-content-type-options") == ["nosniff"]

    assert response(preview(build, "#{other_site.key}.test"), 404)
    assert response(preview(build, "unknown.test"), 404)
  end

  test "refuses a preview when tenancy is on but the request resolved no site", context do
    build = ready_build(context.site, context.environment)

    conn = get(Phoenix.ConnTest.build_conn(), "/__ssg_preview__/#{build.preview_token}/")
    assert response(conn, 404) == "Static preview not found"
  end

  defp preview(build, host) do
    Phoenix.ConnTest.build_conn(:get, "/__ssg_preview__/#{build.preview_token}/")
    |> Map.put(:host, host)
    |> TenantRouter.call(TenantRouter.init([]))
  end

  test "retains environment history after the source environment is deleted", context do
    build = request_build(context.site, context.environment)
    assert {:ok, _environment} = Registry.delete_environment(context.environment)

    historical = Builds.get_build(build.id)
    assert historical.environment == nil
    assert historical.environment_name == "Production"
    assert historical.environment_key == "production"

    assert {:cancel, :environment_not_found} = perform_job(SSGBuild, %{"build_id" => build.id})
    assert Builds.get_build(build.id).status == :failed
  end

  test "prunes old artifact directories but retains build history", context do
    first = ready_build(context.site, context.environment)
    second = ready_build(context.site, context.environment)
    newest = ready_build(context.site, context.environment)

    assert {:ok, pruned} = Deploy.prune(context.site, 1)
    assert Enum.map(pruned, & &1.id) == [second.id, first.id]
    refute File.exists?(first.build_path)
    refute File.exists?(second.build_path)
    assert File.exists?(newest.build_path)
    assert Builds.get_build(first.id).pruned_at
  end

  test "rejects lifecycle requests for dynamically delivered sites", context do
    {:ok, dynamic_site} = Registry.update_site(context.site, %{delivery_mode: :dynamic})

    assert {:error, :dynamic_site} =
             Builds.request_build(dynamic_site, context.environment)
  end

  test "rejects lifecycle requests for inactive sites", context do
    {:ok, suspended_site} = Registry.update_site(context.site, %{status: :suspended})

    assert {:error, :inactive_site} =
             Builds.request_build(suspended_site, context.environment)
  end

  defp request_build(site, environment, opts \\ []) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, build} = Builds.request_build(site, environment, opts)
      build
    end)
  end

  defp ready_build(site, environment) do
    build = request_build(site, environment)
    File.mkdir_p!(build.build_path)
    File.write!(Path.join(build.build_path, "index.html"), build.version)
    {:ok, ready} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
    ready
  end
end
