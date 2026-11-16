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

  alias Brando.Sites.DeployConfig
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.SSGBuildsTest.TenantRouter
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
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

  defmodule NotingBuilder do
    def build(site, environment, opts) do
      {:ok, result} = SuccessfulBuilder.build(site, environment, opts)
      {:ok, Map.put(result, :notes, ["/about.md: not written"])}
    end
  end

  defmodule HomeOnly do
    @moduledoc false
    import Brando.SSG

    urls :pages do
      ["/"]
    end
  end

  # Brando.SSG with this module's URLs, and no assets or media to copy. It
  # adds neither :base_url nor :endpoint: the origin is the build's own.
  defmodule RenderingBuilder do
    def build(site, environment, opts) do
      empty = Path.join(System.tmp_dir!(), "brando-ssg-empty-#{System.unique_integer([:positive])}")
      File.mkdir_p!(empty)

      try do
        Brando.SSG.build(
          site,
          environment,
          opts ++ [ssg_module: HomeOnly, static_path: empty, media_path: empty, site_files: false]
        )
      after
        File.rm_rf(empty)
      end
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

    put_test_env(DeployConfig,
      rsync_targets: ["deploy@example.test:/srv/www"],
      s3_targets: ["s3://static-bucket/sites/acme"]
    )

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
      Registry.create_environment(
        site,
        %{
          name: "Production",
          key: "production",
          domain: "#{site.key}.test",
          live: true
        },
        actor: :system
      )

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

  test "writes what the build skipped without failing into its log", context do
    build = request_build(context.site, context.environment)
    put_test_env(:ssg_builder, NotingBuilder)

    assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})
    assert Builds.get_build(build.id).build_log =~ ~r/\] \/about\.md: not written\n.*Build completed/s
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

  describe "a build whose creator is gone, groups mode" do
    setup do
      put_test_env(:authorization_mode, :groups)
      Brando.Authorization.Boundary.put_scope(nil)
      on_exit(fn -> Brando.Authorization.Boundary.put_scope(nil) end)

      # Superusers by role become members of the Superuser group
      creator = Brando.Factory.insert(:random_user, role: :superuser)
      recipient = Brando.Factory.insert(:random_user, role: :superuser)
      deleter = Brando.Factory.insert(:random_user, role: :superuser)
      {:ok, _} = Brando.Authorization.Migration.run()

      %{creator: creator, recipient: recipient, deleter: deleter}
    end

    # Handed to the recipient, the build would run on the recipient's authority
    test "is refused after a delete with transfer", context do
      build = request_build(context.site, context.environment, creator_id: context.creator.id)

      assert {:ok, _} = Brando.Users.delete_user_with_transfer(context.creator.id, context.recipient.id, context.deleter)

      put_test_env(:ssg_builder, SuccessfulBuilder)
      assert {:cancel, :forbidden} = perform_job(SSGBuild, %{"build_id" => build.id})

      cancelled = Builds.get_build(build.id)
      assert cancelled.status == :failed
      assert cancelled.creator_id == context.creator.id
      assert cancelled.build_log =~ "Build cancelled"
    end

    test "is refused once the purged account leaves it no creator", context do
      build = request_build(context.site, context.environment, creator_id: context.creator.id)

      Brando.Repo.update_all(
        Ecto.Query.from(b in Brando.SSG.Build, where: b.id == ^build.id),
        set: [creator_id: nil]
      )

      put_test_env(:ssg_builder, SuccessfulBuilder)
      assert {:cancel, :forbidden} = perform_job(SSGBuild, %{"build_id" => build.id})
      assert Builds.get_build(build.id).status == :failed
    end
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

  test "requests the pages from the endpoint's listener, on whatever port it listens", context do
    receiver = Brando.Test.SSGEndpoint.start(fn _request -> {200, "<main>home</main>"} end)
    refute receiver.port == 4000
    put_test_env(:endpoint_module, Brando.Test.SSGEndpoint)
    put_test_env(:ssg_builder, RenderingBuilder)
    build = request_build(context.site, context.environment)

    assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})

    assert_received {:webhook_request, %{path: "/", headers: %{"host" => host}}}
    assert host == "localhost:#{receiver.port}"
    ready = Builds.get_build(build.id)
    assert ready.status == :ready
    assert File.read!(Path.join(ready.build_path, "index.html")) =~ "home"
  end

  test "fails a build, saying why, when the endpoint has no HTTP listener", context do
    # The test application's endpoint runs with server: false
    put_test_env(:ssg_builder, RenderingBuilder)
    build = request_build(context.site, context.environment)

    assert {:error, {:no_http_listener, BrandoIntegrationWeb.Endpoint}} =
             perform_job(SSGBuild, %{"build_id" => build.id})

    failed = Builds.get_build(build.id)
    assert failed.status == :failed
    assert failed.build_log =~ "Build failed: BrandoIntegrationWeb.Endpoint has no HTTP listener on #{node()}"
    assert failed.build_log =~ "must run on a node that serves the endpoint"
    refute failed.build_log =~ "base_url"
    refute File.exists?(failed.build_path)
  end

  test "schedules the Oban job for a future build", context do
    scheduled_at = DateTime.add(DateTime.utc_now(), 3_600, :second)
    build = request_build(context.site, context.environment, scheduled_at: scheduled_at)

    assert DateTime.diff(build.scheduled_at, scheduled_at, :second) == 0
    assert [job] = all_enqueued(worker: SSGBuild, args: %{"build_id" => build.id})
    assert abs(DateTime.diff(job.scheduled_at, scheduled_at, :second)) <= 1
  end

  test "keeps a successful artifact ready when automatic deployment fails", context do
    build = request_build(context.site, context.environment, auto_deploy: true)
    put_test_env(:ssg_builder, SuccessfulBuilder)
    put_test_env(:ssg_deploy_runner, fn "rsync", _args, _opts -> {"connection refused", 255} end)

    assert {:error, {:deploy_failed, {:rsync_failed, 255, "connection refused"}}} =
             perform_job(SSGBuild, %{"build_id" => build.id})

    ready = Builds.get_build(build.id)
    assert ready.status == :ready
    assert ready.build_log =~ "Automatic deployment failed"
  end

  test "deploys automatically by the site's setting when the request does not say", context do
    {:ok, site} = Registry.update_site(context.site, %{deploy_config: %{auto_deploy: true}})
    test_pid = self()
    put_test_env(:ssg_builder, SuccessfulBuilder)

    put_test_env(:ssg_deploy_runner, fn command, _args, _opts ->
      send(test_pid, {:deployed, command})
      {"deployed", 0}
    end)

    build = request_build(site, context.environment)
    assert build.auto_deploy

    assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})
    assert_received {:deployed, "rsync"}
    assert Builds.get_build(build.id).status == :deployed
  end

  test "does not deploy automatically without a deployment target, whatever the request says", context do
    {:ok, site} =
      Registry.update_site(context.site, %{deploy_config: %{strategy: nil, target: nil, auto_deploy: true}})

    for opts <- [[auto_deploy: true], []] do
      build = request_build(site, context.environment, opts)
      refute build.auto_deploy
      put_test_env(:ssg_builder, SuccessfulBuilder)

      assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})
      assert Builds.get_build(build.id).status == :ready
    end
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
    assert_receive {:command, "rsync", ["-az", "--delete", "--", _, "deploy@example.test:/srv/www"]}

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

  # A build carries the config it was made with, which may predate the
  # check on save
  test "an rsync deploy refuses a snapshotted local or option-like target", context do
    for target <- ["/tmp/local-dest", "--log-file=/tmp/marker.log", "u@-oProxyCommand=true:/srv/www"] do
      build = ready_build(context.site, context.environment)
      {:ok, build} = Builds.update(build, %{deploy_config: %{"strategy" => "rsync", "target" => target}})

      runner = fn command, args, _opts ->
        send(self(), {:command, command, args})
        {"", 0}
      end

      assert {:error, :invalid_deploy_target} = Deploy.deploy(build, runner: runner)
      refute_received {:command, "rsync", _}
    end
  end

  test "a deploy job with a refused target is cancelled, not retried", context do
    build = ready_build(context.site, context.environment)
    {:ok, build} = Builds.update(build, %{deploy_config: %{"strategy" => "rsync", "target" => "/tmp/local-dest"}})

    assert {:cancel, :invalid_deploy_target} =
             perform_job(Brando.Worker.SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})
  end

  describe "a snapshotted target, checked again at deploy" do
    setup context do
      {:ok, other} =
        Registry.create_site(%{
          name: "Static Beta",
          key: "static-beta-#{System.unique_integer([:positive])}",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :static
        })

      put_test_env(DeployConfig,
        rsync_targets: ["deploy@static.example.test:/srv/sites/{site_key}"],
        s3_targets: ["s3://static-bucket/sites/{site_key}"]
      )

      %{other_key: other.key, build: ready_build(context.site, context.environment)}
    end

    defp with_target(build, strategy, target) do
      {:ok, build} = Builds.update(build, %{deploy_config: %{"strategy" => strategy, "target" => target}})
      build
    end

    defp recording_runner(command, args, _opts) do
      send(self(), {:command, command, args})
      {"", 0}
    end

    defp recording_s3(operation) do
      send(self(), {:s3, operation})
      {:ok, %{body: %{contents: [], is_truncated: "false"}}}
    end

    test "rsync into another site's directory runs nothing", context do
      build = with_target(context.build, "rsync", "deploy@static.example.test:/srv/sites/#{context.other_key}")

      assert {:error, :invalid_deploy_target} = Deploy.deploy(build, runner: &recording_runner/3)
      refute_received {:command, _, _}
    end

    # The deploy host goes through the test resolver even with the
    # operator's rsync targets overridden, never the machine's DNS:
    # `pinned.test` is loopback there, so this server
    test "rsync to a listed host that resolves to this server runs nothing", context do
      put_test_env(DeployConfig, rsync_targets: ["deploy@pinned.test:/srv/sites/{site_key}"])
      build = with_target(context.build, "rsync", "deploy@pinned.test:/srv/sites/#{context.site.key}")

      assert {:error, :invalid_deploy_target} = Deploy.deploy(build, runner: &recording_runner/3)
      refute_received {:command, _, _}
    end

    test "rsync into its own directory deploys", context do
      target = "deploy@static.example.test:/srv/sites/#{context.site.key}"
      build = with_target(context.build, "rsync", target)

      assert {:ok, %{status: :deployed}} = Deploy.deploy(build, runner: &recording_runner/3)
      assert_received {:command, "rsync", args}
      assert target in args
    end

    test "S3 at another site's prefix or a whole bucket lists and deletes nothing", context do
      for target <- [
            "s3://static-bucket/sites/#{context.other_key}",
            "s3://static-bucket",
            "s3://static-bucket/",
            "s3://static-bucket//",
            "s3://static-bucket/sites/#{context.site.key}/../#{context.other_key}",
            "s3://static-bucket/sites/#{context.other_key}?/sites/#{context.site.key}",
            "s3://other-bucket/sites/#{context.site.key}"
          ] do
        build = with_target(context.build, "s3", target)

        assert {:error, :invalid_deploy_target} = Deploy.deploy(build, s3_request: &recording_s3/1), target
        refute_received {:s3, _}
      end
    end

    test "S3 at its own prefix deploys", context do
      build = with_target(context.build, "s3", "s3://static-bucket/sites/#{context.site.key}")

      assert {:ok, %{status: :deployed}} = Deploy.deploy(build, s3_request: &recording_s3/1)
      assert_received {:s3, %ExAws.Operation.S3{http_method: :get}}
    end

    test "a per-site map is checked at deploy: S3", context do
      put_test_env(DeployConfig,
        s3_targets: %{context.site.key => ["s3://acme-www"], context.other_key => ["s3://beta-www"]}
      )

      build = with_target(context.build, "s3", "s3://beta-www")
      assert {:error, :invalid_deploy_target} = Deploy.deploy(build, s3_request: &recording_s3/1)
      refute_received {:s3, _}

      build = with_target(context.build, "s3", "s3://acme-www")
      assert {:ok, %{status: :deployed}} = Deploy.deploy(build, s3_request: &recording_s3/1)
      assert_received {:s3, %ExAws.Operation.S3{http_method: :get}}
    end

    test "a per-site map is checked at deploy: rsync", context do
      put_test_env(DeployConfig,
        rsync_targets: %{
          context.site.key => ["deploy@acme-www.example.test:/srv/www"],
          context.other_key => ["deploy@beta-www.example.test:/srv/www"]
        }
      )

      build = with_target(context.build, "rsync", "deploy@beta-www.example.test:/srv/www")
      assert {:error, :invalid_deploy_target} = Deploy.deploy(build, runner: &recording_runner/3)
      refute_received {:command, _, _}

      build = with_target(context.build, "rsync", "deploy@acme-www.example.test:/srv/www")
      assert {:ok, %{status: :deployed}} = Deploy.deploy(build, runner: &recording_runner/3)
      assert_received {:command, "rsync", _args}
    end

    test "a queued S3 deploy to another site's prefix is cancelled, not retried", context do
      build = with_target(context.build, "s3", "s3://static-bucket/sites/#{context.other_key}")

      assert {:cancel, :invalid_deploy_target} =
               perform_job(Brando.Worker.SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})
    end

    test "a queued deploy or rollback to a refused target says why in the build log", context do
      for action <- ["deploy", "rollback"] do
        build =
          context.site
          |> ready_build(context.environment)
          |> with_target("s3", "s3://static-bucket/sites/#{context.other_key}")

        refute build.build_log =~ "refused"

        assert {:cancel, :invalid_deploy_target} =
                 perform_job(Brando.Worker.SSGDeploy, %{"build_id" => build.id, "action" => action})

        assert Builds.get_build(build.id).build_log =~ "refused"
      end
    end

    test "with several sites and no list, nothing deploys", context do
      put_test_env(DeployConfig, [])

      build = with_target(context.build, "rsync", "deploy@static.example.test:/srv/sites/#{context.site.key}")
      assert {:error, :invalid_deploy_target} = Deploy.deploy(build, runner: &recording_runner/3)
      refute_received {:command, _, _}

      build = with_target(build, "s3", "s3://static-bucket/sites/#{context.site.key}")
      assert {:error, :invalid_deploy_target} = Deploy.deploy(build, s3_request: &recording_s3/1)
      refute_received {:s3, _}
    end

    test "with one site and no list, any remote or S3 target deploys as before", context do
      put_test_env(DeployConfig, [])

      for mode <- [:single, :none] do
        put_test_env(:tenancy_mode, mode)

        build = with_target(context.build, "rsync", "deploy@static.example.test:/srv/www")
        assert {:ok, deployed} = Deploy.deploy(build, runner: &recording_runner/3)
        assert_received {:command, "rsync", _}

        build = with_target(deployed, "s3", "s3://whole-bucket")
        assert {:ok, deployed} = Deploy.deploy(build, s3_request: &recording_s3/1)
        assert_received {:s3, %ExAws.Operation.S3{http_method: :get}}
        assert deployed.status == :deployed
      end
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
  test "serves a preview only on its own site's host, with a restrictive policy", context do
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
      Registry.create_environment(
        other_site,
        %{
          name: "Production",
          key: "production",
          domain: "#{other_site.key}.test",
          live: true
        },
        actor: :system
      )

    build = ready_build(context.site, context.environment)

    own = preview(build, "#{context.site.key}.test")
    assert response(own, 200) == build.version
    assert [policy] = get_resp_header(own, "content-security-policy")
    assert policy =~ "sandbox allow-scripts"
    assert policy =~ "form-action 'none'"
    assert get_resp_header(own, "x-content-type-options") == ["nosniff"]

    assert response(preview(build, "#{other_site.key}.test"), 404)
    assert response(preview(build, "unknown.test"), 404)
  end

  # Audit F02: a preview keeps its origin and lets scripts run, so it must not
  # open on the admin's host, even for a site bound to it before that was
  # refused.
  test "refuses a preview on the installation's own host", context do
    build = ready_build(context.site, context.environment)
    admin_host = URI.parse(Brando.endpoint().url()).host

    assert response(preview(build, admin_host), 404)

    context.environment
    |> Ecto.Changeset.change(domain: admin_host)
    |> Brando.Repo.update!(prefix: "public")

    Brando.Tenant.Cache.invalidate()

    assert response(preview(build, admin_host), 404)
  end

  test "refuses a preview when tenancy is on but the request resolved no site", context do
    build = ready_build(context.site, context.environment)

    conn = get(Phoenix.ConnTest.build_conn(), "/__ssg_preview__/#{build.preview_token}/")
    assert response(conn, 404) == "Static preview not found"
  end

  defp preview(build, host, path \\ "") do
    Phoenix.ConnTest.build_conn(:get, "/__ssg_preview__/#{build.preview_token}/#{path}")
    |> Map.put(:host, host)
    |> TenantRouter.call(TenantRouter.init([]))
  end

  test "a preview serves the build's Markdown alternates through an endpoint with the Markdown plug", context do
    build = ready_build(context.site, context.environment)
    File.write!(Path.join(build.build_path, "about.md"), "# About\n")
    markdown = Brando.Plug.Markdown.init([])

    conn =
      Phoenix.ConnTest.build_conn(:get, "/__ssg_preview__/#{build.preview_token}/about.md")
      |> Map.put(:host, "#{context.site.key}.test")
      |> Brando.Plug.Markdown.call(markdown)
      |> TenantRouter.call(TenantRouter.init([]))

    assert response(conn, 200) == "# About\n"
    assert response_content_type(conn, :markdown) =~ "text/markdown"
  end

  test "a preview loads the build's own files and its links stay inside it", context do
    build = ready_build(context.site, context.environment)
    host = "#{context.site.key}.test"
    prefix = "/__ssg_preview__/#{build.preview_token}"

    site_url =
      Brando.Tenant.with_prefix(Brando.Tenant.prefix(context.site, context.environment), &Brando.Utils.public_hostname/0)

    page =
      ~s(<link rel="stylesheet" href="/assets/app.css"><script type="module" src="/assets/app.js"></script>) <>
        ~s(<a href="/about">About</a><a href='#{site_url}/contact?x=1'>Contact</a><a href="#{site_url}">Home</a>) <>
        ~s(<a href="https://elsewhere.example.com/">Away</a><a href="//cdn.example.com/x.js">CDN</a>) <>
        ~s(<img data-srcset="/media/a.jpg 400w, /media/b.jpg 800w" src="data:image/gif;base64,R0lGOD">) <>
        ~s|<div style="background-image: url('/media/bg.jpg')"></div>|

    File.write!(Path.join(build.build_path, "index.html"), page)
    File.mkdir_p!(Path.join(build.build_path, "assets"))
    File.write!(Path.join([build.build_path, "assets", "app.css"]), "body{background:url(/media/bg.jpg)}")
    File.write!(Path.join(build.build_path, "404.html"), ~s(<a href="/">Back</a>))

    html = response(preview(build, host), 200)

    assert html ==
             ~s(<link rel="stylesheet" href="#{prefix}/assets/app.css"><script type="module" src="#{prefix}/assets/app.js"></script>) <>
               ~s(<a href="#{prefix}/about">About</a><a href='#{prefix}/contact?x=1'>Contact</a><a href="#{prefix}/">Home</a>) <>
               ~s(<a href="https://elsewhere.example.com/">Away</a><a href="//cdn.example.com/x.js">CDN</a>) <>
               ~s(<img data-srcset="#{prefix}/media/a.jpg 400w, #{prefix}/media/b.jpg 800w" src="data:image/gif;base64,R0lGOD">) <>
               ~s|<div style="background-image: url('#{prefix}/media/bg.jpg')"></div>|

    css = preview(build, host, "assets/app.css")
    assert response(css, 200) == "body{background:url(#{prefix}/media/bg.jpg)}"
    assert [content_type] = get_resp_header(css, "content-type")
    assert content_type =~ "text/css"

    # The artifact keeps the bytes it was built with
    assert File.read!(Path.join(build.build_path, "index.html")) == page

    # A path the build has no file for answers the build's own error page
    assert response(preview(build, host, "missing"), 404) == ~s(<a href="#{prefix}/">Back</a>)
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
