defmodule Brando.Worker.EntryPublisher do
  @moduledoc """
  Runs the jobs `Brando.Publisher` schedules: publishing an entry at its
  `publish_at`, deactivating it at its `unpublish_at`, and restoring and
  publishing a scheduled revision. Status changes go through the entry's
  context, like a change made by hand, so they record Activity and send their
  content events (webhooks, IndexNow, the search index) with the actor
  `"scheduler"`.

  A publication or expiry runs as the user who scheduled it. When that user
  may no longer make the change, or their account is deactivated or deleted,
  the job is cancelled rather than retried, and the date it was for is
  cleared (a pending entry goes back to draft) so that
  `Brando.Publisher.sweep/1` does not carry it out instead. Activity records
  why.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 10

  require Logger
  alias Brando.Revisions
  alias Brando.Tenant.Job, as: TenantJob

  # A schedule its user may no longer carry out, or whose user is gone
  @refusals [:forbidden, :scheduler_missing, :scheduler_inactive]

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
  defp perform_tenant(%Oban.Job{
         args: %{
           "schema" => schema,
           "id" => id,
           "status" => status,
           "user_id" => user_id
         }
       }) do
    schema_module = Module.concat(List.wrap(schema))
    now = DateTime.utc_now()

    case Brando.Repo.get(schema_module, id) do
      nil ->
        :ok

      %{deleted_at: %DateTime{}} ->
        :ok

      entry ->
        if due?(entry, status, now),
          do: update_status(schema_module, entry, status, user_id, now),
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
      Brando.Repo.all(
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

  defp update_status(schema_module, entry, status, user_id, now) do
    params =
      if status == "published",
        do: %{creator_id: user_id, status: status, publish_at: now},
        else: %{status: status}

    context = schema_module.__modules__().context
    singular = schema_module.__naming__().singular

    with {:ok, user} <- scheduler(user_id),
         {:ok, _} <- apply(context, :"update_#{singular}", [entry.id, params, user]) do
      Logger.info("""

      ==> [B/Pub] #{(status == "published" && "Published") || "Depublished"} #{singular} ##{entry.id}
      ==> [B/Pub] @ #{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second} UTC
      """)

      BrandoAdmin.LiveView.Listing.update_list_entries(schema_module)

      :ok
    else
      {:error, reason} when reason in @refusals -> refuse(schema_module, entry, status, user_id, reason)
      {:error, reason} -> {:error, reason}
    end
  end

  # Who a job runs as: the user who scheduled it, while their account is
  # active, or the system for a schedule made without a user. A user who is
  # gone is never replaced by the system.
  defp scheduler(nil), do: {:ok, :system}

  defp scheduler(user_id) do
    case Brando.Users.get_user(user_id) do
      {:ok, %{active: true, deleted_at: nil} = user} -> {:ok, user}
      {:ok, _user} -> {:error, :scheduler_inactive}
      _ -> {:error, :scheduler_missing}
    end
  end

  # The user who scheduled the change may no longer make it, or is gone, so
  # no one will: trying again would not help, and the sweep would carry out
  # the date as the system. The job is cancelled and the date cleared, a
  # publication's entry going back to draft, as deleting the job does, and
  # Activity says why. Saved as the system, which only takes back the plan.
  defp refuse(schema_module, entry, status, user_id, reason) do
    {params, action} =
      if status == "published",
        do: {%{status: :draft, publish_at: nil}, "publish"},
        else: {%{unpublish_at: nil}, "unpublish"}

    details = %{"schedule_refused" => %{"action" => action, "reason" => to_string(reason)}}
    context = schema_module.__modules__().context
    singular = schema_module.__naming__().singular

    Logger.warning(
      "[B/Pub] Did not #{action} #{singular} ##{entry.id} as scheduled by user ##{user_id} (#{reason}): " <>
        "the job is cancelled and its date cleared"
    )

    Brando.Activity.with_source(:scheduler, details, fn ->
      case apply(context, :"update_#{singular}", [entry.id, params, :system]) do
        {:ok, _} -> :ok
        {:error, error} -> clear_refused(schema_module, entry, params, details, error)
      end
    end)

    BrandoAdmin.LiveView.Listing.update_list_entries(schema_module)
    {:cancel, reason}
  end

  # An entry its context will not save (it no longer validates) still loses
  # the date, so the sweep does not carry it out.
  defp clear_refused(schema_module, entry, params, details, error) do
    import Ecto.Query, only: [from: 2]

    Logger.warning("[B/Pub] Could not save #{inspect(schema_module)} ##{entry.id}, clearing its date: #{inspect(error)}")

    Brando.Repo.update_all(from(e in schema_module, where: e.id == ^entry.id), set: Map.to_list(params))

    if Brando.Activity.logged?(schema_module) do
      fields = params |> Map.keys() |> Enum.map(&to_string/1)
      Brando.Activity.record(:updated, entry, :system, fields: fields, details: details)
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
