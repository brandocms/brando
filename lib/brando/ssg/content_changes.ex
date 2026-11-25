defmodule Brando.SSG.ContentChanges do
  @moduledoc """
  When each environment of a static site last had its content changed, so
  the site can tell whether content changed after a build
  (`changed_since?/1`).

  One row per environment (`ssg_content_changes`, in `public`), written once
  the save that changed the content has committed. Every save of content
  passes one of two places, and both mark the environment of the write
  (`touch/0,1`): `Brando.Cache.Query`, which evicts the environment's cached
  queries, and `Brando.Cache.rebuild_after_commit/1`, which rebuilds its site
  caches (identity, SEO, globals, palettes, menus). Media saves evict too.
  Activating an asset set marks the environments that render with it, and
  copying an environment over another marks the target
  (`touch_environment/1`, `touch_site/1`).

  A transaction begun with `Brando.Repo.transaction/2` marks each environment
  once, after it has committed; a save outside a transaction marks once for
  each of its evictions. Nothing is marked for a site whose delivery is
  dynamic, a write to a shared table (`Brando.Tenant.SharedTables`), the
  activity log's own rows, or what a static build's own page requests write
  (`Brando.Assets.SiteAssets.build_set?/0`), so a build does not leave its
  environment changed.

  A mark errs towards changed: a save that changes nothing a build renders
  (a draft, a note) may mark. It can also be lost: the process that saved
  stopped between the commit and the mark, or the write failed, which is
  logged and never fails the save. `changed_since?/1` therefore also reads
  the environment's activity log, which is written with the save.

  Once a mark is written, `{:ssg_content_changed, environment_id}` goes out on
  the site's `Brando.SSG.Builds.topic/1`, at most once a second for each
  environment: a change within that second is told at its end.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Assets.SiteAssets
  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.Tenant

  require Logger

  @interval 1_000
  @waiters Brando.SSG.ContentChanges.TaskSupervisor

  # What an MCP client asked for, and notes beside an entry: the changes a
  # tool call makes log their own events
  @not_changes [:tool_called, :note_added, :note_resolved, :note_reopened]

  # Every environment named, of a static site; nil for every site or every
  # environment of it. Dated by the database's clock, as builds start
  # (`now/0`), and never moved back.
  @mark """
  INSERT INTO public.ssg_content_changes AS change (environment_id, changed_at)
  SELECT environment.id, clock_timestamp() AT TIME ZONE 'UTC'
  FROM public.environments AS environment
  JOIN public.sites AS site ON site.id = environment.site_id
  WHERE site.delivery_mode = 'static'
    AND ($1::bigint IS NULL OR site.id = $1)
    AND ($2::bigint[] IS NULL OR environment.id = ANY($2))
  ON CONFLICT (environment_id) DO UPDATE SET changed_at = GREATEST(change.changed_at, EXCLUDED.changed_at)
  RETURNING change.environment_id, (SELECT site_id FROM public.environments WHERE id = change.environment_id)
  """

  @doc """
  Marks the caller's environment (its tenant prefix) as changed, once the
  transaction around the caller has committed, or at once outside one. Does
  nothing without a tenant prefix, for a dynamic site, or in a static
  build's own page request.
  """
  @spec touch() :: :ok
  def touch do
    prefix = Tenant.current_prefix()

    with false <- SiteAssets.build_set?(),
         site_key when is_binary(site_key) <- Tenant.site_key_of(prefix),
         %Site{id: site_id, delivery_mode: :static} <- Tenant.Cache.get_site(site_key),
         %Environment{id: id} <- Tenant.Cache.get_env(site_key, Tenant.environment_key_of(prefix)) do
      hold({:environment, id}, site_id, [id])
    else
      _no_static_environment -> :ok
    end
  end

  @doc """
  As `touch/0`, for a write to the table `source`: a shared table, or the
  activity log, marks nothing.
  """
  @spec touch(String.t()) :: :ok
  def touch(source) when is_binary(source) do
    if source == "activity_events" or Tenant.SharedTables.member?(source), do: :ok, else: touch()
  end

  @doc "Marks `environment` as changed, as `touch/0` does, when its site's delivery is static."
  @spec touch_environment(Environment.t()) :: :ok
  def touch_environment(%Environment{id: id, site_id: site_id}), do: hold({:environment, id}, site_id, [id])

  @doc """
  Marks every environment of the site with `site_id` as changed, as
  `touch/0` does, when its delivery is static; with nil, every environment of
  every static site (the standalone asset set, in `tenancy_mode: :single`).
  """
  @spec touch_site(pos_integer() | nil) :: :ok
  def touch_site(site_id), do: hold({:site, site_id}, site_id, nil)

  @doc "When `environment`'s content was last marked as changed, or nil."
  @spec changed_at(Environment.t() | pos_integer()) :: DateTime.t() | nil
  def changed_at(%Environment{id: id}), do: changed_at(id)

  def changed_at(environment_id) when is_integer(environment_id) do
    from(change in "ssg_content_changes",
      where: change.environment_id == ^environment_id,
      select: type(change.changed_at, :utc_datetime_usec)
    )
    |> Brando.Repo.one(prefix: "public")
  end

  @doc """
  Whether the content of `build`'s environment changed after the build
  started (`started_at`, or for a build made before it was recorded, when it
  was queued): its mark is as new or newer, or its activity log has an event
  since then, which covers a mark that was lost and edits made before marks
  were kept. Media is the part only the mark sees. True when the build's
  environment is gone. Reads the site and environment when `build` does not
  have them loaded.
  """
  @spec changed_since?(Build.t()) :: boolean()
  def changed_since?(%Build{} = build) do
    case Brando.Repo.preload(build, [:site, :environment], prefix: "public") do
      %Build{site: %Site{} = site, environment: %Environment{} = environment} = build ->
        since = build.started_at || build.inserted_at
        marked_since?(environment, since) or logged_since?(Tenant.prefix(site, environment), since)

      %Build{} ->
        true
    end
  end

  defp marked_since?(environment, since) do
    case changed_at(environment) do
      nil -> false
      changed_at -> DateTime.compare(changed_at, since) != :lt
    end
  end

  # An environment being copied over has its schema dropped and cloned again
  defp logged_since?(prefix, since) do
    from(event in Event, where: event.inserted_at >= ^since and event.action not in ^@not_changes)
    |> Brando.Repo.repo().exists?(prefix: prefix)
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] in [:undefined_table, :invalid_schema_name], do: true, else: reraise(error, __STACKTRACE__)
  end

  @doc """
  The database's clock, which dates marks: a build's `started_at` is taken
  from it, so a node whose clock differs does not misplace a change.
  """
  @spec now() :: DateTime.t()
  def now do
    %{rows: [[now]]} = Brando.Repo.repo().query!("SELECT clock_timestamp() AT TIME ZONE 'UTC'")
    DateTime.from_naive!(now, "Etc/UTC")
  end

  # Once per transaction for each environment or site, after the rest of its
  # after-commit work: a build that starts once it is marked reads no cache
  # entry the transaction's evictions and rebuilds have yet to refresh
  defp hold(key, site_id, environment_ids) do
    Brando.Repo.after_commit({__MODULE__, key}, fn -> mark(site_id, environment_ids) end, late: true)
  end

  # Inside a transaction begun on the repo itself, `Brando.Repo.after_commit/2`
  # runs the work at once, before the commit. A write there could abort the
  # save, and would date the change before the commit: a build that started
  # in between would miss the change and still compare as newer. Another
  # process writes it once the transaction has ended.
  defp mark(site_id, environment_ids) do
    if Brando.Repo.repo().in_transaction?(),
      do: mark_after_transaction(site_id, environment_ids),
      else: site_id |> write(environment_ids) |> announce()
  end

  defp write(site_id, environment_ids) do
    case Brando.Repo.repo().query(@mark, [site_id, environment_ids]) do
      {:ok, %{rows: rows}} ->
        rows

      {:error, error} ->
        log_failure(error)
        []
    end
  rescue
    error ->
      log_failure(error)
      []
  end

  defp log_failure(error) do
    Logger.warning("[Brando.SSG.ContentChanges] Could not record a content change: " <> Exception.message(error))
  end

  # The transaction holds a lock of the caller's for as long as it runs, and
  # a waiter writes the mark once it has the lock. One waiter for each
  # environment, or site, serves every write of the transaction: a later
  # transaction whose waiter has taken the lock already gets one of its own.
  # The lock is taken in a savepoint, so it cannot abort the save.
  defp mark_after_transaction(site_id, environment_ids) do
    lock = transaction_lock()

    case Brando.Repo.repo().query("SELECT pg_advisory_xact_lock_shared($1)", [lock], mode: :savepoint) do
      {:ok, _} ->
        waiter = {__MODULE__, :waiter, site_id, environment_ids}

        unless waiting?(Process.get(waiter)),
          do: Process.put(waiter, start_waiter(lock, site_id, environment_ids))

      {:error, error} ->
        log_failure(error)
    end

    :ok
  end

  # The caller's own: random, as a waiter must not wait for another
  # process's transactions, on any node
  defp transaction_lock do
    with nil <- Process.get({__MODULE__, :lock}) do
      lock = :rand.uniform(2 ** 62)
      Process.put({__MODULE__, :lock}, lock)
      lock
    end
  end

  # Still waiting for the transaction it was started in, or a later one
  defp waiting?({pid, taken}), do: Process.alive?(pid) and :atomics.get(taken, 1) == 0
  defp waiting?(nil), do: false

  defp start_waiter(lock, site_id, environment_ids) do
    taken = :atomics.new(1, [])

    case Task.Supervisor.start_child(@waiters, fn -> wait_and_write(lock, taken, site_id, environment_ids) end) do
      {:ok, pid} ->
        {pid, taken}

      {:error, reason} ->
        log_failure(RuntimeError.exception(inspect(reason)))
        nil
    end
  catch
    # The supervisor is not running, or restarting
    :exit, reason ->
      log_failure(RuntimeError.exception(inspect(reason)))
      nil
  end

  defp wait_and_write(lock, taken, site_id, environment_ids) do
    repo = Brando.Repo.repo()

    {:ok, rows} =
      repo.transaction(
        fn ->
          repo.query!("SELECT pg_advisory_xact_lock($1)", [lock], timeout: :infinity)
          :atomics.put(taken, 1, 1)
          write(site_id, environment_ids)
        end,
        timeout: :infinity
      )

    announce(rows)
  rescue
    error -> log_failure(error)
  end

  defp announce(rows), do: Enum.each(rows, fn [environment_id, site_id] -> changed(site_id, environment_id) end)

  defp changed(site_id, environment_id), do: GenServer.cast(__MODULE__, {:changed, site_id, environment_id})

  # Broadcasts

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl GenServer
  def init(nil), do: {:ok, %{}}

  # By environment: `{:told, site_id}` within a second of telling, or
  # `{:pending, site_id}` when it changed again since
  @impl GenServer
  def handle_cast({:changed, site_id, environment_id}, state) do
    case Map.get(state, environment_id) do
      nil -> {:noreply, tell(state, site_id, environment_id)}
      _told_or_pending -> {:noreply, Map.put(state, environment_id, {:pending, site_id})}
    end
  end

  @impl GenServer
  def handle_info({:quiet, environment_id}, state) do
    case Map.get(state, environment_id) do
      {:pending, site_id} -> {:noreply, tell(state, site_id, environment_id)}
      _told -> {:noreply, Map.delete(state, environment_id)}
    end
  end

  defp tell(state, site_id, environment_id) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), Builds.topic(site_id), {:ssg_content_changed, environment_id})
    Process.send_after(self(), {:quiet, environment_id}, @interval)
    Map.put(state, environment_id, {:told, site_id})
  end
end
