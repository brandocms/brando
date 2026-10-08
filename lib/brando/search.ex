defmodule Brando.Search do
  @moduledoc """
  The admin's full-text search: one `search_documents` table per site
  environment, with a row for each entry (and its language) of every content
  type that has an editor.

  ## What is indexed

  Each document holds the entry's title (weight A), its slug or URI and
  meta description (weight B), and the plain text of its text fields and of
  every block (weight C, see `Brando.Search.Text`), cut at about 200 KB. The
  `tsvector` is built with the language's text search configuration:
  `norwegian` for Norwegian, `english` for English and `simple` for any
  other language. Searching uses a GIN index on it; Brando needs no Postgres
  extension for this.

  ## Keeping it up to date

  `Brando.Search` is a `Brando.ContentEvents.Subscriber`, subscribed by
  default. Every content event for a searchable entry queues a
  `Brando.Worker.SearchIndexer` job on the `:search_index` queue, which reads
  the entry again and writes or removes its document. The event itself is
  not trusted: a later event, a retry or a repeat finds the entry as it is
  now, which makes the subscriber idempotent. Saves never wait for the index.

  `rebuild/1`, run by `Brando.Worker.SearchIndexRebuild` from Configuration
  → Utilities, indexes every entry of the current site and environment again
  and removes documents nothing has. Run it once after upgrading, and after
  changing what an identifier or text field holds.

  ## Configuration

      config :brando, Brando.Search, enabled: true

  With `enabled: false` nothing is queued and the index is left as it is.
  An application that sets `config :brando, Oban` itself must add the
  `search_index` queue; `mix brando.doctor` warns when it is missing.
  """
  @behaviour Brando.ContentEvents.Subscriber

  import Ecto.Query, only: [from: 2]

  alias Brando.ContentEvents
  alias Brando.ContentEvents.Event
  alias Brando.Repo
  alias Brando.Search.Document
  alias Brando.Search.Indexer
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Worker.SearchIndexer
  alias Brando.Worker.SearchIndexRebuild

  require Logger

  @unfinished ~w(available scheduled executing retryable)

  @doc "Whether saves keep the index up to date."
  @spec enabled?() :: boolean()
  def enabled?, do: Keyword.get(Brando.config(__MODULE__) || [], :enabled, true)

  @doc "The PubSub topic a rebuild of the current site and environment reports to."
  @spec topic(String.t() | nil) :: String.t()
  def topic(prefix \\ Brando.Tenant.current_prefix())
  def topic(nil), do: "brando:search"
  def topic(prefix), do: "brando:search:" <> prefix

  @doc """
  The content types in the index: those with persisted identifiers and an
  editor of their own. The command palette lists the same ones.
  """
  @spec searchable_schemas() :: [module()]
  def searchable_schemas do
    :include_brando
    |> Brando.Content.Identifier.Registry.list_persistent_identifier_modules()
    |> Enum.filter(&function_exported?(&1, :__admin_route__, 2))
    |> Enum.uniq()
  end

  @doc "Whether entries of `schema` are indexed."
  @spec searchable?(module() | nil) :: boolean()
  def searchable?(nil), do: false
  def searchable?(schema), do: schema in searchable_schemas()

  @doc """
  The text search configuration for a language: `norwegian` for Norwegian
  (`no`, `nb`, `nn`), `english` for English and `simple` otherwise.
  """
  @spec config_for(String.t() | atom() | nil) :: String.t()
  def config_for(language) do
    case language |> to_string() |> String.downcase() do
      code when code in ~w(no nb nn nor nob nno) -> "norwegian"
      "no-" <> _ -> "norwegian"
      "nb-" <> _ -> "norwegian"
      code when code in ~w(en eng) -> "english"
      "en-" <> _ -> "english"
      _ -> "simple"
    end
  end

  @doc "The text search configurations documents are written with."
  @spec configs() :: [String.t()]
  def configs, do: ~w(norwegian english simple)

  ## Subscriber

  @doc """
  Queues the entry of a content event for indexing. One job per entry waits
  at a time: events that arrive while it waits add nothing, and the job
  reads the entry as it is when it runs.
  """
  @impl Brando.ContentEvents.Subscriber
  def handle_event(%Event{schema: schema, entry_id: id}) when is_integer(id) do
    if enabled?() and searchable?(schema), do: queue_entry(schema, id), else: :ok
  end

  def handle_event(_event), do: :ok

  @doc "Queues `schema` entry `id` to be indexed again (or removed)."
  @spec queue_entry(module(), integer()) :: :ok | {:error, term()}
  def queue_entry(schema, id) do
    %{"schema" => to_string(schema), "entry_id" => id}
    |> TenantJob.attach()
    |> SearchIndexer.new()
    |> insert()
  end

  defp insert(changeset) do
    case Oban.insert(changeset) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  ## Indexing

  @doc """
  Writes the document of `schema` entry `id`, or removes it when the entry
  is gone or in the trash. Runs in the current site and environment.
  """
  @spec index_entry(module(), integer()) :: :ok | {:error, term()}
  def index_entry(schema, id) do
    if searchable?(schema), do: guarded(fn -> Indexer.index(schema, id) end), else: delete_entry(schema, id)
  end

  @doc "Removes every document of `schema` entry `id`."
  @spec delete_entry(module(), integer()) :: :ok | {:error, term()}
  def delete_entry(schema, id) do
    guarded(fn ->
      Repo.delete_all(from(d in Document, where: d.schema == ^schema and d.entry_id == ^id), ContentEvents.savepoint())
      :ok
    end)
  end

  @doc """
  Indexes every searchable entry of the current site and environment again,
  then removes the documents of entries that are gone. `progress` is called
  with the number done and the total after each batch.
  """
  @spec rebuild((non_neg_integer(), non_neg_integer() -> any())) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild(progress \\ fn _done, _total -> :ok end) do
    guarded(fn -> Indexer.rebuild(searchable_schemas(), progress) end)
  end

  # An environment that has not run the brando_212 migration has no table:
  # the index is skipped there, without failing the job again and again.
  defp guarded(fun) do
    fun.()
  rescue
    error in Postgrex.Error ->
      if missing_index_table?(error) do
        Logger.warning("[Brando.Search] No search_documents table here; run the brando_212 migration")
        {:error, :no_table}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  @doc false
  def missing_index_table?(%Postgrex.Error{postgres: %{code: :undefined_table, message: message}}),
    do: String.contains?(message, "search_documents")

  def missing_index_table?(_error), do: false

  @doc "Queues a rebuild of the current site and environment's index, unless one is unfinished."
  @spec queue_rebuild(map() | nil) :: {:ok, Oban.Job.t()} | {:error, :already_running | term()}
  def queue_rebuild(user \\ nil) do
    if rebuild_running?() do
      {:error, :already_running}
    else
      %{"user_id" => user && user.id}
      |> TenantJob.attach()
      |> SearchIndexRebuild.new()
      |> Oban.insert()
    end
  end

  @doc "Whether a rebuild of the current site and environment is queued or running."
  @spec rebuild_running?() :: boolean()
  def rebuild_running? do
    worker = Oban.Worker.to_string(SearchIndexRebuild)
    args = TenantJob.attach(%{})

    query =
      from j in Oban.Job,
        where: j.worker == ^worker and j.state in ^@unfinished and fragment("? @> ?", j.args, ^args),
        select: true,
        limit: 1

    Repo.one(query) == true
  end

  @doc "How many documents the current site and environment's index holds, or nil without the table."
  @spec count() :: non_neg_integer() | nil
  def count do
    Repo.aggregate(Document, :count)
  rescue
    error in Postgrex.Error -> if missing_index_table?(error), do: nil, else: reraise(error, __STACKTRACE__)
  end
end
