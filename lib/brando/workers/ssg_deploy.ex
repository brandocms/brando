defmodule Brando.Worker.SSGDeploy do
  @moduledoc "Deploys or rolls back an existing static artifact on the serial SSG queue."

  use Oban.Worker, queue: :ssg_builds, max_attempts: 3

  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"build_id" => build_id, "action" => action}})
      when action in ["deploy", "rollback"] do
    with %Build{} = build <- Builds.get_build(build_id),
         {:ok, deployed} <- run(action, build) do
      notify_creator(deployed, action)
      :ok
    else
      nil -> {:cancel, :build_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp run("deploy", build), do: Deploy.deploy(build)
  defp run("rollback", build), do: Deploy.rollback(build.site, build)

  defp notify_creator(%Build{creator: nil}, _action), do: :ok

  defp notify_creator(%Build{creator: creator} = build, action) do
    BrandoAdmin.Toast.send_to(
      creator,
      "Static #{action} completed with #{build.version}",
      %{level: :success, type: :notification}
    )
  rescue
    _endpoint_unavailable -> :ok
  end
end
