defmodule Brando.Environments do
  @moduledoc """
  Lifecycle API for named, schema-backed content environments.

  Registry rows always live in `public`; each environment's content lives in
  `tenant_{site_key}_{environment_key}`. Creation compensates for migration
  failures by removing both the new schema and registry row. Destructive copy,
  archives, rollback, and scheduling are layered on this foundation.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Environment
  alias Brando.Environments.OperationLog
  alias Brando.Environments.Schema
  alias Brando.Environments.SchemaCloner.Postgres, as: PostgresSchemaCloner
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Worker.EnvironmentCopy
  alias Brando.Worker.EnvironmentSetLive

  @public_prefix "public"
  @public_opts [prefix: @public_prefix]
  @default_archive_keep 3

  @doc """
  Creates the public environment record and its PostgreSQL schema, clones the
  content structure from `public`, then applies all tenant migrations. A failed
  schema creation, structure clone, or migration is compensated.
  """
  @spec create_environment(Site.t(), map(), keyword()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_environment(site, attrs, opts \\ [])

  def create_environment(%Site{} = site, attrs, opts) do
    Brando.Authorization.Operations.run(:create, :environments, site.id, opts, fn ->
      do_create_environment(site, attrs, opts)
    end)
  end

  defp do_create_environment(%Site{} = site, attrs, opts) do
    with {:ok, environment} <- Registry.create_environment(site, attrs),
         prefix = Tenant.prefix(site, environment),
         :ok <- create_schema_or_compensate(environment, prefix),
         :ok <- clone_structure_or_compensate(environment, prefix, opts),
         {:ok, _versions} <- migrate_or_compensate(site, environment, prefix) do
      log_operation!(site.id, :create,
        target_environment_id: environment.id,
        creator_id: creator_id(opts),
        note: opts[:note]
      )

      Cache.invalidate()
      announce(site.id)
      {:ok, environment}
    end
  end

  @doc """
  PubSub topic carrying environment lifecycle changes for one site.

  Scheduled copies and live switches run in Oban workers, so a browser sitting
  on the environments screen has no other way to learn that state moved.
  """
  @spec topic(pos_integer()) :: String.t()
  def topic(site_id), do: "brando:environments:#{site_id}"

  defp announce(site_id) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic(site_id), {:environments_updated, site_id})
  end

  @doc "Runs tenant migrations on one environment schema."
  @spec migrate(Environment.t()) :: {:ok, [integer()]} | {:error, term()}
  def migrate(%Environment{} = environment) do
    case Registry.get_site(environment.site_id) do
      nil -> {:error, :site_not_found}
      %Site{} = site -> migrator().migrate(site, environment)
    end
  end

  @doc "Runs tenant migrations on every registered environment schema."
  @spec migrate_all() :: {:ok, [{Environment.t(), [integer()]}]} | {:error, term()}
  def migrate_all do
    Registry.list_sites()
    |> Enum.flat_map(& &1.environments)
    |> Enum.sort_by(& &1.id)
    |> migrate_environments()
  end

  @doc "Runs tenant migrations on every environment belonging to one site."
  @spec migrate_site(Site.t()) :: {:ok, [{Environment.t(), [integer()]}]} | {:error, term()}
  def migrate_site(%Site{} = site) do
    site
    |> Registry.list_environments()
    |> Enum.sort_by(& &1.id)
    |> migrate_environments()
  end

  @doc "Deletes a non-live environment and its content schema."
  @spec delete_environment(Environment.t(), keyword()) ::
          {:ok, Environment.t()} | {:error, term()}
  def delete_environment(environment, opts \\ [])

  def delete_environment(%Environment{} = environment, opts) do
    Brando.Authorization.Operations.run(:delete, :environments, environment.site_id, opts, fn ->
      do_delete_environment(environment, opts)
    end)
  end

  defp do_delete_environment(%Environment{} = environment, opts) do
    with %Environment{} = current_environment <- Registry.get_environment(environment.id),
         %Site{} = site <- Registry.get_site(current_environment.site_id) do
      with_site_lock(site, fn -> delete_under_lock(site, current_environment.id, opts) end)
    else
      nil ->
        {:error, :site_or_environment_not_found}
    end
  end

  @doc "Atomically marks one environment as the sole live environment for its site."
  @spec set_live(Environment.t(), keyword()) :: {:ok, Environment.t()} | {:error, term()}
  def set_live(environment, opts \\ [])

  def set_live(%Environment{} = environment, opts) do
    Brando.Authorization.Operations.run(:promote, :environments, environment.site_id, opts, fn ->
      do_set_live(environment, opts)
    end)
  end

  defp do_set_live(%Environment{} = environment, opts) do
    case Registry.get_environment(environment.id) do
      %Environment{live: true} = current_environment ->
        {:ok, current_environment}

      %Environment{} = current_environment ->
        current_environment.site_id
        |> Registry.get_site()
        |> set_live_for_site(current_environment, opts)

      nil ->
        {:error, :environment_not_found}
    end
  end

  defp set_live_for_site(%Site{} = site, environment, opts) do
    case with_site_lock(site, fn -> set_current_environment_live(site, environment, opts) end) do
      {:ok, _live_environment} = result ->
        Cache.invalidate()
        announce(site.id)
        result

      {:error, _reason} = error ->
        error
    end
  end

  defp set_live_for_site(nil, _environment, _opts), do: {:error, :site_not_found}

  @doc """
  Archives the target schema, replaces it with a complete copy of the source,
  and restores the archive if copying fails.
  """
  @spec copy_environment(Environment.t(), Environment.t(), keyword()) ::
          {:ok, %{archive_schema: String.t(), target: Environment.t()}} | {:error, term()}
  def copy_environment(source, target, opts \\ [])

  def copy_environment(%Environment{id: id}, %Environment{id: id}, _opts),
    do: {:error, :same_environment}

  def copy_environment(%Environment{} = source, %Environment{} = target, opts) do
    Brando.Authorization.Operations.run(:promote, :environments, target.site_id, opts, fn ->
      do_copy_environment(source, target, opts)
    end)
  end

  defp do_copy_environment(%Environment{} = source, %Environment{} = target, opts) do
    with %Environment{} = current_source <- Registry.get_environment(source.id),
         %Environment{} = current_target <- Registry.get_environment(target.id),
         true <- current_source.site_id == current_target.site_id,
         %Site{} = site <- Registry.get_site(current_source.site_id) do
      with_site_lock(site, fn ->
        copy_under_lock(site, current_source, current_target, opts)
      end)
    else
      false -> {:error, :different_sites}
      nil -> {:error, :site_or_environment_not_found}
    end
  end

  @doc """
  Lists a site's most recent lifecycle operations, newest first.

  The log is the only place a `note` is ever recorded, so this is what makes
  those notes readable outside the database.
  """
  @spec list_operation_logs(Site.t(), pos_integer()) :: [OperationLog.t()]
  def list_operation_logs(%Site{} = site, limit \\ 10) do
    from(log in OperationLog,
      where: log.site_id == ^site.id,
      order_by: [desc: log.inserted_at, desc: log.id],
      limit: ^limit
    )
    |> Repo.all(@public_opts)
    |> Repo.preload([:source_environment, :target_environment, :creator], @public_opts)
    |> preload_creator_avatars()
  end

  # `User` is pinned to `public`, and Ecto preloads an association using the
  # parent struct's prefix — so `creator: :avatar` looks for the image in
  # `public.images`, where tenant-scoped images do not exist. The avatar
  # therefore has to be preloaded against the active tenant prefix explicitly.
  # Listings are unaffected because their parent entries are tenant-scoped.
  defp preload_creator_avatars(records) do
    case Tenant.current_prefix() do
      nil -> Repo.preload(records, creator: :avatar)
      prefix -> Repo.preload(records, [creator: :avatar], prefix: prefix)
    end
  rescue
    # An environment schema without an `images` table — mid-provision, or one
    # that never got structure — must not take an audit view down over a
    # decorative avatar. Drop to no avatar rather than leaving it unloaded,
    # which would fail in the template instead.
    _exception -> Enum.map(records, &drop_avatar/1)
  end

  defp drop_avatar(%{creator: %Brando.Users.User{} = creator} = record),
    do: %{record | creator: %{creator | avatar: nil}}

  defp drop_avatar(record), do: record

  @doc "Lists existing archive schemas for a site, newest first."
  @spec list_archives(Site.t()) :: [map()]
  def list_archives(%Site{} = site) do
    logs_by_schema =
      from(log in OperationLog,
        where:
          log.site_id == ^site.id and log.operation in [:copy, :set_live] and
            not is_nil(log.archive_schema),
        order_by: [desc: log.inserted_at, desc: log.id]
      )
      |> Repo.all(@public_opts)
      |> Repo.preload([:creator], @public_opts)
      |> preload_creator_avatars()
      |> Enum.reduce(%{}, fn log, logs -> Map.put_new(logs, log.archive_schema, log) end)

    pattern = "tenant_#{site.key}\\_%\\_archive\\_%"

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo.repo(),
        """
        SELECT nspname
        FROM pg_namespace
        WHERE nspname LIKE $1 ESCAPE '\\'
        ORDER BY nspname DESC
        """,
        [pattern]
      )

    rows
    |> Enum.map(fn [schema] ->
      log = logs_by_schema[schema]

      %{
        schema: schema,
        operation: log && log.operation,
        operation_log_id: log && log.id,
        created_at: log && log.inserted_at,
        note: log && log.note,
        creator: log && log.creator
      }
    end)
    |> Enum.sort_by(&archive_sort_key/1, :desc)
  end

  @doc "Drops old archive schemas, retaining the newest `keep` archives."
  @spec prune_archives(Site.t(), non_neg_integer()) :: {:ok, [String.t()]} | {:error, term()}
  def prune_archives(site, keep \\ @default_archive_keep)

  def prune_archives(%Site{} = site, keep) when is_integer(keep) and keep >= 0 do
    Brando.Authorization.Operations.run(:delete, :environments, site.id, [], fn ->
      with_site_lock(site, fn -> prune_archives_under_lock(site, keep) end)
    end)
  end

  def prune_archives(%Site{}, keep), do: {:error, {:invalid_keep, keep}}

  defp prune_archives_under_lock(site, keep) do
    site
    |> list_archives()
    |> Enum.drop(keep)
    |> Enum.reduce_while({:ok, []}, fn archive, {:ok, dropped} ->
      case Schema.drop(archive.schema) do
        :ok -> {:cont, {:ok, [archive.schema | dropped]}}
        {:error, reason} -> {:halt, {:error, {archive.schema, reason}}}
      end
    end)
    |> case do
      {:ok, dropped} -> {:ok, Enum.reverse(dropped)}
      error -> error
    end
  end

  @doc """
  Restores an archive as a new, non-live environment.

  Defaults to the newest archive. Pass `:archive_schema` to restore a specific
  one; it is resolved against this site's own archives, so a schema belonging to
  another site is rejected rather than restored.
  """
  @spec rollback(Site.t(), keyword()) :: {:ok, Environment.t()} | {:error, term()}
  def rollback(site, opts \\ [])

  def rollback(%Site{} = site, opts) do
    Brando.Authorization.Operations.run(:promote, :environments, site.id, opts, fn -> do_rollback(site, opts) end)
  end

  defp do_rollback(%Site{} = site, opts) do
    with_site_lock(site, fn ->
      case archive_to_restore(site, opts[:archive_schema]) do
        {:ok, archive} -> restore_archive(site, archive, opts)
        {:error, _reason} = error -> error
      end
    end)
  end

  defp archive_to_restore(site, nil) do
    case List.first(list_archives(site)) do
      nil -> {:error, :no_archives}
      archive -> {:ok, archive}
    end
  end

  defp archive_to_restore(site, archive_schema) when is_binary(archive_schema) do
    case Enum.find(list_archives(site), &(&1.schema == archive_schema)) do
      nil -> {:error, :archive_not_found}
      archive -> {:ok, archive}
    end
  end

  @doc "Schedules a copy operation through Oban."
  @spec schedule_copy(Environment.t(), Environment.t(), DateTime.t(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t() | term()}
  def schedule_copy(source, target, scheduled_at, opts \\ [])

  def schedule_copy(%Environment{} = source, %Environment{} = target, %DateTime{} = scheduled_at, opts) do
    Brando.Authorization.Operations.run(:promote, :environments, target.site_id, opts, fn ->
      do_schedule_copy(source, target, scheduled_at, opts)
    end)
  end

  def schedule_copy(%Environment{}, %Environment{}, scheduled_at, _opts),
    do: {:error, {:invalid_scheduled_at, scheduled_at}}

  defp do_schedule_copy(%Environment{} = source, %Environment{} = target, %DateTime{} = scheduled_at, opts) do
    if source.site_id == target.site_id and source.id != target.id do
      %{
        site_id: source.site_id,
        source_environment_id: source.id,
        target_environment_id: target.id,
        creator_id: creator_id(opts),
        note: opts[:note]
      }
      |> compact_job_args()
      |> EnvironmentCopy.new(scheduled_at: scheduled_at, tags: ["environment-operation"])
      |> Oban.insert()
    else
      {:error, :invalid_environment_pair}
    end
  end

  @doc "Schedules an environment to become live through Oban."
  @spec schedule_set_live(Environment.t(), DateTime.t(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t() | term()}
  def schedule_set_live(environment, scheduled_at, opts \\ [])

  def schedule_set_live(%Environment{} = environment, %DateTime{} = scheduled_at, opts) do
    Brando.Authorization.Operations.run(:promote, :environments, environment.site_id, opts, fn ->
      do_schedule_set_live(environment, scheduled_at, opts)
    end)
  end

  def schedule_set_live(%Environment{}, scheduled_at, _opts),
    do: {:error, {:invalid_scheduled_at, scheduled_at}}

  defp do_schedule_set_live(%Environment{} = environment, %DateTime{} = scheduled_at, opts) do
    %{
      site_id: environment.site_id,
      environment_id: environment.id,
      creator_id: creator_id(opts),
      note: opts[:note]
    }
    |> compact_job_args()
    |> EnvironmentSetLive.new(scheduled_at: scheduled_at, tags: ["environment-operation"])
    |> Oban.insert()
  end

  @doc "Lists pending copy/live-switch jobs for a site."
  @spec list_scheduled_operations(Site.t()) :: [Oban.Job.t()]
  def list_scheduled_operations(%Site{} = site) do
    workers = [Oban.Worker.to_string(EnvironmentCopy), Oban.Worker.to_string(EnvironmentSetLive)]
    states = ["available", "scheduled", "retryable", "executing"]
    site_id = to_string(site.id)

    from(job in Oban.Job,
      where:
        job.worker in ^workers and job.state in ^states and
          fragment("?->>'site_id' = ?", job.args, ^site_id),
      order_by: [asc: job.scheduled_at, asc: job.id]
    )
    |> Repo.all(@public_opts)
  end

  @doc "Cancels a pending environment operation after checking site ownership."
  @spec cancel_scheduled_operation(Site.t(), pos_integer()) :: :ok | {:error, term()}
  def cancel_scheduled_operation(%Site{} = site, job_id) do
    Brando.Authorization.Operations.run(:promote, :environments, site.id, [], fn ->
      do_cancel_scheduled_operation(site, job_id)
    end)
  end

  defp do_cancel_scheduled_operation(site, job_id) do
    case Repo.get(Oban.Job, job_id, @public_opts) do
      %Oban.Job{} = job ->
        if scheduled_environment_job?(job, site.id) do
          Oban.cancel_job(job)
        else
          {:error, :job_not_found}
        end

      nil ->
        {:error, :job_not_found}
    end
  end

  defp set_current_environment_live(site, environment, opts) do
    with {:ok, archive_prefix} <- archive_live_environment(site, environment.id),
         {:ok, live_environment} <-
           persist_live_switch(environment, archive_prefix, opts) do
      prune_archives_under_lock(site, opts[:keep_archives] || @default_archive_keep)
      {:ok, live_environment}
    end
  end

  defp persist_live_switch(environment, archive_prefix, opts) do
    Repo.transaction(fn ->
      from(candidate in Environment, where: candidate.site_id == ^environment.site_id)
      |> Repo.update_all([set: [live: false]], @public_opts)

      environment
      |> Environment.changeset(%{live: true})
      |> Repo.update(@public_opts)
      |> case do
        {:ok, live_environment} ->
          log_operation!(live_environment.site_id, :set_live,
            target_environment_id: live_environment.id,
            creator_id: creator_id(opts),
            archive_schema: archive_prefix,
            note: opts[:note]
          )

          live_environment

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp archive_live_environment(site, next_live_environment_id) do
    previous_live =
      site
      |> Registry.list_environments()
      |> Enum.find(&(&1.live and &1.id != next_live_environment_id))

    case previous_live do
      nil ->
        {:ok, nil}

      environment ->
        prefix = Tenant.prefix(site, environment)
        archive_prefix = next_archive_prefix(prefix)

        case schema_cloner().clone_schema(prefix, archive_prefix) do
          :ok -> {:ok, archive_prefix}
          {:error, reason} -> {:error, {:archive_failed, reason}}
        end
    end
  end

  defp copy_under_lock(site, source, target, opts) do
    source_prefix = Tenant.prefix(site, source)
    target_prefix = Tenant.prefix(site, target)
    archive_prefix = next_archive_prefix(target_prefix)

    with true <- Schema.exists?(source_prefix),
         true <- Schema.exists?(target_prefix),
         :ok <- schema_cloner().clone_schema(target_prefix, archive_prefix),
         :ok <- Schema.drop(target_prefix),
         :ok <- clone_with_recovery(source_prefix, target_prefix, archive_prefix) do
      log =
        log_operation!(site.id, :copy,
          source_environment_id: source.id,
          target_environment_id: target.id,
          creator_id: creator_id(opts),
          archive_schema: archive_prefix,
          note: opts[:note]
        )

      Cache.invalidate()
      announce(site.id)
      prune_archives_under_lock(site, opts[:keep_archives] || @default_archive_keep)

      {:ok, %{archive_schema: archive_prefix, operation_log: log, target: target}}
    else
      false -> {:error, :source_or_target_schema_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp clone_with_recovery(source_prefix, target_prefix, archive_prefix) do
    case schema_cloner().clone_schema(source_prefix, target_prefix) do
      :ok ->
        :ok

      {:error, copy_reason} ->
        Schema.drop(target_prefix)

        recovery = schema_cloner().clone_schema(archive_prefix, target_prefix)
        {:error, {:copy_failed, copy_reason, recovery}}
    end
  end

  defp delete_under_lock(site, environment_id, opts) do
    with %Environment{live: false} = environment <- Registry.get_environment(environment_id),
         prefix = Tenant.prefix(site, environment),
         :ok <- Schema.drop(prefix),
         {:ok, deleted_environment} <- Registry.delete_environment(environment) do
      log_operation!(site.id, :delete,
        creator_id: creator_id(opts),
        note: opts[:note] || "Deleted environment #{environment.key}"
      )

      {:ok, deleted_environment}
    else
      %Environment{live: true} -> {:error, :live_environment}
      nil -> {:error, :site_or_environment_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp restore_archive(site, archive, opts) do
    environment_key = next_rollback_key(site)

    attrs = %{
      name: "Rollback #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S")}",
      key: environment_key,
      live: false
    }

    with {:ok, environment} <- Registry.create_environment(site, attrs),
         prefix = Tenant.prefix(site, environment),
         :ok <- clone_archive_or_compensate(environment, archive.schema, prefix),
         {:ok, _versions} <- migrate_or_compensate(site, environment, prefix) do
      log_operation!(site.id, :rollback,
        target_environment_id: environment.id,
        creator_id: creator_id(opts),
        archive_schema: archive.schema,
        note: opts[:note]
      )

      Cache.invalidate()
      announce(site.id)
      {:ok, environment}
    end
  end

  defp clone_archive_or_compensate(environment, archive_prefix, target_prefix) do
    case schema_cloner().clone_schema(archive_prefix, target_prefix) do
      :ok ->
        :ok

      {:error, reason} ->
        Schema.drop(target_prefix)
        Registry.delete_environment(environment)
        {:error, {:archive_restore_failed, reason}}
    end
  end

  defp with_site_lock(site, fun) do
    repo = Repo.repo()
    lock_key = "brando:environment-operation:#{site.id}"

    repo.checkout(
      fn ->
        Ecto.Adapters.SQL.query!(
          repo,
          "SELECT pg_advisory_lock(hashtextextended($1, 0))",
          [lock_key]
        )

        try do
          fun.()
        after
          Ecto.Adapters.SQL.query!(
            repo,
            "SELECT pg_advisory_unlock(hashtextextended($1, 0))",
            [lock_key]
          )
        end
      end,
      timeout: :infinity
    )
  end

  defp next_archive_prefix(base_prefix, offset \\ 0) do
    timestamp = DateTime.utc_now() |> DateTime.add(offset, :second) |> Calendar.strftime("%Y%m%d%H%M%S")
    candidate = archive_prefix(base_prefix, timestamp)

    if Schema.exists?(candidate),
      do: next_archive_prefix(base_prefix, offset + 1),
      else: candidate
  end

  defp archive_prefix(base_prefix, timestamp) do
    full = "#{base_prefix}_archive_#{timestamp}"

    if byte_size(full) <= 63 do
      full
    else
      hash = :crypto.hash(:sha256, base_prefix) |> Base.encode16(case: :lower) |> binary_part(0, 8)
      truncated_base = binary_part(base_prefix, 0, 31)
      "#{truncated_base}_archive_#{timestamp}_#{hash}"
    end
  end

  defp archive_timestamp(schema) do
    case Regex.run(~r/_archive_(\d{14})(?:_[a-f0-9]{8})?$/, schema) do
      [_match, timestamp] -> timestamp
      _no_match -> ""
    end
  end

  defp archive_sort_key(archive) do
    {archive_timestamp(archive.schema), archive_created_at(archive.created_at), archive.schema}
  end

  defp archive_created_at(%DateTime{} = created_at),
    do: DateTime.to_unix(created_at, :microsecond)

  defp archive_created_at(_created_at), do: 0

  defp next_rollback_key(site, offset \\ 0) do
    seconds =
      Time.utc_now()
      |> Time.to_seconds_after_midnight()
      |> elem(0)
      |> Kernel.+(offset)
      |> rem(1_000_000)
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    key = "rollback-#{seconds}"

    if Registry.get_environment_by_key(site, key),
      do: next_rollback_key(site, offset + 1),
      else: key
  end

  defp creator_id(opts) do
    case opts[:creator] do
      %{id: id} -> id
      _ -> opts[:creator_id]
    end
  end

  defp compact_job_args(args) do
    Map.reject(args, fn {_key, value} -> is_nil(value) end)
  end

  defp scheduled_environment_job?(job, site_id) do
    job.worker in [
      Oban.Worker.to_string(EnvironmentCopy),
      Oban.Worker.to_string(EnvironmentSetLive)
    ] and
      to_string(job.args["site_id"]) == to_string(site_id) and
      job.state in ["available", "scheduled", "retryable", "executing"]
  end

  defp create_schema_or_compensate(environment, prefix) do
    case Schema.create(prefix) do
      :ok ->
        :ok

      {:error, reason} ->
        Registry.delete_environment(environment)
        {:error, {:schema_creation_failed, reason}}
    end
  end

  # Callers that immediately copy another environment over this one would only
  # throw the cloned structure away, because copying drops the target schema.
  defp clone_structure_or_compensate(environment, prefix, opts) do
    if Keyword.get(opts, :clone_structure, true),
      do: do_clone_structure(environment, prefix),
      else: :ok
  end

  defp do_clone_structure(environment, prefix) do
    case structure_cloner().clone_structure(@public_prefix, prefix) do
      :ok ->
        :ok

      {:error, reason} ->
        Schema.drop(prefix)
        Registry.delete_environment(environment)
        {:error, {:structure_clone_failed, reason}}
    end
  end

  defp migrate_or_compensate(site, environment, prefix) do
    case migrator().migrate(site, environment) do
      {:ok, versions} ->
        {:ok, versions}

      {:error, reason} ->
        Schema.drop(prefix)
        Registry.delete_environment(environment)
        {:error, {:migration_failed, reason}}
    end
  end

  defp migrate_environments(environments) do
    Enum.reduce_while(environments, {:ok, []}, fn environment, {:ok, migrated} ->
      case migrate(environment) do
        {:ok, versions} -> {:cont, {:ok, [{environment, versions} | migrated]}}
        {:error, reason} -> {:halt, {:error, {environment, reason}}}
      end
    end)
    |> case do
      {:ok, migrated} -> {:ok, Enum.reverse(migrated)}
      error -> error
    end
  end

  defp migrator do
    Brando.config(:tenant_migrator) || Brando.Environments.Migrator
  end

  defp structure_cloner do
    Brando.config(:tenant_structure_cloner) || Brando.Environments.StructureCloner.Postgres
  end

  defp schema_cloner do
    Brando.config(:environment_schema_cloner) || PostgresSchemaCloner
  end

  defp log_operation!(site_id, operation, attrs) do
    attrs = attrs |> Map.new() |> Map.merge(%{site_id: site_id, operation: operation})

    %OperationLog{}
    |> OperationLog.changeset(attrs)
    |> Repo.insert!(@public_opts)
  end
end
