defmodule Brando.Worker.NotificationDelivery do
  @moduledoc """
  Sends one notification (`Brando.Notifications.Routing`), in the site and
  environment it belongs to: posts it to the route's Slack or Teams webhook,
  or emails it to one of the route's recipients.

  Before each attempt the route must still be active and, for Slack and
  Teams, its URL must still resolve to public addresses only
  (`Brando.Webhooks.URLGuard`); an email recipient must still be active and
  allowed to read the entry. A failed attempt is retried with exponential
  backoff, 30 seconds doubling up to an hour, 10 attempts over about three
  hours; a test notification is tried once. When the last attempt fails, the
  delivery is marked failed, and a Slack or Teams route is paused.

  Its own failures are never notified as failed jobs, so a broken route
  cannot notify itself in a loop.
  """
  use Oban.Worker, queue: :webhooks, max_attempts: 10

  import Ecto.Query, only: [from: 2]

  alias Brando.Notifications.Delivery
  alias Brando.Notifications.Message
  alias Brando.Notifications.Recipient
  alias Brando.Notifications.Route
  alias Brando.Notifications.Routing
  alias Brando.Repo
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Webhooks.Client
  alias Brando.Webhooks.URLGuard

  require Logger

  @first_backoff 30
  @max_backoff 3600

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    TenantJob.run(job, fn -> deliver(job) end)
  rescue
    # Returned rather than raised: with Oban's inline testing mode the job
    # runs inside the save, which must not fail for it.
    error ->
      Logger.error("[Brando.Notifications] Delivery job #{job.id} crashed: " <> Exception.message(error))
      {:error, Exception.message(error)}
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    seconds = min(@first_backoff * Integer.pow(2, max(attempt - 1, 0)), @max_backoff)
    seconds + :rand.uniform(max(div(seconds, 10), 1))
  end

  @impl Oban.Worker
  def timeout(_job), do: Client.timeout() + 5_000

  @doc false
  def deliver(%Oban.Job{args: %{"delivery" => delivery_id, "route" => route_id}} = job) do
    with {:ok, delivery} <- load(delivery_id, route_id),
         :ok <- ensure_unfinished(delivery),
         {:ok, route} <- Routing.get_route(route_id),
         :ok <- ensure_active(route, delivery) do
      mark_sending(delivery)
      attempt(route, delivery, job)
    else
      {:error, :not_found} -> {:cancel, :not_found}
      {:cancel, _} = cancel -> cancel
    end
  end

  def deliver(_job), do: {:cancel, :invalid_arguments}

  defp load(delivery_id, route_id) do
    case Repo.get(Delivery, delivery_id) do
      %Delivery{route_id: ^route_id} = delivery -> {:ok, delivery}
      _ -> {:error, :not_found}
    end
  end

  defp ensure_unfinished(%Delivery{state: state}) when state in ["succeeded", "failed", "cancelled", "digest"],
    do: {:cancel, :already_finished}

  defp ensure_unfinished(_delivery), do: :ok

  defp ensure_active(%Route{active: true}, _delivery), do: :ok

  defp ensure_active(_route, delivery) do
    finish(delivery, %{state: "cancelled", error: "route_paused"})
    {:cancel, :route_paused}
  end

  defp mark_sending(delivery) do
    write(delivery, %{state: "sending", started_at: DateTime.utc_now()})
  end

  defp attempt(%Route{kind: :email} = route, delivery, job) do
    user = delivery.recipient_id && Repo.get(Brando.Users.User, delivery.recipient_id)

    if user && Recipient.may_see?(user, delivery) do
      started = System.monotonic_time(:millisecond)

      result =
        user
        |> Brando.Notifications.Email.single(delivery.notification)
        |> Brando.Mailer.deliver()

      duration = System.monotonic_time(:millisecond) - started

      case result do
        {:ok, _} ->
          record(%{status: nil, body: "", error: nil, duration_ms: duration, ok?: true}, route, delivery, job)

        {:error, reason} when reason in [:no_mailer, :no_sender] ->
          fail(route, delivery, %{status: nil, body: "", error: reason, duration_ms: duration}, final?: true)
          {:cancel, reason}

        {:error, reason} ->
          record(%{status: nil, body: "", error: mail_error(reason), duration_ms: duration}, route, delivery, job)
      end
    else
      finish(delivery, %{state: "cancelled", error: "recipient_unavailable"})
      {:cancel, :recipient_unavailable}
    end
  end

  defp attempt(%Route{kind: kind} = route, delivery, job) when kind in [:slack, :teams] do
    with {:ok, url} <- Routing.url(route),
         {:ok, target} <- URLGuard.resolve(url) do
      body = delivery.notification |> payload(kind) |> Jason.encode!()
      headers = [{"content-type", "application/json"}, {"user-agent", "Brando-Notifications"}]

      target
      |> Client.post(headers, body)
      |> Map.put(:ok?, false)
      |> record(route, delivery, job)
    else
      # The URL now points somewhere it may not, or cannot be read: trying
      # again won't help.
      {:error, reason} when reason in [:private_address, :https_required, :scheme_not_allowed, :url_unreadable] ->
        fail(route, delivery, %{status: nil, body: "", error: reason, duration_ms: 0}, final?: true)
        {:cancel, reason}

      {:error, reason} ->
        record(%{status: nil, body: "", error: reason, duration_ms: 0, ok?: false}, route, delivery, job)
    end
  end

  @doc "The request body for a Slack or Teams route."
  def payload(notification, :slack), do: Message.slack(notification)
  def payload(notification, :teams), do: Message.teams(notification)

  defp mail_error(reason), do: "mail: " <> String.slice(inspect(reason), 0, 200)

  defp record(%{ok?: true} = result, route, delivery, _job), do: succeed(result, route, delivery)

  defp record(%{status: status} = result, route, delivery, _job) when status in 200..299,
    do: succeed(result, route, delivery)

  defp record(result, route, delivery, job) do
    final? = delivery.test or job.attempt >= job.max_attempts
    fail(route, delivery, result, final?: final?)

    reason = if result.status, do: "HTTP #{result.status}", else: to_string(result.error)
    if final?, do: {:cancel, reason}, else: {:error, reason}
  end

  defp succeed(result, route, delivery) do
    finish(delivery, %{
      state: "succeeded",
      response_status: result.status,
      response_body: result.body,
      error: nil,
      duration_ms: result.duration_ms
    })

    update_route(route, last_delivery_at: DateTime.utc_now(), last_delivery_state: "succeeded", failing_since: nil)
    :ok
  end

  defp fail(route, delivery, result, final?: final?) do
    finish(delivery, %{
      state: if(final?, do: "failed", else: "retrying"),
      response_status: result.status,
      response_body: result.body,
      error: result.error && to_string(result.error),
      duration_ms: result.duration_ms
    })

    update_route(route,
      last_delivery_at: DateTime.utc_now(),
      last_delivery_state: "failed",
      failing_since: route.failing_since || DateTime.utc_now()
    )

    # A channel that failed every attempt: stop posting to it. One email
    # recipient's failure does not stop the others.
    if final? and not delivery.test and route.active and route.kind in [:slack, :teams],
      do: pause_after_failures(route)
  end

  defp pause_after_failures(route) do
    Logger.warning("[Brando.Notifications] Paused route ##{route.id} after its deliveries kept failing")
    Routing.pause(Repo.reload!(route), :failures, :system)
  rescue
    error -> Logger.error("[Brando.Notifications] Could not pause route ##{route.id}: " <> Exception.message(error))
  end

  # Records how an attempt went. Never raises: the message may already have
  # arrived, and a job that failed here would send it again.
  defp finish(delivery, changes) do
    changes =
      changes
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:attempts, delivery.attempts + if(changes.state == "cancelled", do: 0, else: 1))
      |> Map.update(:response_body, nil, &(&1 && Client.valid_text(&1)))

    with :error <- write(delivery, changes),
         :error <- write(delivery, Map.merge(changes, %{response_body: nil, error: "result_not_recorded"})) do
      Logger.error("[Brando.Notifications] Could not record delivery ##{delivery.id}")
    end

    safely(fn -> Routing.broadcast({:delivery, delivery.route_id}) end)
  end

  defp write(delivery, changes) do
    safely(fn -> Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: Map.to_list(changes)) end)
  end

  defp update_route(route, changes) do
    safely(fn -> Repo.update_all(from(r in Route, where: r.id == ^route.id), set: changes) end)
  end

  defp safely(fun) do
    fun.()
    :ok
  rescue
    error ->
      Logger.error("[Brando.Notifications] " <> Exception.message(error))
      :error
  end
end
