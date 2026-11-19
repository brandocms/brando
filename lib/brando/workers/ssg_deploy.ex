defmodule Brando.Worker.SSGDeploy do
  @moduledoc """
  Deploys or rolls back an existing static artifact on the serial SSG queue.

  The admin queues it with `BrandoAdmin.Work.track/4`, so the job reports
  its outcome to whoever asked, on the build's key
  (`Brando.Worker.SSGBuild.work_key/1`).
  """

  use Oban.Worker, queue: :ssg_builds, max_attempts: 3

  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"build_id" => build_id, "action" => action} = args} = job)
      when action in ["deploy", "rollback"] do
    case Builds.get_build(build_id) do
      %Build{} = build -> action |> run(build, args["creator_id"]) |> outcome(build, job)
      nil -> {:cancel, :build_not_found}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp run("deploy", build, creator_id), do: Deploy.deploy(build, creator_id: creator_id)
  defp run("rollback", build, creator_id), do: Deploy.rollback(build.site, build, creator_id: creator_id)

  defp outcome({:ok, _deployed}, _build, _job), do: :ok

  # The build's target stays what it was: retrying cannot help
  defp outcome({:error, :invalid_deploy_target}, build, _job) do
    Builds.append_log(
      build,
      "Deployment refused: its target has the wrong form or is not one this site may use. A superuser sets the site's allowed deploy targets under Sites; the config's rsync_targets or s3_targets may list them too."
    )

    {:cancel, :invalid_deploy_target}
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
       when reason in [:local_delivery_not_configured, :local_delivery_disabled, :build_made_for_another_delivery] do
    Builds.append_log(build, "Deployment refused: #{local_refusal(reason)}")
    {:cancel, reason}
  end

  defp outcome({:error, reason}, _build, _job), do: {:error, reason}

  defp local_refusal(:local_delivery_not_configured),
    do: "the site is no longer served by this installation. Make a build with its current settings."

  defp local_refusal(:build_made_for_another_delivery),
    do: "the build was made for another delivery than the site now uses, and must be built again."

  defp local_refusal(:local_delivery_disabled),
    do: "this installation turns off serving builds itself (local_delivery: false in the config)."
end
