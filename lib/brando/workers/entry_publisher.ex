defmodule Brando.Worker.EntryPublisher do
  @moduledoc """
  Runs the jobs `Brando.Publisher` schedules: publishing an entry at its
  `publish_at`, deactivating it at its `unpublish_at`, and restoring and
  publishing a scheduled revision. Status changes go through the entry's
  context, like a change made by hand, so they record Activity and send their
  content events (webhooks, IndexNow, the search index) with the actor
  `"scheduler"`.

  A publication or expiry runs as the user who scheduled it. With group
  authorization, when that user may no longer make the change (a grant or a
  record policy), or their account is deactivated or deleted, a
  publication's job is cancelled rather than retried, and its date cleared
  (the pending entry goes back to draft) so that `Brando.Publisher.sweep/1`
  does not carry it out instead. An expiry still deactivates the entry on
  time, as the system. Activity records why. While the site is suspended
  the job waits, spending no attempts; a refusal for any other reason is
  retried, and taken back on the last attempt. Without group authorization,
  schedules run as they always have.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 10

  require Logger
  alias Brando.Authorization.Boundary
  alias Brando.Authorization.Engine
  alias Brando.Repo
  alias Brando.Revisions
  alias Brando.Tenant.Job, as: TenantJob

  # Why a user's authorization refuses them for want of a grant
  @grant_denials [:missing_grant, :backend_access_required]

  # A refusal for the scope that passes when the site is active again: the
  # job waits, without spending its attempts, for as long as it takes
  @temporary_denials [:inactive_site]
  @suspended_snooze_seconds 600

  # schedule publishing/depublishing an entry
  @impl Oban.Worker
  def perform(%Oban.Job{} = job),
    do: TenantJob.run(job, fn -> Brando.Activity.with_source(:scheduler, fn -> perform_tenant(job) end) end)

  defp perform_tenant(
         %Oban.Job{
           args: %{
             "schema" => schema,
             "id" => id,
             "revision" => revision,
             "user_id" => user_id
           }
         } = job
       ) do
    if current_revision_job?(job),
      do: publish_revision(job, schema, id, revision, user_id),
      else: :ok
  end

  # Publish an entry at its publish_at, or deactivate it at its unpublish_at,
  # through the context's update like a status change made by hand. A job
  # whose date has since moved (the entry was rescheduled after it was
  # queued) or that no longer applies does nothing.
  defp perform_tenant(
         %Oban.Job{
           args: %{
             "schema" => schema,
             "id" => id,
             "status" => status,
             "user_id" => user_id
           }
         } = job
       ) do
    schema_module = Module.concat(List.wrap(schema))
    now = DateTime.utc_now()

    case Repo.get(schema_module, id) do
      nil ->
        :ok

      %{deleted_at: %DateTime{}} ->
        :ok

      entry ->
        if due?(entry, status, now),
          do: update_status(job, schema_module, entry, status, user_id, now),
          else: :ok
    end
  end

  # A scheduled revision's time is its job's: moving it (in the revisions
  # drawer or the calendar) cancels the job and queues another. A job that
  # is no longer the revision's one waiting job, or whose time has not come,
  # is stale and does nothing, so it cannot publish early. A job built
  # without a row (a test, a manual run) has nothing to compare with.
  defp current_revision_job?(%Oban.Job{id: nil}), do: true

  defp current_revision_job?(%Oban.Job{id: job_id, args: args, scheduled_at: scheduled_at}) do
    import Ecto.Query, only: [from: 2]

    # Whoever scheduled it: a move by another user replaces it too
    match = Map.drop(args, ["user_id"])

    waiting =
      Repo.all(
        from j in Oban.Job,
          where:
            j.worker == ^inspect(__MODULE__) and j.state in ["available", "scheduled", "executing", "retryable"] and
              fragment("? @> ?", j.args, ^match),
          select: j.id
      )

    waiting == [job_id] and not after?(scheduled_at, DateTime.utc_now())
  end

  defp publish_revision(job, schema, id, revision, user_id) do
    user = publisher_user(user_id)
    now = DateTime.utc_now()

    single =
      schema
      |> String.split(".")
      |> List.last()
      |> String.downcase()

    schema = Module.concat(List.wrap(schema))

    case Revisions.set_entry_to_revision(schema, id, revision, user, publish?: true) do
      {:ok, new_entry} ->
        Logger.info("""

        ==> [B/Pub] Published revision ##{revision} of #{single} ##{id}
        ==> [B/Pub] @ #{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second} UTC
        """)

        BrandoAdmin.LiveView.Listing.update_list_entries(schema)
        {:ok, new_entry}

      {:error, reason} ->
        release_failed_revision_schedule(job, schema, id, revision)
        {:error, reason}
    end
  end

  # A publish waits for its publish_at, publishes only a pending entry (one
  # set back to draft stays a draft) and is dropped once the entry has
  # expired; an expiry waits for its unpublish_at and only ends an entry that
  # is published or about to be.
  defp due?(entry, "published", now),
    do:
      Map.get(entry, :status) == :pending and not after?(Map.get(entry, :publish_at), now) and
        not passed?(Map.get(entry, :unpublish_at), now)

  defp due?(entry, _status, now),
    do: passed?(Map.get(entry, :unpublish_at), now) and Map.get(entry, :status) in [:published, :pending]

  # Oban may run a job a moment before its time
  @slack_seconds 60

  defp after?(%DateTime{} = at, now), do: DateTime.diff(at, now) > @slack_seconds
  defp after?(_at, _now), do: false

  defp passed?(%DateTime{} = at, now), do: not after?(at, now)
  defp passed?(_at, _now), do: false

  defp update_status(job, schema_module, entry, status, user_id, now) do
    case scheduler(user_id) do
      {:ok, user} -> save_status(job, schema_module, entry, status, user, user_id, now)
      {:error, reason} -> refuse(schema_module, entry, status, user_id, reason)
    end
  end

  defp save_status(job, schema_module, entry, status, user, user_id, now) do
    params =
      if status == "published",
        do: %{creator_id: user_id, status: status, publish_at: now},
        else: %{status: status}

    context = schema_module.__modules__().context
    singular = schema_module.__naming__().singular

    case apply(context, :"update_#{singular}", [entry.id, params, user]) do
      {:ok, _} ->
        Logger.info("""

        ==> [B/Pub] #{(status == "published" && "Published") || "Depublished"} #{singular} ##{entry.id}
        ==> [B/Pub] @ #{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second} UTC
        """)

        BrandoAdmin.LiveView.Listing.update_list_entries(schema_module)
        :ok

      {:error, reason} = error when reason == :forbidden or (is_tuple(reason) and elem(reason, 1) == :not_found) ->
        refused(job, error, schema_module, entry, status, user, user_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A save its user is refused (a record policy may hide the entry from them
  # instead, so it is not found), with group authorization. Refused for want
  # of a grant or by a record policy, it is taken back at once. For a
  # suspended site it waits, spending no attempts. For any other reason it is
  # tried again, and taken back on its last attempt: a job that ran out of
  # attempts must not leave the date for the sweep to carry out as the system.
  defp refused(job, error, schema_module, entry, status, user, user_id) do
    case refusal(user, schema_module, entry, status) do
      :retry ->
        error

      :temporary ->
        {:snooze, @suspended_snooze_seconds}

      {:refused, reason} ->
        refuse(schema_module, entry, status, user_id, reason)

      {:unexplained, reason} ->
        if last_attempt?(job), do: refuse(schema_module, entry, status, user_id, reason), else: error
    end
  end

  defp refusal(:system, _schema_module, _entry, _status), do: :retry

  defp refusal(user, schema_module, entry, status) do
    if Engine.enabled?(), do: classify(user, schema_module, entry, status), else: :retry
  end

  # A publication sets publish_at, which takes the right to schedule as well
  defp classify(user, schema_module, entry, status) do
    snapshot = user |> Boundary.actor_scope() |> Engine.snapshot()
    actions = if status == "published", do: [:update, :publish, :schedule], else: [:update, :publish]

    cond do
      snapshot.reason in @temporary_denials -> :temporary
      not is_nil(snapshot.reason) -> {:unexplained, snapshot.reason}
      denial = Enum.find_value(actions, &denial(snapshot, &1, schema_module, entry)) -> {:refused, denial}
      true -> {:unexplained, :forbidden}
    end
  end

  defp denial(snapshot, action, schema_module, entry) do
    reason = Engine.explain(snapshot, action, schema_module).reason || Engine.explain(snapshot, action, entry).reason

    cond do
      reason in @grant_denials -> :forbidden
      reason == :policy_denied -> :policy_denied
      true -> nil
    end
  end

  defp last_attempt?(%Oban.Job{attempt: attempt, max_attempts: max}) when is_integer(attempt) and is_integer(max),
    do: attempt >= max

  defp last_attempt?(_job), do: false

  # Who a job runs as: the user who scheduled it, or the system for a
  # schedule made without a user. With group authorization the user's
  # account must be active, and a user who is gone is never replaced by the
  # system; without it, the job runs as whoever it finds, as it always has.
  defp scheduler(nil), do: {:ok, :system}

  defp scheduler(user_id) do
    case {Engine.enabled?(), Brando.Users.get_user(user_id)} do
      {false, {:ok, user}} -> {:ok, user}
      {false, _} -> {:ok, nil}
      {true, {:ok, %{active: true, deleted_at: nil} = user}} -> {:ok, user}
      {true, {:ok, _user}} -> {:error, :scheduler_inactive}
      {true, _} -> {:error, :scheduler_missing}
    end
  end

  # The user who scheduled an expiry may no longer make it, or is gone: it
  # is carried out all the same, as the system, so that a refusal never
  # leaves an entry live for longer than planned. Activity says why.
  defp refuse(schema_module, entry, "disabled" = status, user_id, reason) do
    details = %{"schedule_refused" => %{"action" => "unpublish", "reason" => to_string(reason)}}
    context = schema_module.__modules__().context
    singular = schema_module.__naming__().singular

    Logger.warning(
      "[B/Pub] User ##{user_id} may no longer deactivate #{singular} ##{entry.id} (#{reason}): " <>
        "deactivating it as the system"
    )

    expire = fn -> apply(context, :"update_#{singular}", [entry.id, %{status: status}, :system]) end

    result =
      Repo.transaction(fn ->
        if still_due?(schema_module, entry, status), do: with_details(details, expire), else: :changed
      end)

    case result do
      {:ok, {:error, reason}} ->
        {:error, reason}

      {:ok, _} ->
        # The save evicted the entry's cached queries before the commit
        Brando.Cache.Query.evict(entry)
        BrandoAdmin.LiveView.Listing.update_list_entries(schema_module)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The user who scheduled a publication may no longer make it, or is gone,
  # so no one will: trying again would not help, and the sweep would carry
  # out the date as the system. The job is cancelled and the date cleared,
  # the entry going back to draft, as deleting the job does, and Activity
  # says why. Saved as the system, which only takes back the plan.
  defp refuse(schema_module, entry, status, user_id, reason) do
    params = %{status: :draft, publish_at: nil}
    details = %{"schedule_refused" => %{"action" => "publish", "reason" => to_string(reason)}}
    singular = schema_module.__naming__().singular

    Logger.warning(
      "[B/Pub] Did not publish #{singular} ##{entry.id} as scheduled by user ##{user_id} (#{reason}): " <>
        "cancelling the job and clearing the date"
    )

    result =
      Repo.transaction(fn ->
        if still_due?(schema_module, entry, status), do: clear_date(schema_module, entry, params, details)
      end)

    case result do
      {:ok, _} ->
        # The save evicted the entry's cached queries before the commit
        Brando.Cache.Query.evict(entry)
        BrandoAdmin.LiveView.Listing.update_list_entries(schema_module)
        {:cancel, reason}

      {:error, error} ->
        {:error, error}
    end
  end

  # The entry is still due, with the date the job read, out of the trash: an
  # editor may have moved the date, or published or unpublished it by hand,
  # since. Locked until it is saved.
  defp still_due?(schema_module, entry, status) do
    import Ecto.Query, only: [from: 2]

    {field, statuses} =
      if status == "published", do: {:publish_at, [:pending]}, else: {:unpublish_at, [:published, :pending]}

    query = from e in schema_module, where: e.id == ^entry.id, lock: "FOR UPDATE"

    case Repo.one(query) do
      nil ->
        false

      current ->
        current.status in statuses and Map.get(current, field) == Map.get(entry, field) and
          is_nil(Map.get(current, :deleted_at))
    end
  end

  defp with_details(details, fun), do: Brando.Activity.with_source(:scheduler, details, fun)

  defp clear_date(schema_module, entry, params, details) do
    context = schema_module.__modules__().context
    update = :"update_#{schema_module.__naming__().singular}"

    case with_details(details, fn -> apply(context, update, [entry.id, params, :system]) end) do
      {:ok, _} -> :ok
      {:error, error} -> clear_refused(schema_module, entry, params, details, error)
    end
  end

  # An entry its context will not save (it no longer validates) still loses
  # the date, so the sweep does not carry it out.
  defp clear_refused(schema_module, entry, params, details, error) do
    import Ecto.Query, only: [from: 2]

    Logger.warning("[B/Pub] Could not save #{inspect(schema_module)} ##{entry.id}, clearing its date: #{inspect(error)}")

    Repo.update_all(from(e in schema_module, where: e.id == ^entry.id), set: Map.to_list(params))

    # What a save does that readers see: the entry's identifier, its cached
    # queries, and Activity with its content event, as the entry is now
    case Repo.get(schema_module, entry.id) do
      nil -> :ok
      updated -> after_clearing(schema_module, updated, params, details)
    end
  end

  defp after_clearing(schema_module, updated, params, details) do
    Brando.Content.update_identifier(schema_module, updated)
    Repo.after_commit(fn -> Brando.Cache.Query.evict(updated) end)

    if Brando.Activity.logged?(schema_module) do
      fields = params |> Map.keys() |> Enum.map(&to_string/1)
      Brando.Activity.record(:updated, updated, :system, fields: fields, details: details)
    end

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  defp publisher_user(nil), do: :system

  defp publisher_user(user_id) do
    case Brando.Users.get_user(user_id) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp release_failed_revision_schedule(
         %Oban.Job{attempt: attempt, max_attempts: max_attempts},
         schema,
         id,
         revision
       )
       when is_integer(attempt) and is_integer(max_attempts) and attempt >= max_attempts do
    Revisions.mark_revision_scheduled(schema, id, revision, false)
  end

  defp release_failed_revision_schedule(_job, _schema, _id, _revision), do: :ok
end
