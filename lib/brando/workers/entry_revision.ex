defmodule Brando.Worker.EntryRevision do
  @moduledoc """
  Compatibility worker for revision jobs queued by older releases.

  New mutations capture revisions synchronously because an id-only background
  job cannot recover the exact state of the save that enqueued it.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{
         args: %{"schema" => schema, "entry_id" => entry_id, "user_id" => user_id}
       }) do
    schema = Module.concat([schema])
    Logger.info("==> [OBAN] Creating revision for #{inspect(schema)} ##{entry_id}")

    with %{} = entry <- Brando.Repo.get(schema, entry_id),
         user <- revision_user(user_id),
         {:ok, _revision} <- Brando.Revisions.create_revision(entry, user) do
      :ok
    else
      nil -> {:cancel, :entry_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  defp revision_user(nil), do: :system

  defp revision_user(user_id) do
    case Brando.Users.get_user(user_id) do
      {:ok, user} -> user
      _ -> :system
    end
  end
end
