defmodule Brando.Worker.EnvironmentCopy do
  @moduledoc """
  Runs a scheduled, archived copy between two named environments, if
  whoever scheduled it still may (`Brando.Environments.scheduler_authorized?/2`);
  otherwise cancelled, as the Environments screen shows
  (`Brando.Environments.cancel_unauthorized/2`).
  """

  use Oban.Worker, queue: :environment_operations, max_attempts: 3

  alias Brando.Tenant.Registry

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "source_environment_id" => source_id,
            "target_environment_id" => target_id
          } = args
      } = job) do
    with source when not is_nil(source) <- Registry.get_environment(source_id),
         target when not is_nil(target) <- Registry.get_environment(target_id),
         true <- Brando.Environments.scheduler_authorized?(args["creator_id"], target.site_id) || {:forbidden, target.site_id},
         {:ok, _result} <-
           Brando.Environments.copy_environment(source, target,
             creator_id: args["creator_id"],
             note: args["note"]
           ) do
      :ok
    else
      nil -> {:cancel, :environment_not_found}
      {:forbidden, site_id} -> Brando.Environments.cancel_unauthorized(job, site_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.hours(2)
end
