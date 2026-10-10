defmodule Brando.Notifications.Digest do
  @moduledoc """
  Email digests: a user who chose a daily or weekly summary in their profile
  (`notification_digest` in `Brando.Users.UserConfig`) gets their mentions
  and the notifications routed to them by email in one email, instead of an
  email each.

  The summary goes out at `digest_hour` (default 8) in `Brando.timezone/0`,
  every day or on Mondays. An item waits for the first such time after it
  arrived. It reuses the mention emails' batching: the user's one
  `Brando.Worker.NoteMentions` job per environment is scheduled for that
  time, and later items join it (`schedule/2`, `deliver/2`).

  Without a digest, mention emails go out as before, at most one every ten
  minutes (`Brando.Notes`), and routed notifications as single emails.
  Notifications that were waiting for a digest the user has since turned off
  go out with their next email. A mention goes out only while the user may
  still see its entry (`Brando.Notes.mention_email_items/2`), and each item
  goes out once, however many jobs run (`Brando.Notes.claim_mentions/2`). An email takes
  at most 200 notifications and 100 mentions; a full batch queues the rest
  (`schedule_rest/2`).
  """

  import Ecto.Query

  alias Brando.Notes
  alias Brando.Notifications.Delivery
  alias Brando.Notifications.Email
  alias Brando.Notifications.Recipient
  alias Brando.Repo
  alias Brando.Users.User

  @periods [:off, :daily, :weekly]
  @email_interval 600
  @limit 200
  @mention_limit 100

  @doc "The choices for the profile: `:off`, `:daily` and `:weekly`."
  def periods, do: @periods

  @doc "When digests go out, as an hour in `Brando.timezone/0`."
  def hour, do: Keyword.get(Brando.config(Brando.Notifications) || [], :digest_hour, 8)

  @doc "The digest `user` (or user id) chose: `:off`, `:daily` or `:weekly`."
  def period(%User{config: %{notification_digest: period}}) when period in [:daily, :weekly], do: period
  def period(%User{}), do: :off

  def period(user_id) when is_integer(user_id) do
    case Repo.one(from(u in User, where: u.id == ^user_id, select: u.config)) do
      %{notification_digest: period} when period in [:daily, :weekly] -> period
      _ -> :off
    end
  end

  def period(_), do: :off

  @doc """
  The first time a `period` digest goes out after `from`: at `hour/0` in
  the site's time zone, the next day for `:daily`, the next Monday for
  `:weekly`.
  """
  @spec next_at(:daily | :weekly, DateTime.t()) :: DateTime.t()
  def next_at(period, %DateTime{} = from) do
    zone = Brando.timezone()
    local = DateTime.shift_zone!(from, zone)
    date = DateTime.to_date(local)

    date
    |> Stream.iterate(&Date.add(&1, 1))
    |> Stream.filter(&(period == :daily or Date.day_of_week(&1) == 1))
    |> Stream.map(&at_hour(&1, zone))
    |> Enum.find(&(DateTime.compare(&1, from) == :gt))
  end

  defp at_hour(date, zone) do
    case DateTime.new(date, Time.new!(hour(), 0, 0), zone) do
      {:ok, datetime} -> DateTime.shift_zone!(datetime, "Etc/UTC")
      {:gap, _before, later} -> DateTime.shift_zone!(later, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
    end
  end

  @doc """
  Queues the user's next email: the mention email's ten-minute batching
  without a digest, else the next digest time. One job per user and
  environment waits; a new item moves it to when the user's setting says.
  """
  def schedule(user_id, now \\ DateTime.utc_now()) do
    delay = fn ->
      case period(user_id) do
        :off -> seconds_until_next_email(user_id, now)
        period -> max(DateTime.diff(next_at(period, now), now, :second), 0)
      end
    end

    insert_job(user_id, delay, scheduled: [:scheduled_at])
  end

  @doc """
  Queues what is left after an email that took a full batch: a digest's
  rest at once, as it is due already; without a digest, with the next
  email. The job running counts as no waiting job, so this queues another,
  or brings forward the one waiting (to be retried, too). Returns `:ok`, or
  `{:error, reason}` for the running job to fail and be retried, as nothing
  else would send the rest.
  """
  def schedule_rest(user_id, now \\ DateTime.utc_now()) do
    seconds = if period(user_id) == :off, do: seconds_until_next_email(user_id, now), else: 0
    # A minute's leeway for the time the insert takes
    due_by = DateTime.add(DateTime.utc_now(), seconds + 60, :second)

    user_id
    |> insert_job(fn -> seconds end, scheduled: [:scheduled_at], retryable: [:scheduled_at])
    |> make_available(seconds)
    |> rest_queued(due_by)
  end

  # A waiting job the rest joined, due now, is made available at once: while
  # scheduled, a new item's `schedule/2` would move it back to the next digest
  defp make_available({:ok, %Oban.Job{conflict?: true, id: id, state: state} = job}, 0)
       when is_integer(id) and state in ["scheduled", "retryable"] do
    :ok = Oban.retry_job(id)
    {:ok, %{job | state: "available"}}
  end

  defp make_available(result, _seconds), do: result

  @doc false
  # Whether an insert left a job for the rest that runs by `due_by`. A unique
  # insert that could not take Oban's lock (another insert for the user held
  # it) is reported as a conflict with nothing inserted, no id.
  def rest_queued({:ok, %Oban.Job{conflict?: true, id: nil}}, _due_by), do: {:error, :locked}
  def rest_queued({:ok, %Oban.Job{state: "available"}}, _due_by), do: :ok

  def rest_queued({:ok, %Oban.Job{scheduled_at: at}}, due_by),
    do: if(DateTime.compare(at, due_by) == :gt, do: {:error, :not_due}, else: :ok)

  def rest_queued({:error, _} = error, _due_by), do: error

  # A job due now is inserted available, not scheduled: `replace` moves only a
  # scheduled job, so a later item cannot push it back to the next digest. Its
  # `scheduled_at` still brings forward a scheduled job it conflicts with.
  # (`Oban.Job.new/2` makes any job with a `scheduled_at` a scheduled one.)
  defp insert_job(user_id, delay, replace) do
    seconds = delay.()
    timing = if seconds > 0, do: [schedule_in: seconds], else: [scheduled_at: DateTime.utc_now()]

    %{"user_id" => user_id}
    |> Brando.Tenant.Job.attach_current()
    |> Brando.Worker.NoteMentions.new([replace: replace] ++ timing)
    |> available_when_due(seconds)
    |> Oban.insert()
  rescue
    error ->
      require Logger
      Logger.warning("[Brando.Notifications] Could not queue an email: " <> Exception.message(error))
      {:error, error}
  end

  defp available_when_due(changeset, seconds) when seconds > 0, do: changeset
  defp available_when_due(changeset, _seconds), do: Ecto.Changeset.force_change(changeset, :state, "available")

  @doc """
  Sends the digest for `user_id` when it is due: `:ok` (sent, or nothing to
  send), `{:snooze, seconds}` until it is due, `:not_digest` when the
  user has no digest and nothing waits for one, so the mention email goes
  out as usual, or `{:error, reason}` when the rest of a full batch could
  not be queued.
  """
  def deliver(user_id, now \\ DateTime.utc_now()) do
    period = period(user_id)
    waiting = waiting(user_id)

    if period == :off and waiting == [] do
      :not_digest
    else
      mentions = Notes.mentions_for(user_id, unsent: true, limit: @mention_limit)
      send_when_due(user_id, period, waiting, mentions, now)
    end
  end

  defp send_when_due(_user_id, _period, [], [], _now), do: :ok

  defp send_when_due(user_id, period, waiting, mentions, now) do
    due =
      if period == :off,
        do: DateTime.add(now, seconds_until_next_email(user_id, now), :second),
        else: due_at(period, waiting, mentions)

    if DateTime.compare(now, due) == :lt,
      do: {:snooze, max(DateTime.diff(due, now, :second), 1)},
      else: send_digest(user_id, period, waiting, mentions, now)
  end

  @doc """
  Seconds until `user_id` may get their next email without a summary: 0, or
  what is left of ten minutes since the last one (a mention email or a
  notification email).
  """
  def seconds_until_next_email(user_id, now) do
    case last_email_at(user_id) do
      nil -> 0
      last -> max(0, @email_interval - DateTime.diff(now, last, :second))
    end
  end

  defp last_email_at(user_id) do
    mentions =
      Repo.one(
        from(m in Brando.Notes.Mention,
          where: m.user_id == ^user_id and not is_nil(m.emailed_at),
          select: max(m.emailed_at)
        )
      )

    [mentions, last_notification_email(user_id)] |> Enum.reject(&is_nil/1) |> Enum.max(DateTime, fn -> nil end)
  end

  defp last_notification_email(user_id) do
    Repo.one(
      from(d in Delivery,
        where: d.recipient_id == ^user_id and d.state == "succeeded" and d.test == false,
        select: max(d.completed_at)
      )
    )
  rescue
    error in Postgrex.Error -> if error.postgres[:code] == :undefined_table, do: nil, else: reraise(error, __STACKTRACE__)
  end

  # The first digest time after the oldest item
  defp due_at(period, waiting, mentions) do
    oldest =
      (Enum.map(waiting, & &1.inserted_at) ++ Enum.map(mentions, & &1.inserted_at))
      |> Enum.min(DateTime)

    next_at(period, oldest)
  end

  defp waiting(user_id) do
    Repo.all(
      from(d in Delivery,
        where: d.recipient_id == ^user_id and d.state == "digest",
        order_by: [asc: d.inserted_at, asc: d.id],
        limit: @limit,
        preload: :route
      )
    )
  rescue
    # An environment that has not run the `brando_217` migration
    error in Postgrex.Error -> if error.postgres[:code] == :undefined_table, do: [], else: reraise(error, __STACKTRACE__)
  end

  # A full batch leaves the rest for another run
  defp send_digest(user_id, period, waiting, mentions, now) do
    :ok = send_batch(user_id, period, waiting, mentions, now)
    if length(waiting) == @limit or length(mentions) == @mention_limit, do: schedule_rest(user_id, now), else: :ok
  end

  defp send_batch(user_id, period, waiting, mentions, now) do
    user = Repo.get(User, user_id)

    if is_nil(user) or not user.active or not is_nil(user.deleted_at) do
      finish(waiting, mentions, "cancelled", now, "recipient_unavailable")
    else
      # Only while the route is active and still names the user, and mentions
      # only while the user may still read their entry
      {readable, unreadable} = Enum.split_with(waiting, &Recipient.may_see?(user, &1, &1.route))
      entries = Notes.mention_email_entries(user, mentions)

      # Only what this job claims goes out, so two jobs never send the same
      # item; the email is queued in the same transaction, so an item claimed
      # is one queued to be sent
      {:ok, routes} =
        Repo.transaction(fn ->
          sent = claim(readable, "succeeded", now)
          cancelled = claim(unreadable, "cancelled", now, "recipient_unavailable")
          claimed = Notes.claim_mentions(mentions, now)
          notifications = for d <- readable, MapSet.member?(sent, d.id), do: d.notification
          items = for {id, item} <- entries, MapSet.member?(claimed, id), do: item

          send_email(user, notifications, items, if(period == :off, do: :batch, else: period))
          routes(readable, sent) ++ routes(unreadable, cancelled)
        end)

      routes |> Enum.uniq() |> Enum.each(&broadcast/1)
    end

    :ok
  end

  defp send_email(_user, [], [], _period), do: :ok

  defp send_email(user, [notification], [], :batch) do
    {:ok, _job} = user |> Email.single(notification) |> Brando.Mailer.deliver_later()
    :ok
  end

  defp send_email(user, notifications, mention_items, period) do
    {:ok, _job} = user |> Email.digest(notifications, mention_items, period) |> Brando.Mailer.deliver_later()
    :ok
  end

  defp finish(deliveries, mentions, state, now, error) do
    claimed = claim(deliveries, state, now, error)
    deliveries |> routes(claimed) |> Enum.uniq() |> Enum.each(&broadcast/1)
    Notes.mark_emailed(mentions, now)
    :ok
  end

  # Finishes those of `deliveries` still waiting for a digest, and returns
  # their ids: what the caller has claimed. Another job finishing them at the
  # same time claims none of them.
  defp claim(deliveries, state, now, error \\ nil)
  defp claim([], _state, _now, _error), do: MapSet.new()

  defp claim(deliveries, state, now, error) do
    ids = Enum.map(deliveries, & &1.id)

    {_, claimed} =
      Repo.update_all(from(d in Delivery, where: d.id in ^ids and d.state == "digest", select: d.id),
        set: [state: state, completed_at: now, error: error]
      )

    MapSet.new(claimed)
  end

  defp routes(deliveries, claimed), do: for(d <- deliveries, MapSet.member?(claimed, d.id), do: d.route_id)

  defp broadcast(route_id), do: Brando.Notifications.Routing.broadcast({:delivery, route_id})
end
