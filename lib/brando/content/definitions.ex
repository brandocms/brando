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

  @doc "Loads a directory of literal `.exs` definitions and an optional baseline lockfile."
  def read(directory) do
    protect(fn ->
      root = Path.expand(directory)

      case File.lstat(root) do
        {:ok, %{type: :directory}} -> :ok
        _ -> Error.raise!(root, "expected a definition directory")
      end

      paths = Reader.files!(root)
      if paths == [], do: Error.raise!(root, "no .exs definitions found")
      bundle = paths |> Enum.map(&Reader.read!/1) |> Model.from_specs!(root)
      lock_path = Path.join(root, "modules.lock.json")

      lock =
        if File.exists?(lock_path) do
          lock = lock_path |> Reader.regular_file!() |> Jason.decode!()
          if lock["format_version"] != 1, do: Error.raise!(lock_path, "unsupported format_version")
          Map.take(lock, ~w(source baseline references))
        else
          %{}
        end

      Map.merge(bundle, lock)
    end)
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

        Enum.each(bundle["modules"] ++ bundle["table_templates"], fn definition ->
          schema = if definition["kind"] == "module", do: Brando.Content.Module, else: Brando.Content.TableTemplate

          record =
            if definition["kind"] == "module",
              do: records.modules[definition["uid"]],
              else: records.tables[definition["uid"]]

          if Boundary.authorize_record(actor, :export, schema, record.id) != :ok,
            do: Error.raise!("authorization", "forbidden")
        end)

        Brando.Content.Definition.References.bind!(bundle, %{}, actor)
        files = Writer.write!(bundle, Path.expand(directory))
        %{bundle: bundle, files: files, directory: Path.expand(directory)}
      end)
    end
  end

  @doc "Builds a change plan in the current tenant. `:references` maps external tokens to destination IDs."
  def plan(bundle, actor, opts \\ []), do: Brando.Content.Definition.Importer.plan(bundle, actor, opts)

  @doc "Applies a plan after locking and checking its target and baseline again."
  def apply(plan, actor), do: Brando.Content.Definition.Importer.apply(plan, actor)

  @doc "Writes the baseline returned by a successful apply, leaving authored DSL and templates intact."
  def write_baseline(directory, %{bundle: bundle}) do
    protect(fn -> Writer.write_lock!(bundle, Path.expand(directory)) end)
  end

  @doc "Retries block synchronization, render enqueueing and notifications for local module UIDs."
  def refresh(uids, actor), do: Brando.Content.Definition.Importer.retry_refresh(uids, actor)

  @doc false
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

  @doc false
  def protect(fun) do
    {:ok, fun.()}
  rescue
    error in [Error, File.Error, Jason.DecodeError] -> {:error, Exception.message(error)}
  end
end
