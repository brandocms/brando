defmodule Brando.SSG.Publishing do
  @moduledoc """
  Publishing a static site in one step, as the Publish button in the admin's
  navigation does: the state of the environment the site publishes from
  (`status/2`), and the actions on it (`publish/4`, `publish_build/4`,
  `retry/3`). Each action decides from the database what it applies to when
  it runs, under the lock that queues a site's builds, and authorizes its
  user then: two people pressing at once start one build or one deploy.

  ## The environment the site publishes from

  A site has one deployed build, whatever environment it was built from. It
  publishes from that build's environment, or from its live environment when
  nothing is deployed or the build's environment is gone. Publishing another
  environment stays on the Publishing screen.

  ## States

  The first that applies, read from the database, so every admin and node
  sees the same:

    * `:publishing` — a build of the environment has a job that can still
      run (`Oban` states available, retryable, scheduled and due, or
      executing within its worker's timeout), for building it or for
      deploying it. A job left executing longer lost its node (a restart):
      Oban's Lifeline rescues it only after an hour, if the application
      runs it at all. `:step` says `:waiting` (the
      job waits for the serial queue), `:building` or `:deploying`;
    * `:failed` — the environment's latest attempt failed: its build
      (`failed: :build`; also a build left queued or building with no job to
      finish it), or its deploy (`failed: :deploy`; given up, or owed by a
      ready build with no job left to do it);
    * `:ready` — the latest attempt is ready, started after the deployed
      build, was built without a deploy, and its files are still there;
    * `:changes` — nothing is deployed, or the environment's content changed
      after the deployed build started (`Brando.SSG.ContentChanges`);
    * `:published` — otherwise.

  The latest attempt is the build that started last (`started_at`; for one
  not started yet, when it was due), not the highest number: a build
  scheduled for later is no attempt until it is due.

  ## Failures

  A failed build, and a deploy given up, are recorded on the build and told
  once to the routes of its environment that send `failed_job`
  (`Brando.Notifications.Routing.publish_failed/3`): from the workers, and
  from `given_up/1` for a job Oban gives up without the worker saying so.
  """

  import Ecto.Query, only: [dynamic: 2, from: 2]

  alias Brando.Environments.Environment
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.ContentChanges
  alias Brando.Tenant
  alias Brando.Tenant.Lock
  alias Brando.Worker.SSGBuild
  alias Brando.Worker.SSGDeploy

  require Logger

  @public_opts [prefix: "public"]
  @workers ["Brando.Worker.SSGBuild", "Brando.Worker.SSGDeploy"]
  @runnable ["available", "retryable"]

  @type status ::
          %{state: :publishing, step: :waiting | :building | :deploying, build: Build.t(), deployed: Build.t() | nil}
          | %{state: :failed, failed: :build | :deploy, build: Build.t(), deployed: Build.t() | nil}
          | %{state: :ready, build: Build.t(), deployed: Build.t() | nil}
          | %{state: :changes | :published, deployed: Build.t() | nil}

  @doc """
  The state of `environment`, when it is the one `site` publishes from (see
  the module doc), or `:elsewhere`. At most five reads.
  """
  @spec status(Site.t(), Environment.t()) :: status() | :elsewhere
  def status(%Site{} = site, %Environment{} = environment) do
    deployed = deployed_build(site)

    if publishing_environment_id(site, deployed) == environment.id do
      deployed = if deployed && deployed.environment_id == environment.id, do: deployed

      running(environment, deployed) || latest(environment, deployed) || published(site, environment, deployed)
    else
      :elsewhere
    end
  end

  @doc """
  Builds `environment` of `site` for `user` and deploys the build once it is
  ready, whatever the site's auto-deploy setting. With `deploy: false`
  (Preview first) it only builds. Starts nothing while the environment is
  publishing (`{:error, :publishing}`) or when it is no longer the one the
  site publishes from.
  """
  @spec publish(Site.t(), Environment.t(), term(), keyword()) :: {:ok, Build.t()} | {:error, term()}
  def publish(%Site{} = site, %Environment{} = environment, user, opts \\ []) do
    deploy? = Keyword.get(opts, :deploy, true)
    actions = if deploy?, do: [:build, :deploy], else: [:build]

    locked(site, environment, user, actions, fn site, environment ->
      case status(site, environment) do
        :elsewhere -> {:error, :not_publishing_environment}
        %{state: :publishing} -> {:error, :publishing}
        _status -> build(site, environment, user, deploy?)
      end
    end)
  end

  @doc """
  Deploys the build `build_id` for `user`, when it is still what the button
  offers: the ready build of the environment the site publishes from
  (`status/2`'s `:ready`). Otherwise `{:error, :stale}`, and nothing starts.
  The deploy stops without touching the target when a build that started
  later is the deployed one by the time it runs.
  """
  @spec publish_build(Site.t(), Environment.t(), pos_integer(), term()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def publish_build(%Site{} = site, %Environment{} = environment, build_id, user) when is_integer(build_id) do
    locked(site, environment, user, [:build, :deploy], fn site, environment ->
      case status(site, environment) do
        %{state: :ready, build: %Build{id: ^build_id} = build} -> deploy(build, user)
        :elsewhere -> {:error, :not_publishing_environment}
        _status -> {:error, :stale}
      end
    end)
  end

  @doc """
  Tries a failed attempt again for `user`: after a failed deploy it deploys
  the same build while its files are there, after a failed build it builds
  and deploys again. `{:error, :stale}` when the environment is no longer
  in the failed state.
  """
  @spec retry(Site.t(), Environment.t(), term()) :: {:ok, Build.t() | Oban.Job.t()} | {:error, term()}
  def retry(%Site{} = site, %Environment{} = environment, user) do
    locked(site, environment, user, [:build, :deploy], fn site, environment ->
      try_again(site, environment, user, status(site, environment))
    end)
  end

  defp try_again(site, environment, user, %{state: :failed, failed: :deploy, build: build}),
    do: if(files?(build), do: deploy(build, user), else: build(site, environment, user, true))

  defp try_again(site, environment, user, %{state: :failed, failed: :build}), do: build(site, environment, user, true)
  defp try_again(_site, _environment, _user, :elsewhere), do: {:error, :not_publishing_environment}
  defp try_again(_site, _environment, _user, _status), do: {:error, :stale}

  @doc "Whether a ready build's files are still there: retention may have pruned them."
  @spec files?(Build.t()) :: boolean()
  def files?(%Build{pruned_at: nil, build_path: path}) when is_binary(path), do: File.dir?(path)
  def files?(%Build{}), do: false

  # The site and environment as stored, and the user's grants, at the moment
  # of the click; the status is read and the job queued holding the lock
  # `Brando.SSG.Builds.request_build/3` takes
  defp locked(site, environment, user, actions, fun) do
    with %Site{} = site <- Brando.Tenant.Registry.get_site(site.id),
         :ok <- authorize(user, site, actions),
         :ok <- publishable(site),
         %Environment{} = environment <- Enum.find(site.environments, &(&1.id == environment.id)) do
      Lock.with("ssg-build:#{site.id}", fn -> fun.(site, environment) end)
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  # As the Publishing screen asks in legacy mode (`Brando.SSG.Builds.can_manage?/2`)
  defp authorize(user, site, actions) do
    allowed? =
      if Brando.Authorization.enabled?() do
        scope = Brando.Authorization.Scope.site(user, site)
        Enum.all?(actions, &Brando.Authorization.can?(scope, &1, :publishing))
      else
        Builds.can_manage?(user, site)
      end

    if allowed?, do: :ok, else: {:error, :forbidden}
  end

  defp publishable(%Site{status: :active, delivery_mode: :static} = site) do
    if Builds.deploy_target?(site), do: :ok, else: {:error, :no_deploy_target}
  end

  defp publishable(%Site{}), do: {:error, :not_publishable}

  defp build(site, environment, user, deploy?),
    do: Builds.request_build(site, environment, creator_id: user.id, auto_deploy: deploy?)

  # It waits behind any build on the serial queue, and reports to `user` as
  # a deploy from the Publishing screen does
  defp deploy(build, user) do
    %{"build_id" => build.id, "action" => "deploy", "creator_id" => user.id, "unless_superseded" => true}
    |> SSGDeploy.new(tags: ["ssg-deploy", "site:#{build.site_id}"])
    |> BrandoAdmin.Work.track(
      user,
      SSGBuild.work_key(build.id),
      [global: true, timeout: to_timeout(hour: 1)] ++ SSGDeploy.work_messages("deploy", build.version)
    )
    |> Oban.insert()
  end

  ## Status

  defp deployed_build(site) do
    from(build in Build, where: build.site_id == ^site.id and build.status == :deployed, limit: 1)
    |> Repo.one(@public_opts)
  end

  defp publishing_environment_id(%Site{environments: environments}, deployed) do
    by_build = deployed && Enum.find(environments, &(&1.id == deployed.environment_id))
    environment = by_build || Enum.find(environments, & &1.live)
    environment && environment.id
  end

  # A build of the environment that a job can still build or deploy: its
  # build job while it is queued, building or owes its deploy, or a deploy
  # job of a ready build. A rollback or a redeploy of an older build is not
  # one.
  defp running(environment, deployed) do
    from(build in Build,
      join: job in Oban.Job,
      on: ^runnable_job(),
      where: ^owes_work(environment),
      order_by: [desc: job.id],
      limit: 1,
      select: {build, job.state}
    )
    |> Repo.one(@public_opts)
    |> case do
      nil -> nil
      {build, job_state} -> %{state: :publishing, step: step(build, job_state), build: build, deployed: deployed}
    end
  end

  # A job of the build that can still run: waiting, to be retried, scheduled
  # for a time that has come, or running within its worker's timeout (as
  # `Brando.Images.SizeRun.remaining/1` counts)
  defp runnable_job do
    now = DateTime.utc_now()
    build_since = DateTime.add(now, -SSGBuild.timeout(%Oban.Job{}), :millisecond)
    deploy_since = DateTime.add(now, -SSGDeploy.timeout(%Oban.Job{}), :millisecond)

    dynamic(
      [build, job],
      job.queue == "ssg_builds" and job.worker in @workers and
        fragment("(?->>'build_id')::bigint", job.args) == build.id and
        (job.state in @runnable or (job.state == "scheduled" and job.scheduled_at <= ^now) or
           (job.state == "executing" and
              ((job.worker == "Brando.Worker.SSGBuild" and job.attempted_at > ^build_since) or
                 (job.worker == "Brando.Worker.SSGDeploy" and job.attempted_at > ^deploy_since))))
    )
  end

  # Of the environment: queued or building, or ready with a deploy job or an
  # automatic deploy owed
  defp owes_work(environment) do
    owed_deploy = dynamic([build, _job], build.auto_deploy and is_nil(build.deploy_failed_at))

    dynamic(
      [build, job],
      build.environment_id == ^environment.id and
        (build.status in [:queued, :building] or
           (build.status == :ready and (job.worker == "Brando.Worker.SSGDeploy" or ^owed_deploy)))
    )
  end

  defp step(_build, job_state) when job_state != "executing", do: :waiting
  defp step(%Build{status: :ready}, _job_state), do: :deploying
  defp step(%Build{}, _job_state), do: :building

  # The latest attempt, when it failed or is ready to deploy. A build left
  # queued or building, or owing its deploy, has no job left: `running/2`
  # found none.
  defp latest(environment, deployed) do
    now = DateTime.utc_now()

    latest =
      from(build in Build,
        where:
          build.environment_id == ^environment.id and
            not (build.status == :queued and not is_nil(build.scheduled_at) and build.scheduled_at > ^now),
        order_by: [
          desc: coalesce(build.started_at, coalesce(build.scheduled_at, build.inserted_at)),
          desc: build.id
        ],
        limit: 1
      )
      |> Repo.one(@public_opts)

    attempt(latest, deployed)
  end

  defp attempt(%Build{status: status} = build, deployed) when status in [:failed, :queued, :building],
    do: %{state: :failed, failed: :build, build: build, deployed: deployed}

  # Given up, or owed with no job left to do it
  defp attempt(%Build{status: :ready} = build, deployed)
       when not is_nil(build.deploy_failed_at) or build.auto_deploy == true,
       do: %{state: :failed, failed: :deploy, build: build, deployed: deployed}

  defp attempt(%Build{status: :ready} = build, deployed) do
    if started_after?(build, deployed) and files?(build), do: %{state: :ready, build: build, deployed: deployed}
  end

  defp attempt(_deployed_or_none, _deployed), do: nil

  defp started_after?(_build, nil), do: true
  defp started_after?(build, deployed), do: DateTime.after?(started(build), started(deployed))

  defp started(build), do: build.started_at || build.inserted_at

  defp published(_site, _environment, nil), do: %{state: :changes, deployed: nil}

  defp published(site, environment, deployed) do
    if ContentChanges.changed_since?(%{deployed | site: site, environment: environment}),
      do: %{state: :changes, deployed: deployed},
      else: %{state: :published, deployed: deployed}
  end

  ## Failures

  @doc """
  A deploy of `build` starts: a failure recorded for an earlier one is
  cleared. Returns the build.
  """
  @spec deploy_started(Build.t()) :: Build.t()
  def deploy_started(%Build{deploy_failed_at: nil} = build), do: build

  def deploy_started(%Build{} = build) do
    case Builds.update(build, %{deploy_failed_at: nil}) do
      {:ok, build} -> build
      {:error, _changeset} -> build
    end
  end

  @doc """
  Records that a deploy of `build` was given up, unless that is recorded
  already, and tells the environment's `failed_job` routes.
  """
  @spec deploy_failed(Build.t()) :: :ok
  def deploy_failed(%Build{id: id}) do
    now = DateTime.utc_now()

    {count, _rows} =
      from(build in Build, where: build.id == ^id and is_nil(build.deploy_failed_at))
      |> Repo.update_all([set: [deploy_failed_at: now, updated_at: now]], @public_opts)

    if count == 1, do: told(id, :deploy)
    :ok
  end

  @doc """
  For a static build or deploy job Oban gave up (it used every attempt, or
  was killed on its last): records what the worker could not, a build left
  queued or building as failed, a deploy owed or started as given up, and
  tells the environment's `failed_job` routes. What the worker recorded
  already is not recorded or told again.
  """
  @spec given_up(Oban.Job.t()) :: :ok
  def given_up(%Oban.Job{worker: "Brando.Worker.SSGBuild", args: %{"build_id" => id}}) do
    case Builds.get_build(id) do
      %Build{status: status} = build when status in [:queued, :building] -> build_given_up(build)
      %Build{status: :ready, auto_deploy: true, deploy_failed_at: nil} = build -> deploy_failed(build)
      _done -> :ok
    end
  end

  def given_up(%Oban.Job{worker: "Brando.Worker.SSGDeploy", args: %{"build_id" => id}}) do
    case Builds.get_build(id) do
      %Build{} = build -> deploy_failed(build)
      nil -> :ok
    end
  end

  def given_up(%Oban.Job{}), do: :ok

  defp build_given_up(%Build{id: id} = build) do
    now = DateTime.utc_now()
    line = "[#{Calendar.strftime(now, "%Y-%m-%d %H:%M:%S UTC")}] Build failed: its job was given up\n"

    {count, _rows} =
      from(build in Build, where: build.id == ^id and build.status in [:queued, :building])
      |> Repo.update_all(
        [set: [status: :failed, built_at: now, updated_at: now, build_log: build.build_log <> line]],
        @public_opts
      )

    if count == 1, do: told(id, :build)
    :ok
  end

  defp told(id, kind) do
    case Builds.get_build(id) do
      %Build{} = build ->
        Builds.broadcast(build)
        notify_failed(build, kind)

      nil ->
        :ok
    end
  end

  @doc """
  Tells the `failed_job` routes of `build`'s environment that the build
  failed (`:build`) or its deploy was given up (`:deploy`). Nothing for a
  build whose environment is gone. Never raises.
  """
  @spec notify_failed(Build.t(), :build | :deploy) :: :ok
  def notify_failed(%Build{} = build, kind) do
    build = Repo.preload(build, [:site, :environment], @public_opts)
    at = if kind == :build, do: build.built_at, else: build.deploy_failed_at

    case build do
      %Build{site: %Site{} = site, environment: %Environment{} = environment} when not is_nil(at) ->
        notify = fn -> Brando.Notifications.Routing.publish_failed(build, kind, at) end
        if Tenant.mode() == :none, do: notify.(), else: Tenant.with_prefix(Tenant.prefix(site, environment), notify)
        :ok

      _no_environment ->
        :ok
    end
  rescue
    error ->
      Logger.warning("[Brando.SSG.Publishing] Could not notify a failed build: " <> Exception.message(error))
      :ok
  end
end
