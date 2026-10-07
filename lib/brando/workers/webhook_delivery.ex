defmodule Brando.Worker.WebhookDelivery do
  @moduledoc """
  Sends one webhook delivery (`Brando.Webhooks`), in the site and
  environment it belongs to.

  Before each attempt the webhook must still be active, a slot must be free
  (at most `Brando.Webhooks.concurrency/0` deliveries to one webhook at a
  time; otherwise the job waits five seconds without using an attempt), and
  the URL must still resolve to public addresses only. The request is
  signed when it is sent, over the exact body.

  A failed attempt is retried with exponential backoff: 30 seconds, then
  doubling up to four hours between attempts, 15 attempts over about 24
  hours. When the last one fails, the delivery is marked failed and the
  webhook paused. A test event is tried once.
  """
  use Oban.Worker, queue: :webhooks, max_attempts: 15

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Webhooks
  alias Brando.Webhooks.Client
  alias Brando.Webhooks.Delivery
  alias Brando.Webhooks.Signature
  alias Brando.Webhooks.URLGuard
  alias Brando.Webhooks.Webhook

  require Logger

  @first_backoff 30
  @max_backoff 4 * 3600
  @busy_snooze 5

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    TenantJob.run(job, fn -> deliver(job) end)
  rescue
    # Returned rather than raised: with Oban's inline testing mode the job
    # runs inside the save, which must not fail for it.
    error -> {:error, Exception.message(error)}
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    seconds = min(@first_backoff * Integer.pow(2, max(attempt - 1, 0)), @max_backoff)
    seconds + :rand.uniform(max(div(seconds, 10), 1))
  end

  @impl Oban.Worker
  def timeout(_job), do: Client.timeout() + 5_000

  @doc false
  def deliver(%Oban.Job{args: %{"delivery" => delivery_id, "webhook" => webhook_id}} = job) do
    with {:ok, delivery} <- load(delivery_id, webhook_id),
         {:ok, webhook} <- Webhooks.get_webhook(webhook_id),
         :ok <- ensure_active(webhook, delivery),
         :claimed <- claim(webhook, delivery) do
      attempt(webhook, delivery, job)
    else
      :busy -> {:snooze, @busy_snooze}
      {:error, :not_found} -> {:cancel, :not_found}
      {:cancel, _} = cancel -> cancel
    end
  end

  def deliver(_job), do: {:cancel, :invalid_arguments}

  defp load(delivery_id, webhook_id) do
    case Repo.get(Delivery, delivery_id) do
      %Delivery{webhook_id: ^webhook_id} = delivery -> {:ok, delivery}
      _ -> {:error, :not_found}
    end
  end

  defp ensure_active(%Webhook{active: true}, _delivery), do: :ok

  defp ensure_active(_webhook, delivery) do
    finish(delivery, %{state: "cancelled", error: "webhook_paused"})
    {:cancel, :webhook_paused}
  end

  # A slot among the webhook's concurrent deliveries. "sending" rows older
  # than the timeout are from an attempt that never finished and don't count.
  defp claim(webhook, delivery) do
    cutoff = DateTime.add(DateTime.utc_now(), -(Client.timeout() + 5_000), :millisecond)
    key = "brando:webhook:#{Brando.Tenant.current_prefix() || "public"}:#{webhook.id}"

    {:ok, result} =
      Repo.transaction(fn ->
        Repo.repo().query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

        busy =
          Repo.aggregate(
            from(d in Delivery,
              where:
                d.webhook_id == ^webhook.id and d.id != ^delivery.id and d.state == "sending" and
                  d.started_at > ^cutoff
            ),
            :count
          )

        if busy >= Webhooks.concurrency() do
          :busy
        else
          Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id),
            set: [state: "sending", started_at: DateTime.utc_now()]
          )

          :claimed
        end
      end)

    result
  end

  defp attempt(webhook, delivery, job) do
    with {:ok, secret} <- Webhooks.secret(webhook),
         {:ok, target} <- URLGuard.resolve(webhook.url) do
      body = Jason.encode!(delivery.payload)
      timestamp = System.system_time(:second)

      headers = [
        {"content-type", "application/json"},
        {"user-agent", "Brando-Webhooks"},
        {"brando-event", delivery.event},
        {"brando-delivery", delivery.delivery_id},
        {"brando-signature", Signature.header(secret, timestamp, body)}
      ]

      target
      |> Client.post(headers, body)
      |> record(webhook, delivery, job)
    else
      # The URL now points somewhere a webhook may not call, or the secret
      # cannot be read: trying again won't help.
      {:error, reason} when reason in [:private_address, :https_required, :scheme_not_allowed, :secret_unreadable] ->
        fail(webhook, delivery, %{status: nil, body: "", error: reason, duration_ms: 0}, job, final?: true)
        {:cancel, reason}

      {:error, reason} ->
        record(%{status: nil, body: "", error: reason, duration_ms: 0}, webhook, delivery, job)
    end
  end

  defp record(%{status: status} = result, webhook, delivery, _job) when status in 200..299 do
    finish(delivery, %{
      state: "succeeded",
      response_status: status,
      response_body: result.body,
      error: nil,
      duration_ms: result.duration_ms
    })

    update_webhook(webhook, last_delivery_at: DateTime.utc_now(), last_delivery_state: "succeeded", failing_since: nil)
    :ok
  end

  defp record(result, webhook, delivery, job) do
    final? = delivery.test or job.attempt >= job.max_attempts
    fail(webhook, delivery, result, job, final?: final?)

    reason = if result.status, do: "HTTP #{result.status}", else: to_string(result.error)
    if final?, do: {:cancel, reason}, else: {:error, reason}
  end

  defp fail(webhook, delivery, result, _job, final?: final?) do
    finish(delivery, %{
      state: if(final?, do: "failed", else: "retrying"),
      response_status: result.status,
      response_body: result.body,
      error: result.error && to_string(result.error),
      duration_ms: result.duration_ms
    })

    update_webhook(webhook,
      last_delivery_at: DateTime.utc_now(),
      last_delivery_state: "failed",
      failing_since: webhook.failing_since || DateTime.utc_now()
    )

    # A delivery that failed every attempt, about a day: stop calling it.
    if final? and not delivery.test and webhook.active do
      Logger.warning("[Brando.Webhooks] Paused webhook ##{webhook.id} after its deliveries kept failing")
      Webhooks.pause(Repo.reload!(webhook), :failures, :system)
    end
  end

  defp finish(delivery, changes) do
    changes =
      changes
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:attempts, delivery.attempts + if(changes.state == "cancelled", do: 0, else: 1))

    Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: Map.to_list(changes))
    Webhooks.broadcast({:delivery, delivery.webhook_id})
  end

  defp update_webhook(webhook, changes) do
    Repo.update_all(from(w in Webhook, where: w.id == ^webhook.id), set: changes)
  end
end
