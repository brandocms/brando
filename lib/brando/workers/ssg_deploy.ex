defmodule Brando.Worker.SSGDeploy do
  @moduledoc """
  Deploys or rolls back an existing static artifact on the serial SSG queue.

  The admin queues it with `BrandoAdmin.Work.track/4`, so the job reports
  its outcome to whoever asked, on the build's key
  (`Brando.Worker.SSGBuild.work_key/1`).

  `"redeploy"` with a `"site_id"` deploys again whichever build is the
  site's deployed one when the job runs, so a newer deploy queued before it
  stays live (`Brando.SSG.TargetReview.delete_unknown/4`), and nothing when
  another build became the deployed one while it waited for the deploy lock.

  `"unless_superseded" => true` (the Publish button, `Brando.SSG.Publishing`)
  deploys nothing when a build that started later is the deployed one by the
  time the job runs.

  A deploy that gives up (refused, or failed on its last attempt) records it
  on the build (`deploy_failed_at`, cleared when the next deploy of it
  starts) and tells the environment's `failed_job` routes
  (`Brando.SSG.Publishing.deploy_failed/1`).
  """

  use Oban.Worker, queue: :ssg_builds, max_attempts: 3
  use Gettext, backend: Brando.Gettext

  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.SSG.Publishing
  alias Brando.SSG.SSH
  alias Brando.SSG.TargetReview

  @doc "What a deploy or rollback job of `version` reports (`BrandoAdmin.Work.track/4`)."
  @spec work_messages(String.t(), String.t()) :: keyword()
  def work_messages("deploy", version) do
    [
      queued: gettext("Deploy of %{version} is queued", version: version),
      running: gettext("Deploying %{version}", version: version),
      done: gettext("%{version} is deployed", version: version),
      failed: gettext("Could not deploy %{version}", version: version)
    ]
  end

  def work_messages("rollback", version) do
    [
      queued: gettext("Rollback to %{version} is queued", version: version),
      running: gettext("Rolling back to %{version}", version: version),
      done: gettext("Rolled back to %{version}", version: version),
      failed: gettext("Could not roll back to %{version}", version: version)
    ]
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"build_id" => build_id, "action" => action} = args} = job)
      when action in ["deploy", "rollback"] do
    case Builds.get_build(build_id) do
      %Build{} = build ->
        build = Publishing.deploy_started(build)
        action |> run(build, args) |> outcome(build, job) |> given_up(build, job)

      nil ->
        {:cancel, :build_not_found}
    end
  end

  def perform(%Oban.Job{args: %{"site_id" => site_id, "action" => "redeploy"} = args} = job) do
    case Builds.deployed_build(site_id) do
      %Build{} = build ->
        build = Publishing.deploy_started(build)
        "redeploy" |> run(build, args) |> outcome(build, job) |> given_up(build, job)

      nil ->
        {:cancel, :no_deployed_build}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp run("deploy", build, args),
    do: Deploy.deploy(build, creator_id: args["creator_id"], unless_superseded: args["unless_superseded"] == true)

  defp run("rollback", build, args), do: Deploy.rollback(build.site, build, creator_id: args["creator_id"])

  defp run("redeploy", build, args),
    do: Deploy.deploy(build, creator_id: args["creator_id"], only_if_deployed: true)

  # Neither is a failure: the site online is newer than this build
  defp given_up({:cancel, reason} = result, _build, _job) when reason in [:build_no_longer_deployed, :superseded],
    do: result

  defp given_up({:cancel, _reason} = result, build, _job), do: deploy_failed(result, build)

  defp given_up({:error, _reason} = result, build, %Oban.Job{attempt: attempt, max_attempts: max})
       when attempt >= max,
       do: deploy_failed(result, build)

  defp given_up(result, _build, _job), do: result

  defp deploy_failed(result, build) do
    Publishing.deploy_failed(build)
    result
  end

  defp outcome({:ok, _deployed}, _build, _job), do: :ok

  # The build's target stays what it was: retrying cannot help
  defp outcome({:error, :invalid_deploy_target}, build, _job) do
    Builds.append_log(build, refused_target_log())

    {:cancel, :invalid_deploy_target}
  end

  # Someone put a build that started later online meanwhile (`Brando.SSG.Publishing`)
  defp outcome({:error, :superseded}, build, _job) do
    Builds.append_log(build, "Deployment skipped: a build that started later was deployed meanwhile, and stays live.")
    {:cancel, :superseded}
  end

  # The newer deploy deleted what was confirmed, or the next one does
  defp outcome({:error, :build_no_longer_deployed} = error, build, _job) do
    Builds.append_log(
      build,
      "Deployment skipped: another build was deployed while this one waited, and stays live. The next deploy deletes the files confirmed for deletion."
    )

    {:cancel, elem(error, 1)}
  end

  # DNS may answer on the next attempt
  defp outcome({:error, :deploy_target_lookup_failed} = error, build, job) do
    next =
      if job.attempt < job.max_attempts,
        do: "It is tried again.",
        else: "That was the last attempt."

    Builds.append_log(build, "Deployment failed: the target's host could not be looked up. #{next}")
    error
  end

  # The site's settings decide: retrying cannot help either
  defp outcome({:error, reason}, build, _job)
       when reason in [
              :local_delivery_not_configured,
              :local_delivery_disabled,
              :build_made_for_another_delivery,
              :site_not_static
            ] do
    Builds.append_log(build, "Deployment refused: #{local_refusal(reason)}")
    {:cancel, reason}
  end

  defp outcome({:error, {:rsync_failed, _status, _output} = reason}, build, _job) do
    Builds.append_log(build, "Deployment failed: #{SSH.failure_message(reason)}")
    {:error, reason}
  end

  defp outcome({:error, reason}, build, _job) do
    # A step on the Publishing screen comes first (`Brando.SSG.SSH`,
    # `Brando.SSG.TargetReview`)
    case SSH.refusal_message(reason) || TargetReview.refusal_message(reason) do
      nil ->
        {:error, reason}

      message ->
        Builds.append_log(build, "Deployment refused: #{message}")
        {:cancel, reason}
    end
  end

  defp local_refusal(:local_delivery_not_configured),
    do: "the site is no longer served by this installation. Make a build with its current settings."

  defp local_refusal(:build_made_for_another_delivery),
    do: "the build was made for another delivery than the site now uses, and must be built again."

  defp local_refusal(:site_not_static),
    do: "the site's delivery is no longer static, so nothing was copied or published."

  defp local_refusal(:local_delivery_disabled),
    do: "this installation turns off serving builds itself (local_delivery: false in the config)."

  # Only several sites have a Sites screen to set a site's allowed targets
  defp refused_target_log do
    if Brando.Tenant.mode() == :multi,
      do:
        "Deployment refused: its target has the wrong form or is not one this site may use. A superuser sets the site's allowed deploy targets under Sites; the config's rsync_targets or s3_targets may list them too.",
      else:
        "Deployment refused: its target has the wrong form or is not one this installation allows. Check rsync_targets or s3_targets in the config."
  end
end
