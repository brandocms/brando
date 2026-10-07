defmodule Brando.Worker.ContentEventDispatcher do
  @moduledoc """
  Hands one content event to every subscriber (`Brando.ContentEvents`), in
  the site and environment it happened in, then broadcasts it on the
  environment's PubSub topic. A debounced `entry.updated` waits here, as a
  scheduled job, for more saves of the same entry.

  A subscriber that raises is logged and skipped; the job itself does not
  fail for it, so the other subscribers are not called twice.
  """
  use Oban.Worker, queue: :content_events, max_attempts: 3

  alias Brando.ContentEvents
  alias Brando.ContentEvents.Event
  alias Brando.Tenant.Job, as: TenantJob

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    TenantJob.run(job, fn ->
      case build(args) do
        {:ok, event} -> dispatch(event)
        :error -> {:cancel, :invalid_event}
      end
    end)
  rescue
    # Returned rather than raised: with Oban's inline testing mode the job
    # runs inside the save, which must not fail for it.
    error -> {:error, Exception.message(error)}
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @doc "Calls every subscriber with `event`, then broadcasts it."
  def dispatch(%Event{} = event) do
    Enum.each(ContentEvents.subscribers(), &call(&1, event))
    Phoenix.PubSub.broadcast(Brando.pubsub(), ContentEvents.topic(), {:content_event, event})
    :ok
  end

  defp call(subscriber, event) do
    subscriber.handle_event(event)
  rescue
    error ->
      Logger.error(
        "[Brando.ContentEvents] #{inspect(subscriber)} failed on #{event.type} #{event.id}: " <>
          Exception.message(error)
      )
  end

  @doc """
  The event from the job's arguments. The URL is looked up now, after the
  save has committed, unless it was taken before the entry was deleted.
  """
  def build(%{"id" => id, "type" => type, "schema" => schema_name} = args) do
    schema = schema(schema_name)
    {site, environment} = site_and_environment()

    {:ok,
     %Event{
       id: id,
       type: type,
       occurred_at: occurred_at(args["occurred_at"]),
       site: site,
       environment: environment,
       schema: schema,
       entry_type: Event.entry_type(schema),
       entry_id: args["entry_id"],
       language: args["language"],
       status: args["status"],
       url: Map.get_lazy(args, "url", fn -> url(schema, args["entry_id"]) end),
       changed_fields: args["fields"] || [],
       actor: args["actor"] || "system"
     }}
  end

  def build(_args), do: :error

  defp schema(name) do
    module = String.to_existing_atom(name)
    if Code.ensure_loaded?(module), do: module
  rescue
    ArgumentError -> nil
  end

  defp occurred_at(nil), do: DateTime.utc_now()

  defp occurred_at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp url(nil, _id), do: nil
  defp url(_schema, nil), do: nil

  defp url(schema, id) do
    case Brando.Repo.get(schema, id, ContentEvents.savepoint()) do
      nil -> nil
      entry -> ContentEvents.entry_url(entry)
    end
  rescue
    _ -> nil
  end

  @doc """
  The site and environment keys of the current tenant prefix. Without
  tenancy there is one site, named by `:site_key` (or the application),
  and no environment.
  """
  def site_and_environment do
    case Brando.Tenant.current_prefix() do
      "tenant_" <> rest ->
        case String.split(rest, "_", parts: 2) do
          [site, environment] -> {site, environment}
          _ -> {rest, nil}
        end

      _ ->
        {Brando.config(:site_key) || to_string(Brando.otp_app()), nil}
    end
  end
end
