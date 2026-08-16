defmodule Brando.Worker.UploadIntentReaper do
  @moduledoc """
  Removes the bucket objects of client-direct uploads that never finalized.

  A `Brando.Uploads.PendingIntent` is written when the server presigns a PUT
  and deleted when the browser reports back — on success, error, or cancel. An
  intent that is still here hours later means the browser stopped talking: a
  closed tab, a lost network, a crash mid-transfer. The presigned URL expired
  long ago, so nothing can complete it, and what may be sitting in the bucket
  is an object with no asset row pointing at it — invisible to the library and
  to every existing cleanup path, which all start from a row.

  So unlike `Brando.Worker.VideoUploadReaper` — which deliberately does NOT
  delete, because a provider webhook can still arrive for a row it reaped —
  this one deletes for real, in both places. There is no third party here: the
  only actor that could still have completed this upload is a browser holding
  an expired URL.

  Deleting the object is best effort. A bucket that refuses (permissions, a key
  that was never written because the transfer died before its first byte) still
  gets its intent row dropped — leaving the row would just make the sweep retry
  the same failure nightly, and the row is not what makes the object findable.
  """
  use Oban.Worker, queue: :upload_reaping, max_attempts: 2

  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Uploads

  require Logger

  # Comfortably past both the presigned URL's lifetime (10 minutes) and any
  # plausible slow transfer, so a large upload in progress is never reaped out
  # from under itself.
  @stale_after_hours 24

  # One sweep drains at most this many. A backlog is spread over successive
  # runs rather than held in a single long job — this worker shares its queue
  # with nothing, but it still does one network round trip per row and an
  # unbounded list would sit inside the timeout below.
  @batch_size 500

  @impl Oban.Worker
  def perform(_job) do
    errors =
      TenantJob.each_active_environment(:all, &reap_current_environment/0)
      |> Enum.reject(&(&1 == :ok))

    case errors do
      [] -> :ok
      [{:error, reason}] -> {:error, reason}
      multiple -> {:error, multiple}
    end
  end

  defp reap_current_environment do
    stale = Uploads.list_stale_pending_intents(@stale_after_hours, @batch_size)

    {reaped, failed} = Enum.split_with(stale, &(reap(&1) == :ok))

    if reaped != [] do
      Logger.info("==> [CRON] Reaped #{length(reaped)} abandoned client-direct upload(s)")
    end

    if length(stale) == @batch_size do
      Logger.info("==> [CRON] UploadIntentReaper hit its batch size; more remain for the next run")
    end

    report(failed)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  # Returning :ok unconditionally made `max_attempts` dead code for the one
  # failure this worker exists to handle. Rows that could not be reaped are
  # still here, so a retry (and the next nightly run) picks up exactly those —
  # the successful ones are gone and cannot be re-deleted.
  defp report([]), do: :ok

  defp report(failed) do
    {:error, "could not delete #{length(failed)} abandoned upload object(s); intents retained"}
  end

  defp reap(intent) do
    case delete_object(intent) do
      :ok ->
        Uploads.delete_pending_intent(intent)
        :ok

      :error ->
        # Keep the row. Dropping it was the original behaviour and it destroyed
        # the only durable record that an orphaned object exists — the object
        # has no asset row, so nothing else in the system can find it again.
        # A persistent failure re-reporting nightly is the correct signal, not
        # noise to be silenced by forgetting the evidence.
        :error
    end
  end

  defp delete_object(intent) do
    case Uploads.delete_direct_object(intent.asset_type, intent.resolved_target, intent.key) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "==> [CRON] UploadIntentReaper: could not delete #{intent.key} " <>
            "(#{intent.asset_type}): #{inspect(reason)} — intent kept for retry"
        )

        :error
    end
  end
end
