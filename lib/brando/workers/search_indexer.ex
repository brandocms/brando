defmodule Brando.Worker.SearchIndexer do
  @moduledoc """
  Writes one entry's search document, or removes it (`Brando.Search`).

  Queued by `Brando.Search.handle_event/1` for every content event of a
  searchable entry. The job reads the entry when it runs, so it does not
  matter which event queued it or how often: while one job for the entry
  waits, no other is queued.
  """
  use Oban.Worker,
    queue: :search_index,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:schema, :entry_id, :tenant_prefix], states: [:available, :scheduled, :retryable]]

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"schema" => schema_name, "entry_id" => id}} = job) when is_integer(id) do
    TenantJob.run(job, fn ->
      case schema(schema_name) do
        nil -> {:cancel, :unknown_schema}
        schema -> result(Brando.Search.index_entry(schema, id))
      end
    end)
  end

  def perform(_job), do: {:cancel, :invalid_args}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(1)

  defp result({:error, :no_table}), do: {:cancel, :no_table}
  defp result(other), do: other

  defp schema(name) when is_binary(name) do
    module = String.to_existing_atom(name)
    if Code.ensure_loaded?(module), do: module
  rescue
    ArgumentError -> nil
  end
end
