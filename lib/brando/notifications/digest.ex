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
  go out with their next email.
  """

  import Ecto.Query

  alias Brando.Notes
  alias Brando.Notifications.Delivery
  alias Brando.Notifications.Email
  alias Brando.Repo
  alias Brando.Users.User

  @periods [:off, :daily, :weekly]
  @limit 200

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
    delay =
      case period(user_id) do
        :off -> Notes.seconds_until_next_email(user_id, now)
        period -> max(DateTime.diff(next_at(period, now), now, :second), 0)
      end

    %{"user_id" => user_id}
    |> Brando.Tenant.Job.attach_current()
    |> Brando.Worker.NoteMentions.new(schedule_in: delay, replace: [scheduled: [:scheduled_at]])
    |> Oban.insert()
  rescue
    error ->
      require Logger
      Logger.warning("[Brando.Notifications] Could not queue an email: " <> Exception.message(error))
      {:error, error}
  end

  @doc """
  Sends the digest for `user_id` when it is due: `:ok` (sent, or nothing to
  send), `{:snooze, seconds}` until it is due, or `:not_digest` when the
  user has no digest and nothing waits for one, so the mention email goes
  out as usual.
  """
  def deliver(user_id, now \\ DateTime.utc_now()) do
    period = period(user_id)
    waiting = waiting(user_id)

    if period == :off and waiting == [] do
      :not_digest
    else
      mentions = Notes.mentions_for(user_id, unsent: true, limit: 100)
      send_when_due(user_id, period, waiting, mentions, now)
    end
  end

  defp send_when_due(_user_id, _period, [], [], _now), do: :ok

  defp send_when_due(user_id, period, waiting, mentions, now) do
    due = due_at(period, waiting, mentions)

    if DateTime.compare(now, due) == :lt,
      do: {:snooze, max(DateTime.diff(due, now, :second), 1)},
      else: send_digest(user_id, period, waiting, mentions, now)
  end

  # The first digest time after the oldest item. Turned off: now.
  defp due_at(:off, _waiting, _mentions), do: ~U[1970-01-01 00:00:00Z]

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
        limit: @limit
      )
    )
  rescue
    # An environment that has not run the `brando_217` migration
    error in Postgrex.Error -> if error.postgres[:code] == :undefined_table, do: [], else: reraise(error, __STACKTRACE__)
  end

  defp send_digest(user_id, period, waiting, mentions, now) do
    user = Repo.get(User, user_id)

    if is_nil(user) or not user.active or not is_nil(user.deleted_at) do
      finish(waiting, mentions, "cancelled", now)
    else
      {readable, unreadable} = Enum.split_with(waiting, &Brando.Notifications.Recipient.may_see?(user, &1))
      notifications = Enum.map(readable, & &1.notification)
      mention_items = Notes.mention_email_items(mentions)

      if notifications != [] or mention_items != [] do
        {:ok, _job} =
          user
          |> Email.digest(notifications, mention_items, if(period == :weekly, do: :weekly, else: :daily))
          |> Brando.Mailer.deliver_later()
      end

      finish(unreadable, [], "cancelled", now)
      finish(readable, mentions, "succeeded", now)
    end
  end

  defp finish(deliveries, mentions, state, now) do
    if deliveries != [] do
      ids = Enum.map(deliveries, & &1.id)
      Repo.update_all(from(d in Delivery, where: d.id in ^ids), set: [state: state, completed_at: now])
      Enum.each(deliveries |> Enum.map(& &1.route_id) |> Enum.uniq(), &broadcast/1)
    end

    Notes.mark_emailed(mentions, now)
    :ok
  end

  defp broadcast(route_id), do: Brando.Notifications.Routing.broadcast({:delivery, route_id})
end
