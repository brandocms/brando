defmodule Brando.SSG.PublishingTest do
  # The state of the environment a site publishes from, and the actions of
  # the Publish button, on real environment schemas: the activity log and
  # the notification routes are the environment's own
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments
  alias Brando.Factory
  alias Brando.Notifications.Routing
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.SSG.Publishing
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.WebhookReceiver
  alias Brando.Worker.SSGBuild
  alias Brando.Worker.SSGDeploy

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  defmodule Builder do
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), "built")
      {:ok, %{file_count: 1, total_size: 5, url_count: 1, processed_urls: 1, failed_urls: []}}
    end
  end

  defmodule FailingBuilder do
    def build(_site, _environment, _opts), do: {:error, :renderer_down}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-publishing-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    put_test_env(:ssg_builder, Builder)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    user = Factory.insert(:random_user, role: :superuser)
    key = "publish-#{System.unique_integer([:positive])}"

    {:ok, site} =
      Registry.create_site(%{
        name: "Publish Acme",
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :local}
      })

    production = environment!(site, "production", true)
    staging = environment!(site, "staging", false)

    %{user: user, site: Registry.get_site(site.id), production: production, staging: staging}
  end

  defp environment!(site, key, live) do
    {:ok, environment} =
      Environments.create_environment(site, %{name: key, key: key, live: live, domain: "#{key}.#{site.key}.test"},
        actor: :system
      )

    environment
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  defp jobs(worker) do
    from(job in Oban.Job, where: job.worker == ^worker, order_by: job.id)
    |> Brando.Repo.all(prefix: "public")
  end

  # Oban sets `attempted_at` when a job starts executing
  defp set_job_state(%Oban.Job{id: id}, state, attempted_at \\ DateTime.utc_now()) do
    from(job in Oban.Job, where: job.id == ^id)
    |> Brando.Repo.update_all([set: [state: state, attempted_at: attempted_at]], prefix: "public")
  end

  # Runs a job as Oban would, and leaves its row as Oban would after the result
  defp perform(worker, job) do
    result = worker.perform(%{job | attempt: job.attempt + 1})

    set_job_state(
      job,
      case result do
        :ok -> "completed"
        {:cancel, _reason} -> "cancelled"
        {:error, _reason} -> "retryable"
      end
    )

    result
  end

  defp mark_changed(environment) do
    Brando.Repo.repo().query!(
      "INSERT INTO public.ssg_content_changes (environment_id, changed_at) VALUES ($1, $2) " <>
        "ON CONFLICT (environment_id) DO UPDATE SET changed_at = EXCLUDED.changed_at",
      [environment.id, DateTime.utc_now()]
    )
  end

  defp state(c, environment \\ nil) do
    case Publishing.status(Registry.get_site(c.site.id), environment || c.production) do
      %{state: state} -> state
      :elsewhere -> :elsewhere
    end
  end

  defp site(c), do: Registry.get_site(c.site.id)

  describe "the environment it publishes from" do
    test "is the live one before anything is deployed, then the deployed build's", c do
      assert %{state: :changes, deployed: nil} = Publishing.status(c.site, c.production)
      assert Publishing.status(c.site, c.staging) == :elsewhere

      {:ok, build} = Builds.request_build(c.site, c.staging, creator_id: c.user.id, auto_deploy: true)
      assert Builds.get_build(build.id).status == :deployed

      assert state(c) == :elsewhere
      assert %{state: :published} = Publishing.status(site(c), c.staging)
      assert {:error, :not_publishing_environment} = Publishing.publish(c.site, c.production, c.user)
    end

    test "is the live one again when the deployed build's environment is gone", c do
      {:ok, build} = Builds.request_build(c.site, c.staging, creator_id: c.user.id, auto_deploy: true)
      from(b in Build, where: b.id == ^build.id) |> Brando.Repo.update_all([set: [environment_id: nil]], prefix: "public")

      assert %{state: :changes, deployed: nil} = Publishing.status(site(c), c.production)
    end
  end

  describe "publish" do
    test "builds and deploys whatever the site's auto-deploy says, and a change made after makes it unpublished",
         c do
      refute c.site.deploy_config.auto_deploy
      assert {:ok, build} = Publishing.publish(c.site, c.production, c.user)

      assert %Build{status: :deployed, auto_deploy: true} = Builds.get_build(build.id)
      assert %{state: :published, deployed: %Build{id: id}} = Publishing.status(site(c), c.production)
      assert id == build.id

      mark_changed(c.production)
      assert state(c) == :changes
    end

    test "starts nothing while a build of the environment waits, builds or owes its deploy", c do
      {build, [job]} =
        manual(fn ->
          {:ok, build} = Publishing.publish(c.site, c.production, c.user)
          assert {:error, :publishing} = Publishing.publish(c.site, c.production, c.user)
          assert {:error, :publishing} = Publishing.publish(c.site, c.production, c.user, deploy: false)
          {build, jobs("Brando.Worker.SSGBuild")}
        end)

      assert [_one] = Builds.list_builds(c.site)
      assert %{state: :publishing, step: :waiting} = Publishing.status(site(c), c.production)

      set_job_state(job, "executing")
      assert %{state: :publishing, step: :building} = Publishing.status(site(c), c.production)

      # Ready, its automatic deploy running: a second click starts nothing
      {:ok, _ready} = Builds.update(build, %{status: :ready, started_at: DateTime.utc_now()})
      assert %{state: :publishing, step: :deploying} = Publishing.status(site(c), c.production)
      assert {:error, :publishing} = manual(fn -> Publishing.publish(c.site, c.production, c.user) end)
      assert [_one] = Builds.list_builds(c.site)
    end

    test "waits behind another environment's build rather than refusing", c do
      manual(fn ->
        {:ok, _staging} = Builds.request_build(c.site, c.staging, creator_id: c.user.id)
        assert {:ok, _build} = Publishing.publish(c.site, c.production, c.user)
      end)

      assert length(Builds.list_builds(c.site)) == 2
      assert %{state: :publishing, step: :waiting} = Publishing.status(site(c), c.production)
    end

    test "is refused to someone who may not manage the site's publishing, and checks it when it runs", c do
      editor = Factory.insert(:random_user, role: :editor)
      {:ok, _} = Brando.Tenant.Access.grant(editor, c.site, :editor)

      assert {:error, :forbidden} = Publishing.publish(c.site, c.production, editor)
      assert {:error, :forbidden} = Publishing.retry(c.site, c.production, editor)
      assert Builds.list_builds(c.site) == []
    end

    test "is refused for a site without a deploy target, and for a dynamic one", c do
      {:ok, _site} = Registry.update_site(c.site, %{deploy_config: %{strategy: nil}})
      assert {:error, :no_deploy_target} = Publishing.publish(c.site, c.production, c.user)

      {:ok, _site} = Registry.update_site(site(c), %{delivery_mode: :dynamic, deploy_config: %{strategy: :local}})
      assert {:error, :not_publishable} = Publishing.publish(c.site, c.production, c.user)
      assert Builds.list_builds(c.site) == []
    end
  end

  describe "a build scheduled for later" do
    test "is no attempt until it is due: it neither shows as publishing nor hides an earlier state", c do
      {:ok, ready} = Publishing.publish(c.site, c.production, c.user, deploy: false)
      assert state(c) == :ready

      manual(fn ->
        {:ok, _scheduled} =
          Builds.request_build(c.site, c.production,
            creator_id: c.user.id,
            scheduled_at: DateTime.add(DateTime.utc_now(), 1, :hour)
          )
      end)

      assert %{state: :ready, build: %Build{id: id}} = Publishing.status(site(c), c.production)
      assert id == ready.id

      put_test_env(:ssg_builder, FailingBuilder)
      {:ok, _failed} = Publishing.publish(c.site, c.production, c.user)
      assert %{state: :failed, failed: :build} = Publishing.status(site(c), c.production)
    end
  end

  describe "failed" do
    test "after a failed build, Try again builds and deploys again", c do
      put_test_env(:ssg_builder, FailingBuilder)
      {:ok, failed} = Publishing.publish(c.site, c.production, c.user)
      assert %{state: :failed, failed: :build, build: %Build{id: id}} = Publishing.status(site(c), c.production)
      assert id == failed.id

      put_test_env(:ssg_builder, Builder)
      assert {:ok, %Build{} = again} = Publishing.retry(c.site, c.production, c.user)
      refute again.id == failed.id
      assert Builds.get_build(again.id).status == :deployed
      assert state(c) == :published
    end

    test "after a failed deploy, Try again deploys the same build", c do
      put_test_env(Brando.Sites.DeployConfig, local_delivery: false)
      {:ok, build} = Publishing.publish(c.site, c.production, c.user)

      assert %Build{status: :ready, deploy_failed_at: %DateTime{}} = Builds.get_build(build.id)
      assert %{state: :failed, failed: :deploy} = Publishing.status(site(c), c.production)

      put_test_env(Brando.Sites.DeployConfig, local_delivery: true)
      assert {:ok, %Oban.Job{}} = Publishing.retry(c.site, c.production, c.user)
      assert %Build{status: :deployed, deploy_failed_at: nil} = Builds.get_build(build.id)
      assert [_one] = Builds.list_builds(c.site)
    end

    test "a deploy given up reads as failed while its job still executes; Try again as publishing", c do
      {:ok, ready} = Publishing.publish(c.site, c.production, c.user, deploy: false)
      manual(fn -> {:ok, _job} = Publishing.publish_build(c.site, c.production, ready.id, c.user) end)
      [job] = jobs("Brando.Worker.SSGDeploy")
      set_job_state(job, "executing")
      assert %{state: :publishing, step: :deploying} = Publishing.status(site(c), c.production)

      # The worker records the failure, and broadcasts it, before it returns to Oban
      :ok = Publishing.deploy_failed(Builds.get_build(ready.id))
      assert %{state: :failed, failed: :deploy} = Publishing.status(site(c), c.production)

      manual(fn ->
        assert {:ok, %Oban.Job{}} = Publishing.retry(c.site, c.production, c.user)
        assert %{state: :publishing, step: :waiting} = Publishing.status(site(c), c.production)
        assert {:error, :stale} = Publishing.retry(c.site, c.production, c.user)
      end)
    end

    test "Try again when nothing failed starts nothing", c do
      assert {:error, :stale} = Publishing.retry(c.site, c.production, c.user)
      assert Builds.list_builds(c.site) == []
    end
  end

  describe "ready" do
    test "Preview first builds without deploying; Publish this build deploys it although content changed since",
         c do
      {:ok, build} = Publishing.publish(c.site, c.production, c.user, deploy: false)
      assert %Build{status: :ready, auto_deploy: false} = Builds.get_build(build.id)
      mark_changed(c.production)

      assert %{state: :ready, build: %Build{id: id}} = Publishing.status(site(c), c.production)
      assert id == build.id

      assert {:ok, %Oban.Job{}} = Publishing.publish_build(c.site, c.production, build.id, c.user)
      assert Builds.get_build(build.id).status == :deployed
      assert site(c).published_build == build.version
      assert state(c) == :changes
    end

    test "Publish this build deploys only the ready build of this environment and site, with its files", c do
      {:ok, other} =
        Registry.create_site(%{
          name: "Other Acme",
          key: "other-#{System.unique_integer([:positive])}",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :static
        })

      other_production = environment!(other, "production", true)
      {:ok, other_build} = Builds.request_build(Registry.get_site(other.id), other_production, creator_id: c.user.id)
      {:ok, staging} = Builds.request_build(c.site, c.staging, creator_id: c.user.id)
      {:ok, ready} = Publishing.publish(c.site, c.production, c.user, deploy: false)

      for id <- [other_build.id, staging.id, ready.id + 1000] do
        assert {:error, :stale} = Publishing.publish_build(c.site, c.production, id, c.user)
      end

      # Pruned between opening the panel and pressing
      {:ok, _pruned} = Builds.update(ready, %{pruned_at: DateTime.utc_now()})
      File.rm_rf!(ready.build_path)
      assert {:error, :stale} = Publishing.publish_build(c.site, c.production, ready.id, c.user)
      assert Builds.get_build(ready.id).status == :ready
      assert Builds.get_build(other_build.id).status == :ready
    end

    test "two clicks on Publish this build give one deploy", c do
      {:ok, ready} = Publishing.publish(c.site, c.production, c.user, deploy: false)

      manual(fn ->
        assert {:ok, %Oban.Job{}} = Publishing.publish_build(c.site, c.production, ready.id, c.user)
        assert {:error, :stale} = Publishing.publish_build(c.site, c.production, ready.id, c.user)
      end)

      assert [_one] = jobs("Brando.Worker.SSGDeploy")
      assert %{state: :publishing, step: :waiting} = Publishing.status(site(c), c.production)
    end

    test "an old panel's Publish this build after another environment was deployed starts nothing", c do
      {:ok, ready} = Publishing.publish(c.site, c.production, c.user, deploy: false)
      {:ok, _staging} = Builds.request_build(c.site, c.staging, creator_id: c.user.id, auto_deploy: true)

      assert {:error, :not_publishing_environment} =
               Publishing.publish_build(c.site, c.production, ready.id, c.user)

      assert Builds.get_build(ready.id).status == :ready
    end

    test "a deploy from the button stops, without touching the target, when a later build went live", c do
      {:ok, older} = Publishing.publish(c.site, c.production, c.user, deploy: false)
      manual(fn -> {:ok, _job} = Publishing.publish_build(c.site, c.production, older.id, c.user) end)
      [job] = jobs("Brando.Worker.SSGDeploy")

      # Deployed from the Publishing screen meanwhile
      {:ok, newer} = Builds.request_build(c.site, c.production, creator_id: c.user.id)
      {:ok, _deployed} = Deploy.deploy(Builds.get_build(newer.id), creator_id: c.user.id)

      assert {:cancel, :superseded} = perform(SSGDeploy, job)
      assert %Build{status: :ready, deploy_failed_at: nil} = Builds.get_build(older.id)
      assert site(c).published_build == newer.version
    end
  end

  describe "a worker that stopped" do
    test "before it wrote ready, with no job left: failed, and a new Publish builds again", c do
      manual(fn -> {:ok, _build} = Publishing.publish(c.site, c.production, c.user) end)
      [job] = jobs("Brando.Worker.SSGBuild")
      [build] = Builds.list_builds(c.site)
      {:ok, _building} = Builds.update(build, %{status: :building, started_at: DateTime.utc_now()})
      set_job_state(job, "discarded")

      assert %{state: :failed, failed: :build} = Publishing.status(site(c), c.production)
      assert {:ok, again} = Publishing.publish(c.site, c.production, c.user)
      assert Builds.get_build(again.id).status == :deployed
    end

    test "left executing past its timeout, as after a restart: failed, and a new Publish builds again", c do
      manual(fn -> {:ok, _build} = Publishing.publish(c.site, c.production, c.user) end)
      [job] = jobs("Brando.Worker.SSGBuild")
      [build] = Builds.list_builds(c.site)
      {:ok, _building} = Builds.update(build, %{status: :building, started_at: DateTime.utc_now()})
      set_job_state(job, "executing", DateTime.add(DateTime.utc_now(), -SSGBuild.timeout(job) - 1000, :millisecond))

      assert %{state: :failed, failed: :build} = Publishing.status(site(c), c.production)
      assert {:ok, again} = Publishing.publish(c.site, c.production, c.user)
      assert Builds.get_build(again.id).status == :deployed
    end

    test "a deploy job left executing past its timeout no longer reads as publishing", c do
      {:ok, ready} = Publishing.publish(c.site, c.production, c.user, deploy: false)
      manual(fn -> {:ok, _job} = Publishing.publish_build(c.site, c.production, ready.id, c.user) end)
      [job] = jobs("Brando.Worker.SSGDeploy")
      set_job_state(job, "executing", DateTime.add(DateTime.utc_now(), -SSGDeploy.timeout(job) - 1000, :millisecond))

      # Neither publishing nor ready: the deploy it owes has no job that can run
      refute match?(%{state: :publishing}, Publishing.status(site(c), c.production))
    end

    test "after it wrote ready: its retry deploys what the build owes", c do
      manual(fn -> {:ok, _build} = Publishing.publish(c.site, c.production, c.user) end)
      [job] = jobs("Brando.Worker.SSGBuild")
      [build] = Builds.list_builds(c.site)
      File.mkdir_p!(build.build_path)
      {:ok, _ready} = Builds.update(build, %{status: :ready, started_at: DateTime.utc_now()})
      set_job_state(job, "retryable")

      assert %{state: :publishing, step: :waiting} = Publishing.status(site(c), c.production)
      assert :ok = perform(SSGBuild, job)
      assert Builds.get_build(build.id).status == :deployed
    end

    test "after it wrote ready, given up by Oban: failed, told once, and Try again deploys the build", c do
      manual(fn -> {:ok, _build} = Publishing.publish(c.site, c.production, c.user) end)
      [job] = jobs("Brando.Worker.SSGBuild")
      [build] = Builds.list_builds(c.site)
      File.mkdir_p!(build.build_path)
      {:ok, _ready} = Builds.update(build, %{status: :ready, started_at: DateTime.utc_now()})
      set_job_state(job, "discarded")

      assert %{state: :failed, failed: :deploy} = Publishing.status(site(c), c.production)
      :ok = Publishing.given_up(job)
      at = Builds.get_build(build.id).deploy_failed_at
      :ok = Publishing.given_up(job)
      assert Builds.get_build(build.id).deploy_failed_at == at

      assert {:ok, %Oban.Job{}} = Publishing.retry(c.site, c.production, c.user)
      assert Builds.get_build(build.id).status == :deployed
    end

    test "a build job given up while building is recorded as failed once", c do
      manual(fn -> {:ok, _build} = Publishing.publish(c.site, c.production, c.user) end)
      [job] = jobs("Brando.Worker.SSGBuild")
      [build] = Builds.list_builds(c.site)
      {:ok, _building} = Builds.update(build, %{status: :building})

      :ok = Publishing.given_up(job)
      failed = Builds.get_build(build.id)
      assert failed.status == :failed
      assert failed.build_log =~ "its job was given up"

      :ok = Publishing.given_up(job)
      assert Builds.get_build(build.id).build_log == failed.build_log
    end
  end

  describe "notifications" do
    setup c do
      put_test_env(Brando.Notifications, failed_jobs: true)
      put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})
      receiver = WebhookReceiver.start()

      route = fn environment ->
        Tenant.with_prefix(Tenant.prefix(c.site, environment), fn ->
          {:ok, route} =
            Routing.create_route(
              %{
                "name" => "Desk #{environment.key}",
                "kind" => "slack",
                "events" => ["failed_job"],
                "url" => WebhookReceiver.url(receiver, "/services/T0/B0/#{environment.key}")
              },
              c.user
            )

          route
        end)
      end

      %{production_route: route.(c.production), staging_route: route.(c.staging)}
    end

    defp deliveries(c, environment, route) do
      Tenant.with_prefix(Tenant.prefix(c.site, environment), fn -> Routing.list_deliveries(route) end)
    end

    test "each failed build goes to its environment's routes once, also within the interval", c do
      put_test_env(:ssg_builder, FailingBuilder)

      manual(fn ->
        {:ok, first} = Publishing.publish(c.site, c.production, c.user)
        {:error, _reason} = perform(SSGBuild, hd(jobs("Brando.Worker.SSGBuild")))
        # Oban gives the job up after the worker recorded the failure: told once
        :ok = Publishing.given_up(hd(jobs("Brando.Worker.SSGBuild")))
        assert Builds.get_build(first.id).status == :failed

        {:ok, _second} = Publishing.retry(c.site, c.production, c.user)
        {:error, _reason} = perform(SSGBuild, Enum.max_by(jobs("Brando.Worker.SSGBuild"), & &1.id))
      end)

      deliveries = deliveries(c, c.production, c.production_route)
      assert length(deliveries) == 2

      assert Enum.all?(deliveries, fn delivery ->
               match?(%{"build" => %{"kind" => "build", "admin_url" => "http" <> _}}, delivery.notification)
             end)

      assert deliveries(c, c.staging, c.staging_route) == []
    end

    test "a deploy given up is told to the routes; nothing is told with failed jobs off", c do
      put_test_env(Brando.Sites.DeployConfig, local_delivery: false)

      manual(fn ->
        {:ok, build} = Publishing.publish(c.site, c.production, c.user)
        {:cancel, {:deploy_failed, _reason}} = perform(SSGBuild, hd(jobs("Brando.Worker.SSGBuild")))
        assert %Build{deploy_failed_at: %DateTime{}} = Builds.get_build(build.id)
      end)

      assert [%{notification: %{"build" => %{"kind" => "deploy"}}}] =
               deliveries(c, c.production, c.production_route)

      put_test_env(Brando.Notifications, failed_jobs: false)

      manual(fn ->
        {:ok, %Oban.Job{}} = Publishing.retry(c.site, c.production, c.user)
        {:cancel, :local_delivery_disabled} = perform(SSGDeploy, hd(jobs("Brando.Worker.SSGDeploy")))
      end)

      assert %{state: :failed, failed: :deploy} = Publishing.status(site(c), c.production)
      assert [_one] = deliveries(c, c.production, c.production_route)
    end
  end
end
