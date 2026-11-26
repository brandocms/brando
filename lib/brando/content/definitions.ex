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
  alias Brando.Content.Definition.{Error, Model, Reader, References, Snapshot, Writer}

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
      bundle = paths |> Enum.map(&Reader.read!(&1, Error.file_label(&1, root))) |> Model.from_specs!(root)
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

  @doc """
  Exports local definitions to a new directory. `:uids` selects complete
  module trees, palettes and containers, with the palettes they point at.
  `:unavailable` in the result lists the containers whose default palette
  the files leave out, as it is in the trash: an import keeps that link.
  """
  def export(directory, actor, opts \\ []) do
    with :ok <- Boundary.authorize(actor, :export, Brando.Content.Module) do
      protect(fn ->
        validate_actor!(actor)
        {bundle, records} = Snapshot.take!(opts)
        bundle = exportable!(bundle, records, actor, opts[:uids])
        References.bind!(bundle, %{}, actor)
        files = Writer.write!(bundle, Path.expand(directory))
        %{bundle: bundle, files: files, directory: Path.expand(directory), unavailable: unavailable(bundle, records)}
      end)
    end
  end

  # Each container whose default palette the files leave out, as no
  # definition can name it here
  defp unavailable(bundle, records) do
    for %{"palette" => nil, "uid" => uid, "name" => name} <- bundle["containers"],
        palette = References.unavailable_palette(records.containers[uid].palette_id),
        do: %{uid: uid, container: name, palette: palette.name}
  end

  # What the actor may export. Every module and table template, and every
  # selected palette and container, needs the actor's export grant; a full
  # export leaves out the palettes and containers the actor may not export,
  # unless what it writes names one: that is refused by name.
  defp exportable!(bundle, records, actor, uids) do
    allowed? = fn %{"kind" => kind, "uid" => uid} ->
      Boundary.authorize_record(actor, :export, Model.schema(kind), Snapshot.record(records, kind, uid).id) == :ok
    end

    if Enum.any?(bundle["modules"] ++ bundle["table_templates"], &(not allowed?.(&1))), do: forbidden!()
    {containers, left_out} = Enum.split_with(bundle["containers"], allowed?)
    if uids && left_out != [], do: forbidden!()
    named = named_palettes(bundle, containers)

    palettes = Enum.filter(bundle["palettes"], &exportable_palette?(&1, allowed?, named, uids))

    if containers == bundle["containers"] and palettes == bundle["palettes"] do
      bundle
    else
      bundle = %{bundle | "containers" => containers, "palettes" => palettes}
      Map.put(bundle, "baseline", Snapshot.baselines(bundle))
    end
  end

  defp exportable_palette?(palette, allowed?, named, uids) do
    cond do
      allowed?.(palette) -> true
      subject = named[palette["uid"]] -> Error.raise!(subject, ~s(palette "#{palette["uid"]}": export forbidden))
      uids -> forbidden!()
      true -> false
    end
  end

  defp forbidden!, do: Error.raise!("authorization", "forbidden")

  # The definition that names each palette: a var of a module or a table
  # template, or one of `containers`
  defp named_palettes(bundle, containers) do
    vars =
      for definition <- bundle["modules"] ++ bundle["table_templates"],
          var <- definition["vars"],
          token = var["assets"]["palette"],
          do:
            {get_in(bundle, ["references", token, "uid"]) || token, Model.subject(definition["kind"], definition["uid"])}

    defaults =
      for %{"palette" => uid} = container <- containers, uid, do: {uid, Model.subject("container", container["uid"])}

    Map.new(Enum.reverse(vars ++ defaults))
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
    * `:catch_up` - against the lockfile, a definition that no longer
      equals the lockfile's baseline but equals what was last applied here
      is compared with that apply: the lockfile's write failed after it

  See `Brando.Content.Definition.Plan` for what each item says.
  """
  def plan(bundle, actor, opts \\ []), do: Brando.Content.Definition.Importer.plan(bundle, actor, opts)

  @doc """
  Applies a plan after locking and checking its target and baseline again,
  and records each definition it wrote, or found equal, as applied
  (`Brando.Content.DefinitionApply`) in the same transaction. Options:
  `:source` (`:release` or `:import`, the default), `:release` (the release
  version) and `:batch_id`.

  The result's `renamed` says, for each module whose renames blocks hold a
  value of, whether the apply moved the values or left them for the resolve
  command (`left?`, over its limit: `Brando.Content.Definition.Renames`),
  with the line that says so (`Brando.Content.Definition.Plan.renamed_text/1`).

  `drop:` the `digest` of `Brando.Content.Definition.Drops.plan/2` a review
  saw: the apply also drops the values blocks hold in the refs and vars it
  removes, and keeps them under `:batch_id` for a revert. The result's
  `dropped` counts them by module uid.
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

  @doc """
  Retries what follows an apply for local definition UIDs: block
  synchronization, render enqueueing and notifications for a module, the
  palette CSS and renders for a palette, renders for a container.
  """
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
