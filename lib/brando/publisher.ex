defmodule Brando.Publisher do
  @moduledoc """
  Helpers for scheduling and publishing content.
  """
  import Ecto.Query

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
        meta: %{identifier: job_identifier(Identifier.identifier_for(entry))}
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
            meta: %{identifier: job_identifier(Identifier.identifier_for(entry))}
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

  @doc """
  Catch up on dates no job will act on, in the current environment: publish
  pending entries whose `publish_at` has passed, and deactivate published or
  pending entries whose `unpublish_at` has passed, through each entry's
  context like the jobs do. Dates arrive without jobs when an environment is
  cloned or an archive restored, and a lost job leaves one behind. Only dates
  more than five minutes old are taken, so the jobs run first; an entry it
  has handled no longer matches, so running it again does nothing. Both
  dates are indexed. Returns how many entries it changed.

  `Brando.Worker.ScheduledPublishingSweep` runs it every ten minutes in every
  active environment.
  """
  def sweep(now \\ DateTime.utc_now()) do
    before = DateTime.add(now, -@sweep_grace_seconds)

    Brando.Activity.with_source(:scheduler, fn ->
      sweepable_schemas()
      |> Enum.map(fn schema ->
        due(schema, :publish_at, [:pending], before)
        |> Enum.concat(due(schema, :unpublish_at, [:published, :pending], before))
        |> Enum.uniq_by(& &1.id)
        |> Enum.count(&(sweep_entry(schema, &1, now) == :ok))
      end)
      |> Enum.sum()
    end)
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

  defp due(schema, field, statuses, before) do
    query = from e in schema, where: e.status in ^statuses and field(e, ^field) <= ^before

    query =
      if :deleted_at in schema.__schema__(:fields), do: from(e in query, where: is_nil(e.deleted_at)), else: query

    Repo.all(query)
  end

  # An expiry that has passed wins over a publish that has
  defp sweep_entry(schema, entry, now) do
    expired? = match?(%DateTime{}, Map.get(entry, :unpublish_at)) and not DateTime.after?(entry.unpublish_at, now)
    params = %{status: if(expired?, do: @unpublish_status, else: @publish_status)}
    context = schema.__modules__().context

    case apply(context, :"update_#{schema.__naming__().singular}", [entry.id, params, :system]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

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

  def delete_job(id) do
    context = TenantJob.context_fragment()

    with {:ok, id} <- cast_entry_id(id),
         %Oban.Job{} = job <- Repo.get(Oban.Job, id),
         true <- map_size(context) == 0 or Map.take(job.args, Map.keys(context)) == context,
         :ok <- job_authorized?(job, :schedule),
         :ok <- Oban.cancel_job(job) do
      clear_revision_schedule(job)
      Repo.delete_all(from j in Oban.Job, where: j.id == ^id)
    else
      nil -> {0, nil}
      false -> {0, nil}
      {:error, _reason} = error -> error
    end
  end

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
