defmodule Brando.Worker.TranslationSync do
  @moduledoc """
  Computes pending versions for the synchronized targets of a translation
  group after its source was saved. See `Brando.Translations.sync_group/2`.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"group_id" => group_id} = args} = job) do
    TenantJob.run(job, fn ->
      case Brando.Translations.sync_group(group_id, minor: Map.get(args, "minor", false)) do
        {:ok, _} -> :ok
        # The source was deleted since the save; there is nothing to sync from.
        {:error, :source_not_found} -> {:cancel, :source_not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end
end
