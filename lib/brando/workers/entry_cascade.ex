defmodule Brando.Worker.EntryCascade do
  @moduledoc """
  Background worker that performs merged datasource + identifier cascade
  discovery and enqueues EntryRenderer jobs.

  Moves the expensive cascade queries (~13 DB queries + recursive CTE + Oban inserts)
  out of the synchronous save path.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:schema, :entry_id], period: 5, states: [:available, :scheduled]]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    schema = Module.concat([args["schema"]])
    entry_id = args["entry_id"]
    identifier_id = args["identifier_id"]

    entry = if entry_id, do: Brando.Repo.get(schema, entry_id)

    Logger.info("==> [OBAN] Running cascade for #{inspect(schema)} ##{entry_id}")

    datasource_block_ids =
      if Brando.Datasource.datasource?(schema) do
        Brando.Content.Blocks.list_block_ids_using_datamodule(schema)
      else
        []
      end

    identifier_block_ids =
      if identifier_id do
        Brando.Content.Blocks.list_block_ids_using_identifier(identifier_id)
      else
        []
      end

    # Merge, deduplicate, then run through shared pipeline once.
    # reject_blocks_belonging_to_entry internally calls
    # list_root_block_ids_by_source and list_entry_ids_for_root_blocks_by_source,
    # returning a %{schema => [entry_ids]} map ready for enqueue_entry_map_for_render.
    (datasource_block_ids ++ identifier_block_ids)
    |> Enum.uniq()
    |> Brando.Content.Blocks.reject_blocks_belonging_to_entry(entry)
    |> Brando.Content.Blocks.enqueue_entry_map_for_render()

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
