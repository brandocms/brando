defmodule Brando.Worker.SearchIndexRebuild do
  @moduledoc """
  Rebuilds the search index of one site and environment (`Brando.Search.rebuild/1`),
  queued from Configuration → Utilities.

  Progress and the result are broadcast on `Brando.Search.topic/0` as
  `{:search_index, %{state: :running | :done | :failed, done: n, total: n}}`.
  """
  use Oban.Worker,
    queue: :search_index,
    max_attempts: 1,
    unique: [period: :infinity, keys: [:tenant_prefix], states: [:available, :scheduled, :executing, :retryable]]

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    TenantJob.run(job, fn ->
      topic = Brando.Search.topic()

      try do
        case Brando.Search.rebuild(&broadcast(topic, :running, &1, &2)) do
          {:ok, count} ->
            broadcast(topic, :done, count, count)
            :ok

          {:error, reason} ->
            broadcast(topic, :failed, 0, 0)
            {:cancel, reason}
        end
      rescue
        error ->
          broadcast(topic, :failed, 0, 0)
          reraise error, __STACKTRACE__
      end
    end)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp broadcast(topic, state, done, total) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {:search_index, %{state: state, done: done, total: total}})
  end
end
