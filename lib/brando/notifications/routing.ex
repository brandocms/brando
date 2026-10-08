defmodule Brando.Notifications.Routing do
  @moduledoc """
  Notifications to Slack, Microsoft Teams and email: short messages to where
  people are when something happens in a site environment.

  ## Routes

  An administrator sets up routes in Configuration → Integrations →
  Notifications, per site environment. Each route has

    * a destination: a Slack incoming webhook URL, a Microsoft Teams
      incoming webhook URL (a Workflows flow, "Post to a channel when a
      webhook request is received"), or email to chosen users;
    * the events it sends, at least one:
      * `mention` — someone was mentioned in a note (`Brando.Notes`);
      * `scheduled_publish` — scheduled publishing published an entry;
      * `scheduled_unpublish` — scheduled publishing unpublished an entry
        (the content event `entry.unpublished` with the actor
        `"scheduler"`);
      * `failed_job` — a background job of this environment was given up
        (Oban discarded it), or a webhook delivery failed for good and the
        webhook was paused;
    * optionally, the content types whose events it sends. Failed jobs are
      not about an entry and pass any content-type filter.

  ## Messages

  A notification names the entry by its title and content type, with a link
  to it in the admin; a mention names its author and the people mentioned,
  never the note's text. Slack gets blocks, Teams an Adaptive Card, both in
  the site's default admin language; see `Brando.Notifications.Message`.
  Email goes to each recipient in their own language, when they are active
  and may read the entry.

  Each message is a delivery (`Brando.Notifications.Delivery`) sent by an
  Oban job on the `:webhooks` queue (`Brando.Worker.NotificationDelivery`),
  with retries for about three hours, and recorded in the route's delivery
  log, like webhook deliveries. A Slack or Teams route whose delivery failed
  every attempt is paused. Only `https` URLs on public addresses are called,
  checked again before every delivery (`Brando.Webhooks.URLGuard`). The log
  keeps `Brando.Webhooks.retention_days/0` of deliveries.

  ## Email digests

  A user can choose, in their profile, one email a day or a week instead of
  single emails (`Brando.Notifications.Digest`). The digest collects their
  mentions and the notifications routed to them by email since the last one,
  and goes out at `digest_hour` in the site's time zone (Mondays for the
  weekly one). It reuses the mention emails' batching: one job per user and
  environment waits for the next email (`Brando.Worker.NoteMentions`).

  ## Secrets

  A Slack or Teams webhook URL lets anyone who has it post to the channel,
  so it is a secret: it is stored encrypted (`Brando.Crypto`, bound to the
  route's id), is never logged, written to Activity or sent back to the
  browser, and the admin shows only its host and last characters.

  ## Permissions

  Managing routes needs the Notifications permission
  (`brando.notifications.manage`) with group authorization, or the admin or
  superuser role without it. Routes send entry titles and people's names to
  places the manager chooses.

  ## Environments

  Copying an environment, or restoring an archive as a new one, pauses the
  copy's routes (`after_environment_copy/2`), as it does webhooks; they
  resume when that environment goes live (`after_going_live/2`).

  ## Configuration

      config :brando, Brando.Notifications,
        enabled: true,
        # notify failed_job routes when Oban discards a job
        failed_jobs: true,
        # at most one failed-job notification per worker in this many seconds
        failed_job_interval: 600,
        # when digests go out, in Brando.timezone()
        digest_hour: 8
  """

  import Ecto.Query

  alias Brando.Activity
  alias Brando.Authorization.Boundary
  alias Brando.ContentEvents.Event
  alias Brando.Notifications.Delivery
  alias Brando.Notifications.Digest
  alias Brando.Notifications.Route
  alias Brando.Repo
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Users.User
  alias Brando.Worker.NotificationDelivery

  require Logger

  @behaviour Brando.ContentEvents.Subscriber

  ## Configuration

  @doc "Whether notifications are sent at all."
  def enabled?, do: Keyword.get(config(), :enabled, true)

  @doc "Whether jobs Oban discards are notified."
  def failed_jobs?, do: enabled?() and Keyword.get(config(), :failed_jobs, true)

  @doc "At most one failed-job notification per worker and environment in this many seconds."
  def failed_job_interval, do: Keyword.get(config(), :failed_job_interval, 600)

  defp config, do: Brando.config(Brando.Notifications) || []

  ## Authorization

  @doc """
  Whether `user` may manage notification routes: the
  `brando.notifications.manage` permission with group authorization, the
  admin or superuser role without.
  """
  def can_manage?(:system), do: true

  def can_manage?(user) do
    if Brando.Authorization.enabled?(),
      do: Boundary.authorize(user, :manage, :notifications) == :ok,
      else: match?(%{role: role} when role in [:admin, :superuser], user)
  end

  defp authorize(user), do: if(can_manage?(user), do: :ok, else: {:error, :forbidden})

  ## Choices

  @doc "The users an email route can send to: active accounts, by name."
  def recipient_options do
    Repo.all(
      from(u in User,
        where: u.active == true and is_nil(u.deleted_at),
        order_by: [asc: u.name, asc: u.id],
        select: %{id: u.id, name: u.name, email: u.email}
      )
    )
  end

  defp form_opts(opts) do
    Keyword.put_new_lazy(opts, :recipient_ids, fn -> Enum.map(recipient_options(), & &1.id) end)
  end

  ## Routes

  @doc "The routes of the current environment, by name."
  def list_routes do
    Repo.all(from(r in Route, order_by: [asc: fragment("lower(?)", r.name), asc: r.id]))
  end

  @doc "A route of the current environment."
  def get_route(id) do
    with {:ok, id} <- cast_id(id),
         %Route{} = route <- Repo.get(Route, id) do
      {:ok, route}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "A changeset for the route form."
  def change_route(route \\ %Route{}, attrs \\ %{}, opts \\ []), do: Route.changeset(route, attrs, opts)

  @doc "Create a route. A webhook URL is stored encrypted once the route has its id."
  def create_route(attrs, user, opts \\ []) do
    with :ok <- authorize(user) do
      fn -> insert_route(attrs, user, form_opts(opts)) end
      |> Repo.transaction()
      |> case do
        {:ok, route} ->
          broadcast(:changed)
          {:ok, route}

        {:error, _} = error ->
          error
      end
    end
  end

  defp insert_route(attrs, user, opts) do
    changeset = Route.changeset(%Route{creator_id: user_id(user)}, attrs, opts)

    with {:ok, route} <- Repo.insert(changeset),
         {:ok, route} <- store_url(route, Ecto.Changeset.get_change(changeset, :url)) do
      Activity.setting_changed(:created, route, route.name, user, details: %{"kind" => to_string(route.kind)})
      route
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc "Change a route. Its URL changes only when a new one is given."
  def update_route(%Route{} = route, attrs, user, opts \\ []) do
    with :ok <- authorize(user),
         changeset = Route.changeset(route, attrs, form_opts(opts)),
         {:ok, updated} <- Repo.transaction(fn -> save_route(changeset) end) do
      fields = changeset.changes |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
      if fields != [], do: Activity.setting_changed(:updated, updated, updated.name, user, fields: fields)
      broadcast(:changed)
      {:ok, updated}
    end
  end

  defp save_route(changeset) do
    with {:ok, updated} <- Repo.update(changeset),
         {:ok, updated} <- store_url(updated, Ecto.Changeset.get_change(changeset, :url)) do
      updated
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc "Delete a route and its delivery log."
  def delete_route(%Route{} = route, user) do
    with :ok <- authorize(user),
         {:ok, deleted} <- Repo.delete(route) do
      Activity.setting_changed(:deleted, deleted, deleted.name, user)
      broadcast(:changed)
      {:ok, deleted}
    end
  end

  @doc "Stop sending on a route. `reason` is `:manual`, `:failures` or `:environment_copy`."
  def pause(%Route{} = route, reason \\ :manual, user) do
    with :ok <- authorize(user),
         {:ok, route} <-
           route
           |> Ecto.Changeset.change(active: false, paused_reason: reason, paused_at: DateTime.utc_now())
           |> Repo.update() do
      Activity.setting_changed(:updated, route, route.name, user,
        fields: ["active"],
        details: %{"route" => "paused", "reason" => to_string(reason)}
      )

      broadcast(:changed)
      {:ok, route}
    end
  end

  @doc "Send on a paused route again. What happened meanwhile is not sent."
  def resume(%Route{} = route, user) do
    with :ok <- authorize(user),
         {:ok, route} <-
           route
           |> Ecto.Changeset.change(active: true, paused_reason: nil, paused_at: nil, failing_since: nil)
           |> Repo.update() do
      Activity.setting_changed(:updated, route, route.name, user, fields: ["active"], details: %{"route" => "resumed"})
      broadcast(:changed)
      {:ok, route}
    end
  end

  ## Secrets

  defp url_context(%Route{id: id}), do: "notifications.url:#{id}"

  defp store_url(route, nil), do: {:ok, route}

  defp store_url(%Route{} = route, url) when is_binary(url) do
    route
    |> Ecto.Changeset.change(url_ciphertext: Brando.Crypto.encrypt(url, url_context(route)), url_hint: url_hint(url))
    |> Repo.update()
    |> case do
      {:ok, route} -> {:ok, %{route | url: nil}}
      error -> error
    end
  end

  @doc "The route's webhook URL, to post to. Never show or log it."
  def url(%Route{url_ciphertext: ciphertext} = route) when is_binary(ciphertext) do
    case Brando.Crypto.decrypt(ciphertext, url_context(route)) do
      {:ok, url} -> {:ok, url}
      :error -> {:error, :url_unreadable}
    end
  end

  def url(_route), do: {:error, :url_unreadable}

  @doc """
  How the admin shows a webhook URL once it is saved: its host and the last
  four characters, `"hooks.slack.com/…b2Xc"`.
  """
  def url_hint(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{host: host}} when is_binary(host) -> host <> "/…" <> String.slice(url, -4, 4)
      _ -> "…"
    end
  end

  ## Events

  @scheduled %{"entry.published" => "scheduled_publish", "entry.unpublished" => "scheduled_unpublish"}

  @impl Brando.ContentEvents.Subscriber
  @doc """
  Content events: an entry published or unpublished by scheduled
  publishing goes to the routes that send `scheduled_publish` or
  `scheduled_unpublish`.
  """
  def handle_event(%Event{actor: "scheduler", type: type} = event) when is_map_key(@scheduled, type) do
    kind = Map.fetch!(@scheduled, type)

    notification =
      base(kind)
      |> Map.put("entry", entry_info(event.schema, event.entry_id, event.language))

    notify(kind, notification, event_id: event.id, schema: event.schema, entry_id: event.entry_id)
  rescue
    error in Postgrex.Error -> missing_table(error, __STACKTRACE__)
  end

  def handle_event(_event), do: :ok

  @doc """
  A note on `entry` mentioned `mentioned` (users): goes to the routes that
  send `mention`. Never fails the note.
  """
  def mention_created(note, schema, entry, author, mentioned) do
    if enabled?() and mentioned != [] do
      notification =
        base("mention")
        |> Map.merge(%{
          "entry" => entry_info(schema, entry),
          "author" => author && author.name,
          "mentioned" => Enum.map(mentioned, & &1.name),
          "anchor" => note.anchor_label
        })

      notify("mention", notification,
        event_id: Ecto.UUID.generate(),
        schema: schema,
        entry_id: entry.id,
        # They have the mention email already
        skip_recipients: Enum.map(mentioned, & &1.id)
      )
    end

    :ok
  rescue
    error ->
      Logger.warning("[Brando.Notifications] Could not route a mention: " <> Exception.message(error))
      :ok
  end

  @doc """
  A webhook delivery failed every attempt and the webhook was paused: goes
  to the routes that send `failed_job`.
  """
  def webhook_failed(webhook, delivery) do
    if enabled?() do
      notification =
        base("failed_job")
        |> Map.put("webhook", %{
          "name" => webhook.name,
          "host" => Brando.Webhooks.host(webhook),
          "admin_url" => admin_url("/admin/config/webhooks/#{webhook.id}/deliveries")
        })

      notify("failed_job", notification, event_id: delivery.delivery_id)
    end

    :ok
  rescue
    error ->
      Logger.warning("[Brando.Notifications] Could not route a failed webhook: " <> Exception.message(error))
      :ok
  end

  @doc """
  A job was given up (see `Brando.Notifications.JobFailures`): goes to the
  routes that send `failed_job`. `job` has `"worker"`, `"queue"`,
  `"attempt"`, `"max_attempts"`, `"error"` and `"id"`.
  """
  def job_failed(job) when is_map(job) do
    notification = Map.put(base("failed_job"), "job", Map.take(job, ~w(worker queue attempt max_attempts error id)))
    notify("failed_job", notification, event_id: Ecto.UUID.generate())
  rescue
    error in Postgrex.Error -> missing_table(error, __STACKTRACE__)
  end

  # An environment that has not run the `brando_217` migration has no routes
  defp missing_table(error, stacktrace) do
    if error.postgres[:code] == :undefined_table, do: :ok, else: reraise(error, stacktrace)
  end

  defp base(event) do
    {site, environment} = Brando.Worker.ContentEventDispatcher.site_and_environment()

    %{
      "event" => event,
      "site" => site,
      "environment" => environment,
      "occurred_at" => DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  # The entry as a notification names it: title, type, language and admin link
  defp entry_info(schema, entry_id, language \\ nil)

  defp entry_info(nil, _id, _language), do: nil
  defp entry_info(_schema, nil, _language), do: nil

  defp entry_info(schema, entry_id, _language) when is_integer(entry_id) do
    case Repo.get(schema, entry_id, Brando.ContentEvents.savepoint()) do
      nil -> %{"title" => "##{entry_id}", "type" => type_label(schema), "admin_url" => nil}
      entry -> entry_info(schema, entry)
    end
  rescue
    _ -> nil
  end

  defp entry_info(schema, %{id: id} = entry, _language) do
    %{
      "title" => Brando.Notes.entry_title(schema, entry),
      "type" => type_label(schema),
      "language" => entry |> Map.get(:language) |> then(&(&1 && to_string(&1))),
      "admin_url" => entry_admin_url(schema, id)
    }
  end

  defp type_label(schema) do
    schema |> Brando.Blueprint.get_singular() |> to_string() |> String.capitalize()
  rescue
    _ -> nil
  end

  defp entry_admin_url(schema, id) do
    admin_url(schema.__admin_route__(:update, [id]))
  rescue
    _ -> nil
  end

  defp admin_url(path) do
    String.trim_trailing(Brando.endpoint().url(), "/") <> path
  rescue
    _ -> nil
  end

  ## Queueing

  # Every active route that sends `event` (for this content type) gets a
  # delivery: one for a Slack or Teams route, one per recipient for email.
  # Returns `{:error, _}` when one could not be queued, so a content event
  # is dispatched again; deliveries already queued for it are not repeated.
  defp notify(event, notification, opts) do
    entry_type = Event.entry_type(opts[:schema])

    from(r in Route, where: r.active == true)
    |> Repo.all(savepoint())
    |> Enum.filter(&Route.matches?(&1, event, entry_type))
    |> Enum.flat_map(&queue(&1, event, notification, entry_type, opts))
    |> Enum.reject(&(&1 == :ok))
    |> case do
      [] -> :ok
      failed -> {:error, {:not_queued, length(failed)}}
    end
  end

  defp queue(%Route{kind: :email} = route, event, notification, entry_type, opts) do
    skip = Keyword.get(opts, :skip_recipients, [])

    route.recipient_ids
    |> Enum.reject(&(&1 in skip))
    |> Enum.map(&queue_one(route, event, notification, entry_type, Keyword.put(opts, :recipient_id, &1)))
  end

  defp queue(route, event, notification, entry_type, opts),
    do: [queue_one(route, event, notification, entry_type, opts)]

  defp queue_one(route, event, notification, entry_type, opts) do
    recipient_id = opts[:recipient_id]
    digest? = recipient_id && Digest.period(recipient_id) != :off

    attrs = %{
      route_id: route.id,
      event: event,
      event_id: opts[:event_id],
      recipient_id: recipient_id,
      entry_schema: opts[:schema] && to_string(opts[:schema]),
      entry_type: entry_type,
      entry_id: opts[:entry_id],
      notification: notification,
      state: if(digest?, do: "digest", else: "pending")
    }

    in_transaction(fn ->
      %Delivery{}
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert(
        [
          on_conflict: :nothing,
          conflict_target:
            {:unsafe_fragment, "(route_id, event_id, coalesce(recipient_id, 0)) WHERE event_id IS NOT NULL"}
        ] ++ savepoint()
      )
      |> case do
        {:ok, %Delivery{id: nil} = existing} -> {:ok, existing}
        {:ok, %Delivery{state: "digest"} = delivery} -> digest(delivery)
        {:ok, delivery} -> enqueue(delivery)
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp digest(%Delivery{recipient_id: user_id} = delivery) do
    case Digest.schedule(user_id) do
      {:ok, _job} -> {:ok, delivery}
      {:error, reason} -> {:error, reason}
    end
  end

  defp in_transaction(fun) do
    if Repo.repo().in_transaction?() do
      with {:ok, _} <- fun.(), do: :ok
    else
      case Repo.transaction(fn -> rollback_on_error(fun.()) end) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    error ->
      Logger.error("[Brando.Notifications] Could not queue a delivery: " <> Exception.message(error))
      {:error, :not_queued}
  end

  defp rollback_on_error({:error, reason}), do: Repo.rollback(reason)
  defp rollback_on_error(result), do: result

  defp savepoint, do: Brando.ContentEvents.savepoint()

  defp enqueue(%Delivery{} = delivery) do
    %{"delivery" => delivery.id, "route" => delivery.route_id}
    |> TenantJob.attach()
    |> NotificationDelivery.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> {:ok, delivery}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Send a test notification on an active route: to its channel, or to each
  of its recipients by single email whatever their digest setting.
  """
  def send_test(%Route{} = route, user) do
    with :ok <- authorize(user),
         :ok <- active(route) do
      notification = Map.put(base("test"), "admin_url", admin_url("/admin/config/notifications/#{route.id}/deliveries"))
      recipients = if route.kind == :email, do: route.recipient_ids, else: [nil]

      Enum.reduce_while(recipients, {:ok, []}, &queue_test(route, &1, notification, &2))
    end
  end

  defp queue_test(route, recipient_id, notification, {:ok, queued}) do
    case queue_test(route, recipient_id, notification) do
      {:ok, delivery} -> {:cont, {:ok, [delivery | queued]}}
      error -> {:halt, error}
    end
  end

  defp queue_test(route, recipient_id, notification) do
    attrs = %{route_id: route.id, event: "test", recipient_id: recipient_id, notification: notification, test: true}

    with {:ok, delivery} <- %Delivery{} |> Ecto.Changeset.change(attrs) |> Repo.insert() do
      enqueue(delivery)
    end
  end

  @doc """
  Send a failed or cancelled delivery again, as a new delivery of the same
  notification to the same channel or recipient. An email goes out as a
  single email, whatever the recipient's summary setting.
  """
  def redeliver(%Delivery{state: state} = original, user) when state in ["failed", "cancelled"] do
    with :ok <- authorize(user),
         {:ok, route} <- get_route(original.route_id),
         :ok <- active(route) do
      attrs =
        original
        |> Map.take([:route_id, :event, :recipient_id, :entry_schema, :entry_type, :entry_id, :notification, :test])

      with {:ok, delivery} <- %Delivery{} |> Ecto.Changeset.change(attrs) |> Repo.insert() do
        enqueue(delivery)
      end
    end
  end

  def redeliver(%Delivery{}, _user), do: {:error, :not_redeliverable}

  @doc "Whether a delivery can be sent again: it failed, or was not sent."
  def redeliverable?(%Delivery{state: state}), do: state in ["failed", "cancelled"]

  @doc "A delivery of the current environment."
  def get_delivery(id) do
    with {:ok, id} <- cast_id(id),
         %Delivery{} = delivery <- Repo.get(Delivery, id) do
      {:ok, delivery}
    else
      _ -> {:error, :not_found}
    end
  end

  defp active(%Route{active: true}), do: :ok
  defp active(_route), do: {:error, :paused}

  ## The log

  @doc "A route's deliveries, newest first, with their recipients. Options: `:limit` (default 50)."
  def list_deliveries(%Route{id: id}, opts \\ []) do
    from(d in Delivery,
      where: d.route_id == ^id,
      order_by: [desc: d.inserted_at, desc: d.id],
      limit: ^Keyword.get(opts, :limit, 50),
      preload: :recipient
    )
    |> Repo.all()
  end

  @doc "Deliveries on every route of the current environment, newest first, with their route and recipient."
  def list_all_deliveries(opts \\ []) do
    from(d in Delivery,
      order_by: [desc: d.inserted_at, desc: d.id],
      limit: ^Keyword.get(opts, :limit, 50),
      preload: [:route, :recipient]
    )
    |> Repo.all()
  end

  @doc """
  For the Integrations screen: how many routes there are, the latest
  delivery and its route, and how many failed in the last day.
  """
  def summary do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)

    latest =
      from(d in Delivery,
        where: d.state in ["succeeded", "retrying", "failed"],
        order_by: [desc: d.completed_at, desc: d.id],
        limit: 1,
        preload: :route
      )
      |> Repo.one()

    %{
      count: Repo.aggregate(Route, :count),
      latest: latest,
      failed:
        Repo.aggregate(
          from(d in Delivery, where: d.state in ["retrying", "failed"] and d.inserted_at >= ^since),
          :count
        )
    }
  rescue
    _ -> %{count: 0, latest: nil, failed: 0}
  end

  @doc "The routes paused because their messages kept failing, for the dashboard."
  def paused_after_failures do
    Repo.all(from(r in Route, where: r.active == false and r.paused_reason == :failures, order_by: r.name))
  rescue
    _ -> []
  end

  @doc "Remove deliveries older than `days`, except those waiting for a digest. Returns how many."
  def purge_deliveries(days \\ Brando.Webhooks.retention_days()) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
    {count, _} = Repo.delete_all(from(d in Delivery, where: d.inserted_at < ^cutoff and d.state != "digest"))
    count
  rescue
    error in Postgrex.Error -> if error.postgres[:code] == :undefined_table, do: 0, else: reraise(error, __STACKTRACE__)
  end

  ## Environments

  @doc """
  After an environment's content was replaced from another schema — copied,
  or restored from an archive as a new environment — its routes (the
  source's) are paused with the reason `:environment_copy` and the delivery
  log that came along is cleared, so the copy sends nothing. Routes paused
  for another reason stay as they are.
  """
  def after_environment_copy(prefix, actor \\ :system) do
    if tables?(prefix), do: pause_copied(prefix, actor), else: :ok
  end

  @doc """
  After the environment at `prefix` became the live one: its routes paused
  because it was a copy resume. Returns how many.
  """
  def after_going_live(prefix, actor \\ :system) do
    if tables?(prefix), do: resume_copied(prefix, actor), else: 0
  end

  defp tables?(prefix) do
    %{rows: [[table]]} = Repo.repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}".notification_routes)])
    not is_nil(table)
  end

  defp pause_copied(prefix, actor) do
    now = DateTime.utc_now()

    {_count, paused} =
      Repo.update_all(
        from(r in Route, where: r.active == true, select: r),
        [set: [active: false, paused_reason: :environment_copy, paused_at: now]],
        prefix: prefix
      )

    Repo.delete_all(Delivery, prefix: prefix)
    record_lifecycle(prefix, paused, actor, %{"route" => "paused", "reason" => "environment_copy"})
    :ok
  rescue
    error ->
      Logger.error("[Brando.Notifications] Could not pause the routes of #{prefix}: " <> Exception.message(error))
      {:error, :notification_routes_not_paused}
  end

  defp resume_copied(prefix, actor) do
    {count, resumed} =
      Repo.update_all(
        from(r in Route, where: r.active == false and r.paused_reason == :environment_copy, select: r),
        [set: [active: true, paused_reason: nil, paused_at: nil, failing_since: nil]],
        prefix: prefix
      )

    record_lifecycle(prefix, resumed, actor, %{"route" => "resumed", "reason" => "went_live"})
    count
  rescue
    error ->
      Logger.error("[Brando.Notifications] Could not resume the routes of #{prefix}: " <> Exception.message(error))
      0
  end

  defp record_lifecycle(_prefix, [], _actor, _details), do: :ok

  defp record_lifecycle(prefix, routes, actor, details) do
    Brando.Tenant.with_prefix(prefix, fn ->
      Enum.each(routes, fn route ->
        Activity.setting_changed(:updated, route, route.name, actor, fields: ["active"], details: details)
      end)

      broadcast(:changed)
    end)
  end

  ## Updates for the admin

  @doc "The PubSub topic for route changes and deliveries in the current environment."
  def topic(prefix \\ Brando.Tenant.current_prefix())
  def topic(nil), do: "brando:notifications"
  def topic(prefix), do: "brando:notifications:" <> prefix

  @doc "Tell the admin screens of the current environment that `message` happened."
  def broadcast(message), do: Phoenix.PubSub.broadcast(Brando.pubsub(), topic(), {__MODULE__, message})

  ## Helpers

  defp cast_id(id) when is_integer(id), do: {:ok, id}

  defp cast_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp cast_id(_), do: :error

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
