defmodule Brando.Content.Definition.Watcher do
  @moduledoc """
  Development aid: imports module definition files when they change on disk.

  Export the modules once, then point the watcher at that directory:

      mix brando.modules export --out priv/modules --user 1

      # config/dev.exs
      config :brando, Brando.Content.Definition.Watcher,
        path: "priv/modules",
        user_id: 1

  Tenant applications also set `site:` and `environment:` keys, like the CLI.

  Every save runs the same plan as `mix brando.modules import`. A clean plan is
  applied and `modules.lock.json` advances to the new baseline; conflicts
  (someone changed the module in the admin since the baseline) and structural
  changes that need a migration are logged and nothing is written. Unchanged
  definitions are left alone, so saving a file without edits does nothing.

  It only runs when configured and when `FileSystem` is loaded, which Phoenix
  apps get in dev through `phoenix_live_reload`. Never configure it in
  production: it applies whatever is on disk without a preview.

  See the [module definitions guide](module_definitions.md).
  """
  use GenServer

  require Logger

  alias Brando.Content.Definition.{Plan, Reader, References, Snapshot}
  alias Brando.Content.Definitions
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @compile {:no_warn_undefined, FileSystem}

  # Editors write a file as several events, and a rename across files touches
  # two. Wait for the burst to settle before reading the directory.
  @debounce 250
  @extensions ~w(.exs .heex .liquid)

  # The admin asks once per listing row; admin edits don't pass through the
  # watcher, so the status is only trusted briefly.
  @status_ttl 2_000

  @doc "The watcher's child spec when it is configured and can run, otherwise none."
  def children do
    config = Application.get_env(:brando, __MODULE__)

    cond do
      is_nil(config) -> []
      not Code.ensure_loaded?(FileSystem) -> warn_unavailable()
      true -> [{__MODULE__, config}]
    end
  end

  def start_link(config), do: GenServer.start_link(__MODULE__, config, name: __MODULE__)

  @impl GenServer
  def init(config) do
    path = config |> Keyword.fetch!(:path) |> Path.expand()
    user_id = Keyword.fetch!(config, :user_id)

    if File.dir?(path) do
      {:ok, watcher} = FileSystem.start_link(dirs: [path])
      FileSystem.subscribe(watcher)
      Logger.info("==> Brando >> Watching module definitions in #{Path.relative_to_cwd(path)}")
      {:ok, %{path: path, user_id: user_id, config: config, watcher: watcher, timer: nil, status: nil, status_at: 0}}
    else
      Logger.warning(
        "==> Brando >> Module definition watcher: #{Path.relative_to_cwd(path)} does not exist. " <>
          "Export it first: mix brando.modules export --out #{Path.relative_to_cwd(path)} --user #{user_id}"
      )

      :ignore
    end
  end

  @impl GenServer
  def handle_info({:file_event, watcher, {file, _events}}, %{watcher: watcher} = state) do
    if Path.extname(file) in @extensions do
      if state.timer, do: Process.cancel_timer(state.timer)
      {:noreply, %{state | timer: Process.send_after(self(), :sync, @debounce), status: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, watcher, :stop}, %{watcher: watcher} = state), do: {:stop, :normal, state}

  def handle_info(:sync, state) do
    log(sync(state.path, state.user_id, state.config))
    {:noreply, %{state | timer: nil, status: nil}}
  end

  @impl GenServer
  def handle_call({:status, fresh?}, _from, state) do
    now = System.monotonic_time(:millisecond)

    state =
      if fresh? or is_nil(state.status) or now - state.status_at > @status_ttl,
        do: %{state | status: status(state.path, state.config), status_at: now},
        else: state

    {:reply, state.status, state}
  end

  @doc """
  The definition file behind a module, for the admin to show. `nil` unless the
  watcher runs for the current tenant and the directory holds this UID.

  Returns `%{name: name, path: path, absolute: path, state: state}` — `name`
  within the definition directory, `path` from the project root — where
  `state` is

    * `:in_sync` — the database and the file agree
    * `:pending` — the file has changes that are not imported, usually because
      they need a migration, or the module doesn't exist yet
    * `:changed_in_admin` — the module changed in the admin since the file was
      imported; the file's next save is refused as a conflict
    * `:changed_in_both` — both sides changed since the last import

  Pass `fresh: true` right after saving a module in the admin.
  """
  def file(uid, opts \\ []) do
    with pid when is_pid(pid) <- Process.whereis(__MODULE__),
         {:ok, prefix, files} <- GenServer.call(pid, {:status, opts[:fresh] == true}),
         true <- prefix == Tenant.current_prefix() do
      files[uid]
    else
      _ -> nil
    end
  catch
    # Busy with a long import, or restarting: show nothing rather than wait
    :exit, _ -> nil
  end

  @doc false
  def status(path, config \\ []) do
    with {:ok, prefix} <- prefix(config),
         {:ok, files} <- Tenant.with_prefix(prefix, fn -> file_states(path) end) do
      {:ok, prefix, files}
    end
  rescue
    # A half-saved file: no markers until the next save
    error -> {:error, Exception.message(error)}
  end

  # The same comparison the importer makes: digests of the file's definition,
  # the stored module and the baseline recorded at the last import
  defp file_states(path) do
    with {:ok, bundle} <- Definitions.read(path) do
      files = Map.new(Reader.files!(path), &{Reader.read!(&1).options[:uid], &1})
      same_site? = bundle["source"] == References.scope()
      bindings = if same_site?, do: bundle["references"] || %{}, else: %{}
      baseline = if same_site?, do: get_in(bundle, ["baseline", "modules"]) || %{}, else: %{}
      {snapshot, _records} = Snapshot.take!(bindings: bindings, all_tables: true)
      stored = Map.new(snapshot["modules"], &{&1["uid"], Snapshot.baseline_digest(bundle, &1)})

      states =
        Map.new(bundle["modules"], fn definition ->
          uid = definition["uid"]
          file = files[uid]
          state = state(stored[uid], Snapshot.baseline_digest(bundle, definition), baseline[uid])
          {uid, %{name: Path.relative_to(file, path), path: Path.relative_to_cwd(file), absolute: file, state: state}}
        end)

      {:ok, states}
    end
  end

  defp state(nil, _file, _baseline), do: :pending
  defp state(same, same, _baseline), do: :in_sync
  defp state(baseline, _file, baseline), do: :pending
  defp state(_stored, baseline, baseline), do: :changed_in_admin
  defp state(_stored, _file, _baseline), do: :changed_in_both

  @doc """
  Plans the directory against the database and applies it when the plan is
  clean. Returns `{:ok, :unchanged}`, `{:ok, changes}`, `{:blocked, items}`
  for conflicts and required migrations, or `{:error, reason}`.
  """
  def sync(path, user_id, config \\ []) do
    with {:ok, user} <- user(user_id),
         {:ok, prefix} <- prefix(config) do
      Tenant.with_prefix(prefix, fn -> sync_in_tenant(path, user) end)
    end
  rescue
    # A half-saved file or a template that doesn't compile yet must not stop
    # the watcher; the next save tries again.
    # The stacktrace keeps a real bug from passing as a bad file.
    error -> {:error, Exception.format(:error, error, __STACKTRACE__)}
  end

  defp sync_in_tenant(path, user) do
    with {:ok, bundle} <- Definitions.read(path),
         {:ok, plan} <- Definitions.plan(bundle, user) do
      names = names(bundle)
      changes = plan.items |> Enum.reject(&(&1.action == :noop)) |> Enum.map(&Map.put(&1, :name, names[&1.uid]))

      cond do
        changes == [] ->
          {:ok, :unchanged}

        not Plan.applicable?(plan) ->
          {:blocked, Enum.reject(changes, &(&1.action in [:create, :update]))}

        true ->
          apply_changes(plan, path, user, changes)
      end
    end
  end

  defp apply_changes(plan, path, user, changes) do
    with {:ok, result} <- Definitions.apply(plan, user),
         {:ok, :ok} <- Definitions.write_baseline(path, result) do
      {:ok, changes}
    end
  end

  # UIDs are opaque; the log names definitions the way the admin does
  defp names(bundle) do
    language = to_string(Brando.config(:default_admin_language) || "en")

    Map.new(bundle["modules"] ++ bundle["table_templates"], fn definition ->
      name =
        case definition["name"] do
          %{^language => name} when name not in [nil, ""] -> name
          %{"en" => name} when name not in [nil, ""] -> name
          name when is_binary(name) -> name
          _ -> definition["uid"]
        end

      {definition["uid"], name}
    end)
  end

  defp user(user_id) do
    case Brando.Repo.get(Brando.Users.User, user_id) do
      %{active: true, deleted_at: nil} = user -> {:ok, user}
      _ -> {:error, "user_id #{inspect(user_id)} is not an active account"}
    end
  end

  defp prefix(config) do
    cond do
      Tenant.mode() == :none ->
        {:ok, nil}

      is_nil(config[:site]) or is_nil(config[:environment]) ->
        {:error, "tenant applications must configure site: and environment:"}

      true ->
        with site when not is_nil(site) <- Registry.get_site_by_key(config[:site]),
             environment when not is_nil(environment) <- Registry.get_environment_by_key(site, config[:environment]) do
          {:ok, Tenant.prefix(site, environment)}
        else
          nil -> {:error, "unknown site #{config[:site]} or environment #{config[:environment]}"}
        end
    end
  end

  defp log({:ok, :unchanged}), do: :ok

  defp log({:ok, changes}) do
    summary = Enum.map_join(changes, ", ", &"#{&1.action} #{&1.name}")
    Logger.info("==> Brando >> Imported module definitions: #{summary}")
  end

  defp log({:blocked, items}) do
    details = Enum.map_join(items, "\n", &"  #{&1.action} #{&1.kind} #{&1.name}: #{&1.reason}")

    Logger.warning(
      "==> Brando >> Module definitions not imported; nothing was written:\n#{details}\n" <>
        "A conflict means the module changed in the admin since your baseline. " <>
        "See the module definitions guide."
    )
  end

  defp log({:error, reason}), do: Logger.warning("==> Brando >> Module definitions not imported: #{reason}")

  defp warn_unavailable do
    Logger.warning("==> Brando >> Module definition watcher is configured, but FileSystem is not available")
    []
  end
end
