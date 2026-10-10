defmodule Brando.Publisher do
  @moduledoc """
  Helpers for scheduling and publishing content.
  """
  import Ecto.Query

  require Logger

  alias Brando.Authorization.Boundary
  alias Brando.Blueprint.Identifier
  alias Brando.Repo
  alias Brando.Revisions
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Users.User
  alias Brando.Worker
  alias Ecto.Changeset

  @publish_status "published"
  @unpublish_status "disabled"

  @type entry :: map()
  @type changeset :: Changeset.t()
  @type user :: User.t()

  @doc """
  Create jobs for the publisher worker when the changeset changed the entry's
  `publish_at` or `unpublish_at`: one that publishes the entry at
  `publish_at`, and one that deactivates it at `unpublish_at`. A date that
  changed replaces the entry's earlier job for it, whoever scheduled that one;
  a date cleared or moved into the past cancels it.
  """
  @spec schedule_publishing(entry, changeset, user) :: {:ok, entry}
  def schedule_publishing(entry, changeset, user) do
    {:ok, entry} = schedule_publish(entry, changeset, user)
    schedule_unpublish(entry, changeset, user)
  end

  # Any change to publish_at drops the entry's earlier publishing job, a date
  # cleared or moved into the past included; only a future date queues one.
  defp schedule_publish(%{id: id, __struct__: schema} = entry, %{changes: %{publish_at: _}}, user) do
    delete_status_jobs(schema, id, @publish_status)

    with %DateTime{} = publish_at <- Map.get(entry, :publish_at),
         true <- DateTime.after?(publish_at, DateTime.utc_now()) do
      %{schema: schema, id: id, user_id: user_id(user), status: :published}
      |> TenantJob.attach()
      |> Worker.EntryPublisher.new(
        replace_args: true,
        scheduled_at: publish_at,
        tags: [:publisher, :status],
        meta: %{identifier: job_identifier(Identifier.identifier_for(entry)), at: publish_at}
      )
      |> Oban.insert()
    end

    {:ok, entry}
  end

  defp schedule_publish(entry, _, _), do: {:ok, entry}

  defp schedule_unpublish(%{id: id, __struct__: schema} = entry, %{changes: %{unpublish_at: _}}, user) do
    delete_status_jobs(schema, id, @unpublish_status)

    case Map.get(entry, :unpublish_at) do
      %DateTime{} = unpublish_at ->
        if DateTime.after?(unpublish_at, DateTime.utc_now()) do
          %{schema: schema, id: id, user_id: user_id(user), status: @unpublish_status}
          |> TenantJob.attach()
          |> Worker.EntryPublisher.new(
            scheduled_at: unpublish_at,
            tags: [:publisher, :unpublish],
            meta: %{identifier: job_identifier(Identifier.identifier_for(entry)), at: unpublish_at}
          )
          |> Oban.insert()
        end

      nil ->
        :ok
    end

    {:ok, entry}
  end

  defp schedule_unpublish(entry, _, _), do: {:ok, entry}

  # The entry's jobs that set `status`, by anyone, except one that is running:
  # it checks the entry's dates itself.
  defp delete_status_jobs(schema, id, status) do
    args = Map.merge(%{"schema" => to_string(schema), "id" => id, "status" => status}, TenantJob.context_fragment())

    Repo.delete_all(
      from j in Oban.Job,
        where:
          j.worker == ^inspect(Worker.EntryPublisher) and
            j.state != "executing" and
            fragment("? @> ?", j.args, ^args)
    )
  end

  @doc "The status an entry gets when its `unpublish_at` passes."
  def unpublish_status, do: String.to_existing_atom(@unpublish_status)

  @doc "Whether `job` deactivates an entry at its `unpublish_at`."
  def unpublish_job?(%Oban.Job{args: %{"status" => @unpublish_status}}), do: true
  def unpublish_job?(_job), do: false

  @doc "Schedule a historical revision for restoration and publication."
  def schedule_revision(schema, id, revision_number, publish_at, user) do
    with :ok <- Boundary.authorize(user, :schedule, schema_module(schema)),
         :ok <- Boundary.authorize(user, :publish, schema_module(schema)),
         {:ok, id} <- cast_entry_id(id),
         {:ok, revision_number} <- cast_revision_number(revision_number),
         {:ok, publish_at} <- parse_future_datetime(publish_at) do
      schema = schema_module(schema)

      Boundary.run(user, :schedule, schema, fn user ->
        schedule_authorized_revision(schema, id, revision_number, publish_at, user)
      end)
    end
  end

  defp schedule_authorized_revision(schema, id, revision_number, publish_at, user) do
    with :ok <- Boundary.authorize_record(user, :publish, schema, id),
         :ok <- Boundary.authorize_record(user, :schedule, schema, id),
         do: schedule_valid_revision(schema, id, revision_number, publish_at, user)
  end

  defp schedule_valid_revision(schema, id, revision_number, publish_at, user) do
    Repo.transaction(fn ->
      lock_entry!(schema, id)

      with {:ok, {revision, {_, decoded_entry}}} <-
             Revisions.get_revision(schema, id, revision_number),
           false <- revision.active,
           :ok <- cancel_revision_job(schema, id, revision_number),
           {1, _} <- Revisions.mark_revision_scheduled(schema, id, revision_number, true),
           args =
             TenantJob.attach(%{
               schema: to_string(schema),
               id: id,
               revision: revision_number,
               user_id: user_id(user)
             }),
           revision_identifier =
             decoded_entry
             |> Identifier.identifier_for()
             |> maybe_add_revision_description(revision),
           {:ok, job} <- insert_revision_job(args, publish_at, revision_identifier) do
        job
      else
        true -> Repo.rollback(:revision_already_active)
        {0, _} -> Repo.rollback(:revision_not_found)
        :error -> Repo.rollback(:revision_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_revision_job(args, publish_at, revision_identifier) do
    args
    |> Worker.EntryPublisher.new(
      scheduled_at: publish_at,
      tags: [:publisher, :revision],
      meta: %{identifier: job_identifier(revision_identifier)},
      unique: [
        fields: [:worker, :args],
        keys: [:tenant_prefix, :schema, :id, :revision],
        period: :infinity,
        states: :incomplete
      ]
    )
    |> Oban.insert()
  end

  @doc "Cancel one scheduled revision and make it eligible for retention again."
  def cancel_scheduled_revision(schema, id, revision_number) do
    with {:ok, id} <- cast_entry_id(id),
         {:ok, revision_number} <- cast_revision_number(revision_number),
         :ok <- Boundary.admin_record(:schedule, schema_module(schema), id) do
      cancel_valid_scheduled_revision(schema_module(schema), id, revision_number)
    end
  end

  defp cancel_valid_scheduled_revision(schema, id, revision_number) do
    case Repo.transaction(fn ->
           lock_entry!(schema, id)
           :ok = cancel_revision_job(schema, id, revision_number)
           Revisions.mark_revision_scheduled(schema, id, revision_number, false)
           :ok
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Cancel all revision publishing jobs for an entry."
  def cancel_revision_jobs(schema, id) do
    schema = to_string(schema)
    args = Map.merge(%{"schema" => schema, "id" => id}, TenantJob.context_fragment())

    from(j in Oban.Job,
      where:
        j.worker == ^inspect(Worker.EntryPublisher) and
          j.state in ["available", "scheduled", "executing", "retryable"] and
          fragment("? @> ?", j.args, ^args)
    )
    |> Oban.cancel_all_jobs()

    :ok
  end

  defp cancel_revision_job(schema, id, revision_number) do
    schema = to_string(schema)

    args =
      Map.merge(
        %{"schema" => schema, "id" => id, "revision" => revision_number},
        TenantJob.context_fragment()
      )

    from(j in Oban.Job,
      where:
        j.worker == ^inspect(Worker.EntryPublisher) and
          j.state in ["available", "scheduled", "executing", "retryable"] and
          fragment("? @> ?", j.args, ^args)
    )
    |> Oban.cancel_all_jobs()

    :ok
  end

  defp lock_entry!(schema, id) do
    query = from(entry in schema, where: entry.id == ^id, select: entry.id, lock: "FOR UPDATE")

    case Repo.one(query) do
      nil -> Repo.rollback(:entry_not_found)
      _entry_id -> :ok
    end
  end

  defp schema_module(schema) when is_atom(schema), do: schema
  defp schema_module(schema) when is_binary(schema), do: Brando.Authorization.Catalog.schema(schema)

  defp maybe_add_revision_description(nil, _revision), do: nil
  defp maybe_add_revision_description(identifier, %{description: nil}), do: identifier
  defp maybe_add_revision_description(identifier, %{description: ""}), do: identifier

  defp maybe_add_revision_description(identifier, %{description: description}),
    do: Map.update!(identifier, :title, &"#{&1} (#{description})")

  defp job_identifier(nil), do: nil

  defp job_identifier(%_{} = identifier) do
    identifier
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp job_identifier(identifier), do: identifier

  @doc """
  Adjust the status for the dates the changeset sets: a pending entry whose
  `publish_at` is cleared or has passed is published, a future `publish_at`
  makes a published entry pending, and an `unpublish_at` set to a time that
  has passed deactivates a published or pending entry at once.
  """
  def maybe_override_status(changeset) do
    changeset
    |> override_for_publish_at()
    |> override_for_unpublish_at()
  end

  # if we have no publish_at but status = pending -- set status published
  defp override_for_publish_at(%{changes: %{publish_at: nil}} = changeset) do
    status = Changeset.get_field(changeset, :status)

    if status == :pending do
      Changeset.put_change(changeset, :status, :published)
    else
      changeset
    end
  end

  defp override_for_publish_at(%{changes: %{publish_at: publish_at}} = changeset) when not is_nil(publish_at) do
    status = Changeset.get_field(changeset, :status)

    if DateTime.after?(publish_at, DateTime.utc_now()) do
      if status in [:pending, :published] do
        Changeset.put_change(changeset, :status, :pending)
      else
        changeset
      end
    else
      # publish date has passed - if it is still pending, set it to published
      if status == :pending do
        Changeset.put_change(changeset, :status, :published)
      else
        changeset
      end
    end
  end

  defp override_for_publish_at(changeset) do
    changeset
  end

  defp override_for_unpublish_at(%{changes: %{unpublish_at: %DateTime{} = unpublish_at}} = changeset) do
    if DateTime.after?(unpublish_at, DateTime.utc_now()) or
         Changeset.get_field(changeset, :status) not in [:published, :pending] do
      changeset
    else
      Changeset.put_change(changeset, :status, unpublish_status())
    end
  end

  defp override_for_unpublish_at(changeset), do: changeset

  @waiting_states ~w(available scheduled executing retryable)

  @doc """
  The publisher's jobs that have yet to run (or are running) in the current
  environment, by time, filtered in the query.

  Options: `:kinds`, any of `:publish`, `:unpublish` and `:revision` (all
  by default); `:from` and `:to`, a window on `scheduled_at` (`to` not
  included).

  Unlike `list_jobs/0` it checks no permissions: callers load the entries and
  check those, as `BrandoAdmin.Schedule` and the dashboard do.
  """
  def waiting_jobs(opts \\ []) do
    kinds = Keyword.get(opts, :kinds, [:publish, :unpublish, :revision])
    context = TenantJob.context_fragment()

    query =
      from j in Oban.Job,
        where:
          j.worker == ^inspect(Worker.EntryPublisher) and j.state in @waiting_states and
            fragment("? @> ?", j.args, ^context),
        order_by: [asc: j.scheduled_at, asc: j.id]

    query
    |> where_kinds(kinds)
    |> where_window(Keyword.get(opts, :from), Keyword.get(opts, :to))
    |> Repo.all()
  end

  defp where_kinds(query, kinds) do
    kind =
      Enum.reduce(kinds, dynamic(false), fn
        :publish, acc -> dynamic([j], ^acc or fragment("?->>'status' = ?", j.args, @publish_status))
        :unpublish, acc -> dynamic([j], ^acc or fragment("?->>'status' = ?", j.args, @unpublish_status))
        :revision, acc -> dynamic([j], ^acc or fragment("? \\? 'revision'", j.args))
      end)

    from j in query, where: ^kind
  end

  defp where_window(query, nil, nil), do: query
  defp where_window(query, from, nil), do: from(j in query, where: j.scheduled_at >= ^from)
  defp where_window(query, nil, to), do: from(j in query, where: j.scheduled_at < ^to)
  defp where_window(query, from, to), do: from(j in query, where: j.scheduled_at >= ^from and j.scheduled_at < ^to)

  @sweep_grace_seconds 300
  @sweep_days 7
  @failed_ttl :timer.hours(24)

  @doc """
  Catch up on dates no job will act on, in the current environment: publish
  pending entries whose `publish_at` has passed, and deactivate published or
  pending entries whose `unpublish_at` has passed, through each entry's
  context like the jobs do. Dates arrive without jobs when an environment is
  cloned or an archive restored, and a lost job leaves one behind. With
  group authorization, a publication whose job is still waiting, running or
  retrying (made for that date, or with its time come) is left to the job,
  which runs as the user who scheduled it; a job that user may no longer
  carry out clears its date (see `Brando.Worker.EntryPublisher`).

    * Only dates from more than five minutes ago, so the jobs run first, and
      from the last seven days (`config :brando, Brando.Publisher,
      sweep_days: 7`), so older dates, from before the sweep existed, are
      left alone.
    * An entry it has handled no longer matches, so running it again does
      nothing. With group authorization, one that changed after it was found
      (its job refused the date, or an editor saved it) is left out. Pages and fragments index
      both dates, and the window keeps each query to a few days of them.
    * A content type whose table cannot be read (an environment whose
      migrations lag) is logged and skipped. An entry whose save fails is
      logged and left alone for a day, or until it is saved again.

  Returns what it did, one map per entry: `%{schema, id, title, action,
  at, result}`, `action` being `:publish` or `:unpublish` and `result`
  `:ok`, `{:error, reason}` or, with `dry_run: true`, `:dry_run` (nothing is
  saved). `Brando.Worker.ScheduledPublishingSweep` runs it every ten minutes
  in every active environment; `mix brando.scheduled_publishing.sweep` shows
  what it would do.
  """
  def sweep(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    dry_run? = Keyword.get(opts, :dry_run, false)
    window = {DateTime.add(now, -sweep_days(), :day), DateTime.add(now, -@sweep_grace_seconds)}

    Brando.Activity.with_source(:scheduler, fn ->
      Enum.flat_map(sweepable_schemas(), &sweep_schema(&1, window, now, dry_run?))
    end)
  end

  defp sweep_days do
    config = Brando.config(__MODULE__) || []
    Keyword.get(config, :sweep_days, @sweep_days)
  end

  defp sweep_schema(schema, {from, before}, now, dry_run?) do
    due(schema, :publish_at, [:pending], from, before)
    |> Enum.concat(due(schema, :unpublish_at, [:published, :pending], from, before))
    |> Enum.uniq_by(& &1.id)
    |> Enum.reject(&failed_before?(schema, &1))
    |> Enum.map(&{&1, sweep_action(&1, now)})
    |> without_waiting_job(schema, now)
    |> Enum.map(fn {entry, action} -> sweep_entry(schema, entry, action, dry_run?) end)
    |> Enum.reject(&(&1.result == :changed))
  rescue
    error ->
      Logger.error(
        "[Brando.Publisher] sweep skipped #{inspect(schema)} in #{Brando.Tenant.current_prefix() || "public"}: " <>
          Exception.message(error)
      )

      []
  end

  @doc "Content types with dates to keep: the trait, a status and a context."
  def sweepable_schemas do
    :include_brando
    |> Brando.Blueprint.list_blueprints()
    |> Enum.uniq()
    |> Enum.filter(fn schema ->
      function_exported?(schema, :has_trait, 1) and schema.has_trait(Brando.Trait.ScheduledPublishing) and
        :status in schema.__schema__(:fields) and function_exported?(schema, :__modules__, 0)
    end)
  end

  defp due(schema, field, statuses, from, before) do
    query =
      from e in schema,
        where: e.status in ^statuses and field(e, ^field) >= ^from and field(e, ^field) <= ^before,
        order_by: [asc: e.id]

    query =
      if :deleted_at in schema.__schema__(:fields), do: from(e in query, where: is_nil(e.deleted_at)), else: query

    Repo.all(query)
  end

  # With group authorization a publication's job runs as the user who
  # scheduled it and refuses what they may no longer do, so a publication
  # whose job is still to run, running or retrying is left to the job: one
  # made for the entry's date or with its time come, while one waiting for a
  # later date the entry had before (an archive restored) does not hold it
  # up. An expiry is carried out even when its user is refused, and does not
  # wait; nor does anything without group authorization.
  defp without_waiting_job(due, schema, now) do
    ids = for {entry, :publish} <- due, do: to_string(entry.id)

    if ids == [] or not Brando.Authorization.Engine.enabled?() do
      due
    else
      waiting = waiting_publications(schema, ids)

      Enum.reject(due, fn {entry, action} -> action == :publish and Enum.any?(waiting, &holds?(&1, entry, now)) end)
    end
  end

  defp holds?(job, entry, now) do
    job.id == to_string(entry.id) and
      (made_for?(job.at, entry.publish_at) or not DateTime.after?(job.scheduled_at, now))
  end

  defp waiting_publications(schema, ids) do
    args =
      Map.merge(%{"schema" => to_string(schema), "status" => @publish_status}, TenantJob.context_fragment())

    Repo.all(
      from j in Oban.Job,
        where:
          j.worker == ^inspect(Worker.EntryPublisher) and j.state in @waiting_states and
            fragment("? @> ?", j.args, ^args) and fragment("?->>'id'", j.args) in ^ids,
        select: %{id: fragment("?->>'id'", j.args), at: fragment("?->>'at'", j.meta), scheduled_at: j.scheduled_at}
    )
  end

  defp made_for?(at, %DateTime{} = date) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, made_for, _} -> same_second?(made_for, date)
      _ -> false
    end
  end

  defp made_for?(_at, _date), do: false

  # An expiry that has passed wins over a publish that has
  defp sweep_action(entry, now) do
    expired? = match?(%DateTime{}, Map.get(entry, :unpublish_at)) and not DateTime.after?(entry.unpublish_at, now)
    if expired?, do: :unpublish, else: :publish
  end

  defp sweep_entry(schema, entry, action, dry_run?) do
    found = %{
      schema: schema,
      id: entry.id,
      title: Map.get(entry, :title) || Map.get(entry, :name),
      action: action,
      at: if(action == :unpublish, do: entry.unpublish_at, else: entry.publish_at)
    }

    Map.put(found, :result, if(dry_run?, do: :dry_run, else: save_sweep(schema, entry, action)))
  end

  defp save_sweep(schema, entry, action) do
    params = %{status: if(action == :unpublish, do: @unpublish_status, else: @publish_status)}
    context = schema.__modules__().context
    update = :"update_#{schema.__naming__().singular}"

    save = fn -> apply(context, update, [entry.id, params, :system]) end

    # With group authorization a job may refuse the date and take it back
    # while the sweep runs: the entry is locked and checked again. The save
    # evicts the entry's cached queries before the commit, so again after it.
    result =
      if Brando.Authorization.Engine.enabled?(),
        do: Repo.transaction(fn -> if still_due?(schema, entry, action), do: save.(), else: :changed end),
        else: {:ok, save.()}

    case result do
      {:ok, :changed} ->
        :changed

      {:ok, {:ok, _}} ->
        Brando.Cache.Query.evict(entry)
        :ok

      {:ok, error} ->
        sweep_failed(schema, entry, action, error)

      error ->
        sweep_failed(schema, entry, action, error)
    end
  rescue
    error ->
      Logger.warning(
        "[Brando.Publisher] sweep could not #{action} #{inspect(schema)} ##{entry.id}: #{Exception.message(error)}"
      )

      Brando.Cache.put(failed_key(schema, entry), true, @failed_ttl)
      {:error, error}
  end

  # The entry still has the status and date the sweep found, out of the
  # trash: a job that refused its date, or an editor, may have changed it
  # since. Locked until it is saved.
  defp still_due?(schema, entry, action) do
    {field, statuses} =
      if action == :unpublish, do: {:unpublish_at, [:published, :pending]}, else: {:publish_at, [:pending]}

    case Repo.one(from e in schema, where: e.id == ^entry.id, lock: "FOR UPDATE") do
      nil ->
        false

      current ->
        current.status in statuses and Map.get(current, field) == Map.get(entry, field) and
          is_nil(Map.get(current, :deleted_at))
    end
  end

  defp sweep_failed(schema, entry, action, error) do
    Logger.warning(
      "[Brando.Publisher] sweep could not #{action} #{inspect(schema)} ##{entry.id}, " <>
        "left alone for a day or until it is saved: #{inspect(sweep_error(error))}"
    )

    Brando.Cache.put(failed_key(schema, entry), true, @failed_ttl)
    {:error, sweep_error(error)}
  end

  defp sweep_error({:error, %Changeset{errors: errors}}), do: errors
  defp sweep_error({:error, reason}), do: reason
  defp sweep_error(other), do: other

  # Saving the entry changes updated_at, and with it the key: it is tried again
  defp failed_key(schema, entry), do: {:publisher_sweep_failed, schema, entry.id, Map.get(entry, :updated_at)}
  defp failed_before?(schema, entry), do: Brando.Cache.get(failed_key(schema, entry)) == true

  def list_jobs do
    context = TenantJob.context_fragment()

    query =
      from j in Oban.Job,
        where: "publisher" in j.tags and fragment("? @> ?", j.args, ^context),
        order_by: j.scheduled_at

    jobs = Repo.all(query)

    jobs =
      if Brando.Authorization.enabled?() and Boundary.current_scope(),
        do: Enum.filter(jobs, &(job_authorized?(&1, :read) == :ok)),
        else: jobs

    {:ok, jobs}
  end

  @doc """
  Delete a publisher job, and with it the plan it carried out, so nothing
  publishes the entry later (`sweep/1` would publish a pending entry whose
  `publish_at` passed with no job): a publishing job clears the entry's
  `publish_at` and sets a pending entry back to draft, an expiry job clears
  `unpublish_at`, and a revision job makes the revision an ordinary one again.
  The entry is saved through its context as `user`, so it records Activity;
  a date that no longer matches the job (it was moved since) is left alone,
  as is an entry in the trash. Needs the right to schedule the entry, and to
  change the date the rights a save of it takes.
  """
  def delete_job(id, user \\ :system) do
    context = TenantJob.context_fragment()

    with {:ok, id} <- cast_entry_id(id),
         %Oban.Job{} = job <- Repo.get(Oban.Job, id),
         true <- map_size(context) == 0 or Map.take(job.args, Map.keys(context)) == context,
         :ok <- job_authorized?(job, :schedule),
         :ok <- clear_job_date(job, user),
         :ok <- Oban.cancel_job(job) do
      clear_revision_schedule(job)
      Repo.delete_all(from j in Oban.Job, where: j.id == ^id)
    else
      nil -> {0, nil}
      false -> {0, nil}
      {:error, _reason} = error -> error
    end
  end

  defp clear_job_date(%Oban.Job{args: %{"status" => status, "schema" => name, "id" => id}} = job, user) do
    field = if status == @publish_status, do: :publish_at, else: :unpublish_at
    schema = schema_module(name)

    with schema when not is_nil(schema) <- schema,
         %{} = entry <- Repo.get(schema, id),
         nil <- Map.get(entry, :deleted_at),
         %DateTime{} = at <- Map.get(entry, field),
         true <- job_for_date?(job, at) do
      params = %{field => nil}
      params = if field == :publish_at and entry.status == :pending, do: Map.put(params, :status, :draft), else: params
      context = schema.__modules__().context

      case apply(context, :"update_#{schema.__naming__().singular}", [entry.id, params, user]) do
        {:ok, _} -> :ok
        {:error, _} = error -> error
      end
    else
      _ -> :ok
    end
  end

  defp clear_job_date(_job, _user), do: :ok

  # The date the job was made for. A failed attempt moves scheduled_at to the
  # retry, so it is kept in meta; a job from before that compares
  # scheduled_at until its first retry, and is taken as the entry's after.
  defp job_for_date?(%Oban.Job{meta: %{"at" => made_for}}, at) when is_binary(made_for) do
    case DateTime.from_iso8601(made_for) do
      {:ok, made_for, _} -> same_second?(made_for, at)
      _ -> true
    end
  end

  defp job_for_date?(%Oban.Job{attempt: 0, scheduled_at: scheduled_at}, at), do: same_second?(scheduled_at, at)
  defp job_for_date?(_job, _at), do: true

  defp same_second?(a, b), do: DateTime.compare(DateTime.truncate(a, :second), DateTime.truncate(b, :second)) == :eq

  defp job_authorized?(%Oban.Job{worker: worker, args: %{"schema" => schema, "id" => id}}, action) do
    if worker == inspect(Worker.EntryPublisher),
      do: Boundary.admin_record(action, schema_module(schema), id),
      else: {:error, :forbidden}
  end

  defp job_authorized?(_, _), do: {:error, :forbidden}

  defp clear_revision_schedule(%Oban.Job{
         args: %{"schema" => schema, "id" => id, "revision" => revision_number}
       }) do
    Revisions.mark_revision_scheduled(schema_module(schema), id, revision_number, false)
  end

  defp clear_revision_schedule(_job), do: :ok

  defp parse_future_datetime(%DateTime{} = datetime) do
    if DateTime.after?(datetime, DateTime.utc_now()) do
      {:ok, datetime}
    else
      {:error, :publish_at_must_be_in_the_future}
    end
  end

  defp parse_future_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed, _offset} -> parse_future_datetime(parsed)
      {:error, _reason} -> {:error, :invalid_publish_at}
    end
  end

  defp parse_future_datetime(_datetime), do: {:error, :invalid_publish_at}

  defp cast_revision_number(revision) when is_integer(revision), do: {:ok, revision}

  defp cast_revision_number(revision) when is_binary(revision) do
    case Integer.parse(revision) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_revision}
    end
  end

  defp cast_revision_number(_revision), do: {:error, :invalid_revision}

  defp cast_entry_id(id) when is_integer(id), do: {:ok, id}

  defp cast_entry_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_entry_id}
    end
  end

  defp cast_entry_id(_id), do: {:error, :invalid_entry_id}

  defp user_id(:system), do: nil
  defp user_id(%{id: id}), do: id
end
