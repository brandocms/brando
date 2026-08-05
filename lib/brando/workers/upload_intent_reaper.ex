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
  use Oban.Worker, queue: :default, max_attempts: 2

  alias Brando.Uploads

  require Logger

  # Comfortably past both the presigned URL's lifetime (10 minutes) and any
  # plausible slow transfer, so a large upload in progress is never reaped out
  # from under itself.
  @stale_after_hours 24

  @impl Oban.Worker
  def perform(_job) do
    stale = Uploads.list_stale_pending_intents(@stale_after_hours)

    reaped = Enum.count(stale, &reap/1)

    if reaped > 0 do
      Logger.info("==> [CRON] Reaped #{reaped} abandoned client-direct upload(s)")
    end

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  defp reap(intent) do
    delete_object(intent)
    Uploads.delete_pending_intent(intent)
    true
  end

  defp delete_object(intent) do
    case Uploads.delete_direct_object(intent.asset_type, intent.resolved_target, intent.key) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "==> [CRON] UploadIntentReaper: could not delete #{intent.key} " <>
            "(#{intent.asset_type}): #{inspect(reason)}"
        )

        :error
    end
  end
end
