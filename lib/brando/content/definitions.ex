defmodule Brando.Content.Definitions do
  @moduledoc """
  Bidirectional module-definition export, planning and import.

  `read/1` loads literal DSL files without executing them. `export/3` writes a
  new directory containing definitions, templates and a baseline lockfile.
  `plan/3` compares that bundle to the current tenant; `apply/2` rechecks the
  plan before writing. Actors are explicit; `:system` is for trusted CLI and
  maintenance callers only.

  See the [module definitions guide](module_definitions.md).
  """

  alias Brando.Authorization.Boundary
  alias Brando.Content.Definition
  alias Brando.Content.Definition.{Error, Model, Reader, Snapshot, Writer}

  @typedoc "A render or cascade job of a run, in `t:refresh_result/0`."
  @type refresh_job :: %{
          worker: :render | :cascade,
          schema: String.t() | nil,
          entry_id: term,
          tenant_prefix: String.t() | nil,
          state: String.t(),
          error: String.t() | nil
        }

  @typedoc "What `await_refresh/2` and `refresh_status/1` return."
  @type refresh_result :: %{
          rendered: non_neg_integer,
          failed: [refresh_job],
          pending: [refresh_job],
          timed_out: boolean
        }

  @doc "Loads a directory of literal `.exs` definitions and an optional baseline lockfile."
  def read(directory) do
    protect(fn ->
      root = Path.expand(directory)

      case File.lstat(root) do
        {:ok, %{type: :directory}} -> :ok
        _ -> Error.raise!(root, "expected a definition directory")
      end

      paths = Reader.files!(root)
      lock_path = Path.join(root, "modules.lock.json")
      if paths == [] and not File.exists?(lock_path), do: Error.raise!(root, "no .exs definitions found")
      bundle = paths |> Enum.map(&Reader.read!/1) |> Model.from_specs!(root)
      Map.merge(bundle, read_lock!(lock_path))
    end)
  end

  defp read_lock!(lock_path) do
    if File.exists?(lock_path) do
      lock = lock_path |> Reader.regular_file!() |> Jason.decode!()
      if lock["format_version"] != 1, do: Error.raise!(lock_path, "unsupported format_version")
      Map.take(lock, ~w(source baseline references))
    else
      %{}
    end
  end

  @doc "Builds a portable bundle from already compiled Spark definition modules."
  def from_modules(modules, opts \\ []) do
    protect(fn ->
      modules |> Enum.map(&Definition.specification/1) |> Model.from_specs!(Keyword.get(opts, :root, File.cwd!()))
    end)
  end

  @doc "Exports local definitions to a new directory. `:uids` selects complete module trees."
  def export(directory, actor, opts \\ []) do
    with :ok <- Boundary.authorize(actor, :export, Brando.Content.Module) do
      protect(fn ->
        validate_actor!(actor)
        {bundle, records} = Snapshot.take!(opts)

        Enum.each(bundle["modules"] ++ bundle["table_templates"], &authorize_export!(&1, records, actor))
        Brando.Content.Definition.References.bind!(bundle, %{}, actor)
        files = Writer.write!(bundle, Path.expand(directory))
        %{bundle: bundle, files: files, directory: Path.expand(directory)}
      end)
    end
  end

  defp authorize_export!(definition, records, actor) do
    schema = if definition["kind"] == "module", do: Brando.Content.Module, else: Brando.Content.TableTemplate

    record =
      if definition["kind"] == "module",
        do: records.modules[definition["uid"]],
        else: records.tables[definition["uid"]]

    if Boundary.authorize_record(actor, :export, schema, record.id) != :ok,
      do: Error.raise!("authorization", "forbidden")
  end

  @doc """
  Builds a change plan in the current tenant. Options:

    * `:references` - maps external tokens to destination IDs
    * `:baseline` - what each definition is compared with: `:lockfile` (the
      bundle's own baseline), `:database` (the definitions last applied in
      this environment, `Brando.Content.DefinitionApply`) or `:auto`, the
      default: the lockfile when it was written for this database, the
      database's own otherwise
    * `:select` - UIDs whose module trees an apply writes; without it, every
      definition
    * `:replace` - UIDs that were never applied from files and differ from
      them, to replace with the bundle's version anyway
    * `:creator` - a user or user ID for new records when the actor is
      `:system`; `:none` makes a plan that can't be applied

  See `Brando.Content.Definition.Plan` for what each item says.
  """
  def plan(bundle, actor, opts \\ []), do: Brando.Content.Definition.Importer.plan(bundle, actor, opts)

  @doc """
  Applies a plan after locking and checking its target and baseline again,
  and records each definition it wrote, or found equal, as applied
  (`Brando.Content.DefinitionApply`) in the same transaction. Options:
  `:source` (`:release` or `:import`, the default), `:release` (the release
  version) and `:batch_id`.
  """
  def apply(plan, actor, opts \\ []), do: Brando.Content.Definition.Importer.apply(plan, actor, opts)

  @doc """
  The PubSub topic that hears `{:definitions_applied, prefix}` after each
  apply, and `{:definitions_changed, prefix}` after a module is saved or
  deleted, a table template saved or deleted, or the environment `prefix`
  copied over, restored from an archive or created.
  """
  def topic, do: "brando:definitions"

  @doc """
  Announces, once the current transaction commits, that definitions changed
  in the environment `prefix` (the current one by default), once however many
  times a transaction calls it, and has the release status planned again
  there (`Brando.Content.Definitions.ReleaseStatus.changed/1`).
  """
  def changed(prefix \\ Brando.Tenant.current_prefix()) do
    Brando.Repo.after_commit({__MODULE__, :changed, prefix}, fn ->
      Phoenix.PubSub.broadcast(Brando.pubsub(), topic(), {:definitions_changed, prefix})
      Brando.Content.Definitions.ReleaseStatus.changed(prefix)
    end)
  end

  @doc "Writes the baseline returned by a successful apply, leaving authored DSL and templates intact."
  def write_baseline(directory, %{bundle: bundle}) do
    protect(fn -> Writer.write_lock!(bundle, Path.expand(directory)) end)
  end

  @doc "Retries block synchronization, render enqueueing and notifications for local module UIDs."
  def refresh(uids, actor), do: Brando.Content.Definition.Importer.retry_refresh(uids, actor)

  @doc """
  Runs `fun`, which applies a plan (`apply/2`) or refreshes modules
  (`refresh/2`), and returns `{fun's result, run}`. `run` names the render
  and cascade jobs it queued, for `await_refresh/2` and `refresh_status/1`.
  """
  @spec track_refresh((-> result)) :: {result, String.t()} when result: term
  defdelegate track_refresh(fun), to: Brando.Content.RenderRun, as: :track

  @doc """
  Follows the jobs of `run` (`track_refresh/1`) until each entry has rendered
  or failed, on whichever node runs them, and returns:

    * `:rendered`: the number of entries rendered.
    * `:failed`: a map for each entry whose render failed, and each cascade
      that failed, with `:worker` (`:render` or `:cascade`), `:schema`,
      `:entry_id`, `:tenant_prefix`, the job's `:state` and its last `:error`.
      A render that failed an attempt counts as failed at once: Oban retries
      it later, on a node that runs its queue.
    * `:pending`: the same maps for those still queued or running.
    * `:timed_out`: whether `:timeout` passed first.

  Options: `:timeout` in milliseconds (10 minutes), `:interval` between looks
  at the jobs table in milliseconds (500), and `:on_progress`, called with
  `%{done: n, total: n, failed: n}` for the entries whenever that changes.

  Call it right after `track_refresh/1`: it knows the jobs by their rows, and
  Oban's Pruner deletes a finished job a few minutes after it finished.
  """
  @spec await_refresh(String.t(), keyword) :: refresh_result
  defdelegate await_refresh(run, opts \\ []), to: Brando.Content.RenderRun, as: :await

  @doc "What `await_refresh/2` would return now for `run`, without waiting."
  @spec refresh_status(String.t()) :: refresh_result
  defdelegate refresh_status(run), to: Brando.Content.RenderRun, as: :status

  @doc """
  Returns `:ok` for `:system` or an active, undeleted account whose authorization
  scope matches the current tenant prefix. Raises a definition error otherwise.
  """
  def validate_actor!(:system), do: :ok

  def validate_actor!(%{id: id} = actor) do
    user = Brando.Repo.get(Brando.Users.User, id)
    unless user && user.active && is_nil(user.deleted_at), do: Error.raise!("authorization", "expected an active account")

    if Brando.Authorization.Engine.enabled?() do
      scope = Boundary.actor_scope(actor)

      if scope.prefix != Brando.Tenant.current_prefix(),
        do: Error.raise!("authorization", "actor scope does not match the target")
    end

    :ok
  end

  def validate_actor!(_), do: Error.raise!("authorization", "expected an account or explicit :system actor")

  @doc """
  Runs `fun` and returns `{:ok, result}`, or `{:error, message}` when it raises a
  definition, file or JSON decoding error. Other exceptions propagate.
  """
  def protect(fun) do
    {:ok, fun.()}
  rescue
    error in [Error, File.Error, Jason.DecodeError] -> {:error, Exception.message(error)}
  end
end
