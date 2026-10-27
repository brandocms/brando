defmodule Brando.Worker.EnvironmentSetLive do
  @moduledoc """
  Switches a scheduled environment live after creating an archive, if
  whoever scheduled it still may (`Brando.Environments.scheduler_authorized?/2`);
  otherwise cancelled, as the Environments screen shows
  (`Brando.Environments.cancel_unauthorized/2`).
  """

  use Oban.Worker, queue: :environment_operations, max_attempts: 3

  alias Brando.Tenant.Registry

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"environment_id" => environment_id} = args} = job) do
    with environment when not is_nil(environment) <- Registry.get_environment(environment_id),
         true <- Brando.Environments.scheduler_authorized?(args["creator_id"], environment.site_id) || {:forbidden, environment.site_id},
         {:ok, _live_environment} <-
           Brando.Environments.set_live(environment,
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
