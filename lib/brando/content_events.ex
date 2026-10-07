defmodule Brando.ContentEvents do
  @moduledoc """
  Content events: one normalised message for each change to an entry, for
  anything outside the save that has to react to it — outbound webhooks
  (`Brando.Webhooks`) today, IndexNow and the search index next.

  ## Events

  | Event | When |
  | --- | --- |
  | `entry.created` | An entry was created, duplicated or imported as new. |
  | `entry.updated` | An entry was saved with changes, a revision was restored, or an import changed it. |
  | `entry.published` | An entry became published: from the form, a listing, scheduled publishing, or created as published (after its `entry.created`). |
  | `entry.unpublished` | A published entry got another status. |
  | `entry.deleted` | An entry was moved to the trash or deleted for good. Emptying the trash later sends nothing more. |
  | `entry.restored` | An entry came back from the trash. |

  Each one is a `Brando.ContentEvents.Event`: the site and environment, the
  entry's type, id, language, URL and status, the names (not the values) of
  the fields that changed, what kind of actor made the change, and when.

  ## Where they come from

  Events are derived from `Brando.Activity`: every change Activity records
  for a Blueprint entry becomes an event, so the contexts need no hooks of
  their own. A schema Activity does not log (its `ignore` list, media,
  Brando's internal records, users) sends no events either. Scheduled
  publishing records `:published` like a manual publish, with the actor
  `"scheduler"`.

  ## Delivery

  The save inserts an Oban job (`Brando.Worker.ContentEventDispatcher`, on
  the `:content_events` queue); the job hands the event to each subscriber.
  Oban was chosen over PubSub alone because:

    * the job is inserted in the save's transaction, so it exists only once
      that transaction commits, and a rolled-back save sends nothing;
    * it outlives the request and the node: a restart or a deploy does not
      lose events;
    * debouncing is a scheduled job that later saves update.

  Enqueuing never blocks or fails the save: an error is logged and the save
  carries on, and the subscribers run later, in the job.

  ## Debounce

  Several saves of the same entry within `debounce_seconds` (default 5)
  become one `entry.updated`, carrying every changed field and the latest
  status. The first save schedules the event; the following ones add to it
  until it is sent. Any other event for the entry in that window
  (`entry.published` after a save, say) takes the pending update's fields
  and replaces it, so its subscribers get one event instead of two.

      config :brando, Brando.ContentEvents, debounce_seconds: 5

  ## Subscribing

  A subscriber implements `Brando.ContentEvents.Subscriber` and is listed in
  the configuration. Brando's own webhooks are always subscribed (unless
  `config :brando, Brando.Webhooks, enabled: false`).

      config :brando, Brando.ContentEvents, subscribers: [MyApp.IndexNow]

      defmodule MyApp.IndexNow do
        @behaviour Brando.ContentEvents.Subscriber

        @impl true
        def handle_event(%{type: type, url: url} = event)
            when type in ["entry.published", "entry.updated", "entry.deleted"] and is_binary(url) do
          # Queue your own job: subscribers run one after the other, inside the
          # dispatcher job, and should return quickly.
          %{url: url, event_id: event.id}
          |> Brando.Tenant.Job.attach()
          |> MyApp.Workers.SubmitUrl.new()
          |> Oban.insert()
        end

        def handle_event(_event), do: :ok
      end

  `handle_event/1` runs in the event's site and environment (the tenant
  prefix is set). An exception in one subscriber is logged and does not stop
  the others. If the dispatcher job itself is retried (the node went down
  while it ran), a subscriber may see the same event twice: use `event.id`
  to ignore repeats.

  A process that only needs to know while it runs, such as a LiveView, can
  subscribe to the PubSub topic of the current environment instead; it gets
  `{:content_event, %Brando.ContentEvents.Event{}}` after the subscribers
  have run:

      Brando.ContentEvents.subscribe()

  ## Configuration

      config :brando, Brando.ContentEvents,
        enabled: true,
        debounce_seconds: 5,
        subscribers: []
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Worker.ContentEventDispatcher

  require Logger

  @types ~w(entry.created entry.updated entry.published entry.unpublished entry.deleted entry.restored)
  @default_debounce 5

  # Not content: changes to users are logged by Activity, but they are not
  # events for the site's integrations.
  @excluded [Brando.Users.User]

  @doc "The event types."
  @spec types() :: [String.t()]
  def types, do: @types

  @doc "Whether events are sent at all (there is someone to send them to)."
  @spec enabled?() :: boolean()
  def enabled?, do: Keyword.get(config(), :enabled, true) and subscribers() != []

  @doc "How long an `entry.updated` waits for more saves of the same entry, in seconds."
  @spec debounce_seconds() :: non_neg_integer()
  def debounce_seconds, do: Keyword.get(config(), :debounce_seconds, @default_debounce)

  @doc "The modules that receive every event: Brando's webhooks, then the configured subscribers."
  @spec subscribers() :: [module()]
  def subscribers do
    builtin = if Brando.Webhooks.enabled?(), do: [Brando.Webhooks], else: []
    builtin ++ Keyword.get(config(), :subscribers, [])
  end

  defp config, do: Brando.config(__MODULE__) || []

  @doc "The PubSub topic for the current site and environment."
  @spec topic(String.t() | nil) :: String.t()
  def topic(prefix \\ Brando.Tenant.current_prefix())
  def topic(nil), do: "brando:content_events"
  def topic(prefix), do: "brando:content_events:" <> prefix

  @doc "Subscribe the calling process to the current environment's events (see the moduledoc)."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Brando.pubsub(), topic())

  ## From Activity

  @doc """
  Turns a change `Brando.Activity` recorded into content events and queues
  them. Called by `Brando.Activity.record/4`; never fails the save.
  """
  def activity_recorded(action, entry, source, opts) do
    with true <- enabled?(),
         %{__struct__: schema} <- entry,
         false <- schema in @excluded,
         [_ | _] = types <- types_for(action, entry, opts) do
      base = %{
        "schema" => to_string(schema),
        "entry_id" => entry.id,
        "language" => language(entry),
        "status" => status(entry),
        "fields" => Keyword.get(opts, :fields, []),
        "actor" => actor(source),
        "occurred_at" => DateTime.to_iso8601(DateTime.utc_now())
      }

      Enum.each(types, &emit(&1, base, entry))
    end

    :ok
  rescue
    error ->
      Logger.warning("[Brando.ContentEvents] Could not queue a content event: " <> Exception.message(error))
      :ok
  end

  @types_for_action %{
    updated: ["entry.updated"],
    revision_restored: ["entry.updated"],
    published: ["entry.published"],
    unpublished: ["entry.unpublished"],
    trashed: ["entry.deleted"],
    restored: ["entry.restored"]
  }

  defp types_for(action, _entry, _opts) when is_map_key(@types_for_action, action),
    do: Map.fetch!(@types_for_action, action)

  defp types_for(action, entry, _opts) when action in [:created, :duplicated], do: created(entry)

  defp types_for(:imported, entry, opts) do
    if Keyword.get(opts, :details, %{})["mode"] == "create", do: created(entry), else: ["entry.updated"]
  end

  # Emptying the trash: the entry was announced as deleted when it was trashed
  defp types_for(:deleted, _entry, opts) do
    if Keyword.get(opts, :details, %{})["purged"], do: [], else: ["entry.deleted"]
  end

  defp types_for(_action, _entry, _opts), do: []

  defp created(entry) do
    if Map.get(entry, :status) == :published,
      do: ["entry.created", "entry.published"],
      else: ["entry.created"]
  end

  @doc ~S'The actor kind for an Activity source: `"person"`, `"assistant"`, `"mcp"`, `"scheduler"` or `"system"`.'
  def actor(:assistant), do: "assistant"
  def actor(:mcp), do: "mcp"
  def actor(:scheduler), do: "scheduler"
  def actor(:system), do: "system"
  def actor(_admin_or_import), do: "person"

  defp language(entry) do
    case Map.get(entry, :language) do
      nil -> nil
      language -> to_string(language)
    end
  end

  defp status(entry) do
    case Map.get(entry, :status) do
      nil -> nil
      status -> to_string(status)
    end
  end

  ## Emitting

  defp emit(type, base, entry) do
    args =
      base
      |> Map.merge(%{"id" => Ecto.UUID.generate(), "type" => type, "debounce_key" => debounce_key(base)})
      |> maybe_put_url(type, entry)
      |> TenantJob.attach()

    if type == "entry.updated" and debounce_seconds() > 0,
      do: debounce(args),
      else: insert(absorb_pending_update(args), [])
  end

  defp debounce_key(%{"schema" => schema, "entry_id" => id}), do: "#{schema}:#{id}"

  # An entry deleted for good can no longer be loaded when the event is sent,
  # so its URL is worked out now — unless the delete is part of a larger
  # transaction, where a failing query would abort it.
  defp maybe_put_url(args, "entry.deleted", entry) do
    if Repo.repo().in_transaction?(), do: args, else: Map.put(args, "url", entry_url(entry))
  end

  defp maybe_put_url(args, _type, _entry), do: args

  defp debounce(args) do
    case merge_into_pending(args) do
      :merged -> :ok
      :none -> insert(args, schedule_in: debounce_seconds())
    end
  end

  defp pending_update(args) do
    fragment = Map.merge(%{"debounce_key" => args["debounce_key"], "type" => "entry.updated"}, tenant_fragment(args))

    from(j in Oban.Job,
      where:
        j.worker == ^inspect(ContentEventDispatcher) and j.state == "scheduled" and
          fragment("? @> ?", j.args, ^fragment),
      lock: "FOR UPDATE SKIP LOCKED",
      limit: 1
    )
  end

  defp tenant_fragment(args), do: Map.take(args, ["tenant_prefix"])

  defp merge_into_pending(args) do
    {:ok, result} =
      Repo.transaction(fn ->
        case Repo.one(pending_update(args)) do
          nil ->
            :none

          %Oban.Job{} = job ->
            merged =
              job.args
              |> Map.merge(Map.take(args, ["language", "status", "actor", "occurred_at"]))
              |> Map.put("fields", union(job.args["fields"], args["fields"]))

            Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [args: merged])
            :merged
        end
      end)

    result
  end

  # A pending `entry.updated` for the same entry is folded into this event,
  # which goes out now.
  defp absorb_pending_update(args) do
    {:ok, args} =
      Repo.transaction(fn ->
        case Repo.one(pending_update(args)) do
          nil ->
            args

          %Oban.Job{} = job ->
            Repo.delete_all(from(j in Oban.Job, where: j.id == ^job.id))
            Map.put(args, "fields", union(job.args["fields"], args["fields"]))
        end
      end)

    args
  end

  defp union(a, b), do: Enum.sort(Enum.uniq(List.wrap(a) ++ List.wrap(b)))

  defp insert(args, opts) do
    args
    |> ContentEventDispatcher.new(opts)
    |> Oban.insert()

    :ok
  end

  @doc """
  Query options that keep a surrounding transaction usable if the query
  fails: Oban's inline testing mode runs the dispatcher inside the save.
  """
  def savepoint, do: if(Repo.repo().in_transaction?(), do: [mode: :savepoint], else: [])

  @doc "The entry's absolute URL, or nil. Loads the associations its URL template needs."
  def entry_url(%{__struct__: schema} = entry) do
    preloads =
      if function_exported?(schema, :__absolute_url_preloads__, 0), do: schema.__absolute_url_preloads__(), else: []

    entry = if preloads == [], do: entry, else: Repo.preload(entry, preloads, savepoint())

    case schema.__absolute_url__(entry) do
      "http" <> _ = url -> url
      "/" <> _ = path -> Brando.Utils.hostname(path)
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
