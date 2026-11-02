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
  def perform(%Oban.Job{args: %{"build_id" => build_id, "action" => action} = args})
      when action in ["deploy", "rollback"] do
    case Builds.get_build(build_id) do
      %Build{} = build -> action |> run(build, args["creator_id"]) |> outcome(build)
      nil -> {:cancel, :build_not_found}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp run("deploy", build, creator_id), do: Deploy.deploy(build, creator_id: creator_id)
  defp run("rollback", build, creator_id), do: Deploy.rollback(build.site, build, creator_id: creator_id)

  defp outcome({:ok, _deployed}, _build), do: :ok

  # The build's target stays what it was: retrying cannot help
  defp outcome({:error, :invalid_deploy_target}, build) do
    Builds.append_log(
      build,
      "Deployment refused: its target is not one this installation allows. Check rsync_targets or s3_targets in the config."
    )

    {:cancel, :invalid_deploy_target}
  end

  defp outcome({:error, reason}, _build), do: {:error, reason}
end
