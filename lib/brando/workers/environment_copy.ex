defmodule Brando.Worker.EnvironmentCopy do
  @moduledoc """
  Runs a scheduled, archived copy between two named environments, if
  whoever scheduled it still may (`Brando.Environments.scheduler_authorized?/2`);
  otherwise cancelled, which the site's operation log records
  (`Brando.Environments.cancel_unauthorized/3`).
  """

  use Oban.Worker, queue: :environment_operations, max_attempts: 3

  alias Brando.Tenant.Registry

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args:
            %{
              "source_environment_id" => source_id,
              "target_environment_id" => target_id
            } = args
        } = job
      ) do
    with source when not is_nil(source) <- Registry.get_environment(source_id),
         target when not is_nil(target) <- Registry.get_environment(target_id),
         true <-
           Brando.Environments.scheduler_authorized?(args["creator_id"], target.site_id) || {:forbidden, {source, target}},
         {:ok, _result} <-
           Brando.Environments.copy_environment(source, target,
             creator_id: args["creator_id"],
             note: args["note"]
           ) do
      :ok
    else
      nil -> {:cancel, :environment_not_found}
      {:forbidden, environments} -> Brando.Environments.cancel_unauthorized(job, :copy, environments)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.hours(2)
end
