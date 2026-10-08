defmodule Brando.Worker.EntryPublisher do
  @moduledoc """
  Runs the jobs `Brando.Publisher` schedules: publishing an entry at its
  `publish_at`, deactivating it at its `unpublish_at`, and restoring and
  publishing a scheduled revision. Status changes go through the entry's
  context, like a change made by hand, so they record Activity and send their
  content events (webhooks, IndexNow, the search index) with the actor
  `"scheduler"`.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 10

  require Logger
  alias Brando.Revisions
  alias Brando.Tenant.Job, as: TenantJob

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

  # A publish waits for its publish_at and is dropped once the entry has
  # expired; an expiry waits for its unpublish_at and only ends an entry
  # that is published or about to be.
  defp due?(entry, "published", now),
    do: not after?(Map.get(entry, :publish_at), now) and not passed?(Map.get(entry, :unpublish_at), now)

  defp due?(entry, _status, now),
    do: passed?(Map.get(entry, :unpublish_at), now) and Map.get(entry, :status) in [:published, :pending]

  # Oban may run a job a moment before its time
  @slack_seconds 60

  defp after?(%DateTime{} = at, now), do: DateTime.diff(at, now) > @slack_seconds
  defp after?(_at, _now), do: false

  defp passed?(%DateTime{} = at, now), do: not after?(at, now)
  defp passed?(_at, _now), do: false

  defp update_status(schema_module, entry, status, user_id, now) do
    user = publisher_user(user_id)

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

      {:error, reason} ->
        {:error, reason}
    end
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
