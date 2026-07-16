defmodule Brando.Content.RenderQueue do
  @moduledoc """
  Enqueues entry-rendering jobs at the content pipeline's asynchronous boundary.

  The worker is resolved at runtime so producers do not depend on the worker's
  block-rendering implementation.
  """

  @entry_renderer Module.concat(["Brando", "Worker", "EntryRenderer"])

  @doc """
  Enqueues every entry in a schema-to-entry-ids map.
  """
  @spec enqueue_map(%{optional(module() | String.t()) => [integer()]}) :: [term()]
  def enqueue_map(entries_by_schema) do
    for {schema, entry_ids} <- entries_by_schema, entry_id <- entry_ids do
      enqueue(%{schema: schema, entry_id: entry_id})
    end
  end

  @doc """
  Enqueues all `entry_ids` for `schema`.
  """
  @spec enqueue_many(module() | String.t(), [integer()]) :: [term()]
  def enqueue_many(schema, entry_ids) do
    Enum.map(entry_ids, &enqueue(%{schema: schema, entry_id: &1}))
  end

  @doc """
  Enqueues one entry-rendering job.
  """
  @spec enqueue(map()) :: term()
  def enqueue(args) do
    worker = @entry_renderer

    args
    |> worker.new(replace_args: true, tags: [:render_entry])
    |> Oban.insert()
  end
end
