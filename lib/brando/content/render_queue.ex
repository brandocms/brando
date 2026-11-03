defmodule Brando.Content.RenderQueue do
  @moduledoc """
  Enqueues entry-rendering jobs at the content pipeline's asynchronous boundary.

  The worker is resolved at runtime so producers do not depend on the worker's
  block-rendering implementation.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Cache.Freshness

  @entry_renderer Module.concat(["Brando", "Worker", "EntryRenderer"])
  # The unique states of the render and cascade workers: a job that has not
  # started reads the write that queues another for its entry
  @waiting ~w(available scheduled)

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
  Enqueues one entry-rendering job. It carries what this node's render
  inputs have caught up with, so a node that has not caught up yet does
  before it renders (`Brando.Cache.ensure_fresh/1`).

  A render of the entry queued and not started yet takes this one's tokens
  instead (`coalesce/3`). One that has started may have read the entry and
  its inputs before the write that queues this one, so this one runs after it.
  """
  @spec enqueue(map()) :: term()
  def enqueue(args) do
    worker = @entry_renderer

    changeset =
      args
      |> Freshness.attach()
      |> Brando.Tenant.Job.attach()
      |> worker.new(tags: [:render_entry])

    changeset
    |> Oban.insert()
    |> coalesce(changeset, &Freshness.merge/2)
  end

  @doc false
  # What `Oban.insert/1` returned for `changeset`, with a conflict resolved:
  # the job it found waiting takes the arguments `merge` makes from its own
  # and the changeset's, or, when there is none to take them, the changeset
  # is inserted as it is.
  #
  # The update is conditional: the job may have started since Oban found it,
  # or another insert may have changed its arguments. Inside a transaction
  # it also holds the job until the transaction commits, so the job cannot
  # start before the write that queued this. A conflict without a job is a
  # unique insert of another transaction holding the lock: that transaction's
  # job may run before this write commits.
  @spec coalesce({:ok, Oban.Job.t()} | term(), Ecto.Changeset.t(), (map(), map() -> map())) :: term()
  def coalesce({:ok, %Oban.Job{conflict?: true, id: nil}}, changeset, _merge), do: insert_anyway(changeset)

  def coalesce({:ok, %Oban.Job{conflict?: true} = job}, changeset, merge) do
    args = merge.(job.args, Ecto.Changeset.get_field(changeset, :args))

    query =
      from j in Oban.Job,
        where: j.id == ^job.id and j.state in @waiting and j.args == type(^job.args, :map)

    case Brando.Repo.update_all(query, set: [args: args]) do
      {1, _} -> {:ok, %{job | args: args}}
      {0, _} -> insert_anyway(changeset)
    end
  end

  def coalesce(result, _changeset, _merge), do: result

  # A second render runs at worst, and one more read
  defp insert_anyway(changeset), do: changeset |> Ecto.Changeset.delete_change(:unique) |> Oban.insert()
end
