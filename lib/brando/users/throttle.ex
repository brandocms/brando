defmodule Brando.Users.Throttle do
  @moduledoc """
  Limits sign-in attempts, two-factor codes and password reset requests, and
  locks an account for a while after repeated failures.

  Attempts are counted per IP address and per account in fixed windows
  (`Brando.RateLimit`, so each node counts its own). Failures — a wrong
  password, a wrong two-factor code, a wrong password or code when
  confirming a change — are counted on the account itself, in the database:
  after `lockout_after` within `lockout_minutes` of the first of them, the
  account is locked for `lockout_minutes` — an hour the second time in a
  day, four hours after that (`lockout_escalation_minutes`) — and the user
  is emailed, on every node, and the lockout is recorded in the
  security log. A successful sign-in starts the count again.

  An address with no account counts its failures too, in the cache, so the
  answer after too many tries is the same whether or not the account exists.

      config :brando, Brando.Users.Throttle,
        window: :timer.minutes(15),
        login_per_ip: 30,
        login_per_account: 10,
        two_factor_per_ip: 30,
        reset_per_ip: 10,
        reset_per_account: 3,
        lockout_after: 5,
        lockout_minutes: 15,
        lockout_escalation_minutes: [60, 240]

  The IP address is the client's, also behind a trusted reverse proxy:
  see `Brando.ClientIP` and `config :brando, :trusted_proxies`.
  """

  import Ecto.Query

  alias Brando.RateLimit
  alias Brando.Repo
  alias Brando.Users.Security
  alias Brando.Users.SecurityLog

  @defaults [
    window: :timer.minutes(15),
    login_per_ip: 30,
    login_per_account: 10,
    two_factor_per_ip: 30,
    reset_per_ip: 10,
    reset_per_account: 3,
    lockout_after: 5,
    lockout_minutes: 15,
    lockout_escalation_minutes: [60, 240]
  ]

  @doc """
  Whole minutes left until `until`, rounded up and at least 1: a fresh
  15-minute lock reads 15 for its whole first minute, so answers given moments
  apart agree (one second earlier it read 16 with a floor-plus-one).
  """
  @spec minutes_left(DateTime.t(), DateTime.t()) :: pos_integer()
  def minutes_left(until, now \\ DateTime.utc_now()), do: max(div(DateTime.diff(until, now) + 59, 60), 1)

  @doc "The throttle's settings, the defaults merged with the application's."
  @spec config() :: keyword()
  def config, do: Keyword.merge(@defaults, Brando.config(__MODULE__) || [])

  defp config(key), do: Keyword.fetch!(config(), key)

  @doc """
  Counts a sign-in attempt from `ip` for `email`. `:ok`, or
  `{:error, :rate_limited, retry_after}` with the milliseconds to wait.
  """
  @spec check_login(String.t() | nil, String.t()) :: :ok | {:error, :rate_limited, non_neg_integer()}
  def check_login(ip, email) do
    with :ok <- hit({:login_ip, ip}, :login_per_ip) do
      hit({:login_account, normalize(email)}, :login_per_account)
    end
  end

  @doc "Counts a two-factor code from `ip`. As `check_login/2`."
  @spec check_two_factor(String.t() | nil) :: :ok | {:error, :rate_limited, non_neg_integer()}
  def check_two_factor(ip), do: hit({:two_factor_ip, ip}, :two_factor_per_ip)

  @doc """
  Counts a password reset request from `ip` for `email`: `:ok`,
  `{:error, :ip_limited, retry_after}`, or `{:error, :account_limited,
  retry_after}`. The last should look like success to the visitor, so it
  tells nothing about the account.
  """
  @spec check_reset(String.t() | nil, String.t()) ::
          :ok | {:error, :ip_limited | :account_limited, non_neg_integer()}
  def check_reset(ip, email) do
    case hit({:reset_ip, ip}, :reset_per_ip) do
      :ok ->
        case hit({:reset_account, normalize(email)}, :reset_per_account) do
          :ok -> :ok
          {:error, :rate_limited, retry_after} -> {:error, :account_limited, retry_after}
        end

      {:error, :rate_limited, retry_after} ->
        {:error, :ip_limited, retry_after}
    end
  end

  # Without an address (a test, or a socket without peer data) there is
  # nothing to count per IP.
  defp hit({_kind, nil}, _limit), do: :ok
  defp hit(bucket, limit), do: RateLimit.hit({__MODULE__, bucket}, config(limit), config(:window))

  defp normalize(email) when is_binary(email), do: email |> String.trim() |> String.downcase() |> String.slice(0, 160)
  defp normalize(_), do: ""

  @doc "When `user`'s lockout ends, or nil when they are not locked out."
  @spec locked_until(map()) :: DateTime.t() | nil
  def locked_until(%{id: user_id}) do
    now = DateTime.utc_now()

    from(s in Security, where: s.user_id == ^user_id and s.locked_until > ^now, select: s.locked_until)
    |> Repo.one()
  end

  @doc """
  Counts a failed attempt by `user` (`reason` is `:password`, `:two_factor`
  or `:confirm`), and records it. Returns `:ok`, or `{:locked, until}` when
  this failure locked the account.

  Failures count in a window of `lockout_minutes` from the first of them, as
  they do for an address with no account (`failed_unknown/1`), so spaced
  attempts get the same answers either way.
  """
  @spec failed(map(), atom(), SecurityLog.meta()) :: :ok | {:locked, DateTime.t()}
  def failed(%{id: user_id} = user, reason, meta \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    SecurityLog.record(:login_failed, user, meta: meta, details: %{"reason" => to_string(reason)})

    {:ok, result} =
      Repo.transaction(fn ->
        Repo.insert(%Security{user_id: user_id}, on_conflict: :nothing, conflict_target: :user_id)
        security = Repo.one!(from s in Security, where: s.user_id == ^user_id, lock: "FOR UPDATE")
        count_failure(user, security, now)
      end)

    case result do
      {:locked, until} ->
        SecurityLog.record(:locked, user, meta: meta, details: %{"until" => DateTime.to_iso8601(until)})

        Brando.Users.notify_security(user, :locked, %{
          time:
            Brando.Utils.Datetime.format_datetime(
              until,
              "%-d %B %Y, %H:%M %Z",
              to_string(Map.get(user, :language) || "en")
            )
        })

        {:locked, until}

      :ok ->
        :ok
    end
  end

  defp count_failure(user, security, now) do
    window_start = DateTime.add(now, -config(:lockout_minutes) * 60, :second)

    {count, since} =
      if security.failures_since && DateTime.compare(security.failures_since, window_start) == :gt,
        do: {security.failed_attempts + 1, security.failures_since},
        else: {1, now}

    query = from(s in Security, where: s.user_id == ^user.id)

    if count >= config(:lockout_after) do
      until = DateTime.add(now, user |> lockouts_today() |> lockout_seconds(), :second)
      Repo.update_all(query, set: [failed_attempts: 0, failures_since: nil, locked_until: until])
      {:locked, until}
    else
      Repo.update_all(query, set: [failed_attempts: count, failures_since: since])
      :ok
    end
  end

  # How long a lockout lasts: `lockout_minutes` the first time in a day, then
  # each of `lockout_escalation_minutes` (an hour, then four), which slows a
  # patient guesser down
  defp lockout_seconds(previous_lockouts) do
    steps = [config(:lockout_minutes) | config(:lockout_escalation_minutes)]
    Enum.at(steps, min(previous_lockouts, length(steps) - 1)) * 60
  end

  # An address with no account keeps the times of its lockouts, so it counts
  # them over the same rolling day as an account's `:locked` events
  defp unknown_lockouts_today(email) do
    length(recent_unknown_lockouts(email))
  end

  defp remember_unknown_lockout(email) do
    times = [System.system_time(:second) | recent_unknown_lockouts(email)]
    Cachex.put(:cache, {__MODULE__, :unknown_lockouts, email}, times, expire: 86_400_000)
  end

  defp recent_unknown_lockouts(email) do
    day_ago = System.system_time(:second) - 86_400

    case Cachex.get(:cache, {__MODULE__, :unknown_lockouts, email}) do
      {:ok, times} when is_list(times) -> Enum.filter(times, &(&1 > day_ago))
      _ -> []
    end
  end

  defp lockouts_today(%{id: user_id}) do
    day_ago = DateTime.add(DateTime.utc_now(), -86_400, :second)

    Repo.aggregate(
      from(e in Brando.Users.SecurityEvent,
        where: e.user_id == ^user_id and e.action == :locked and e.inserted_at > ^day_ago
      ),
      :count
    )
  end

  @doc """
  Counts a failed sign-in for an address with no account, so that it is
  answered as an account's would be: the same window, the same lockout.
  Returns `:ok`, or `{:locked, until}`.
  """
  @spec failed_unknown(String.t()) :: :ok | {:locked, DateTime.t()}
  def failed_unknown(email) do
    email = normalize(email)
    key = {__MODULE__, :unknown_failures, email}
    # A read first, so a count whose window has passed is dropped before it grows
    _ = Cachex.get(:cache, key)
    {_, count} = Cachex.incr(:cache, key, 1)
    if count == 1, do: Cachex.expire(:cache, key, config(:lockout_minutes) * 60_000)

    if count >= config(:lockout_after) do
      seconds = email |> unknown_lockouts_today() |> lockout_seconds()
      remember_unknown_lockout(email)
      until = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), seconds, :second)
      Cachex.del(:cache, key)
      Cachex.put(:cache, {__MODULE__, :unknown_locked, email}, until, expire: seconds * 1000)
      {:locked, until}
    else
      :ok
    end
  end

  @doc "When the lockout of an address with no account ends, as `locked_until/1`."
  @spec unknown_locked_until(String.t()) :: DateTime.t() | nil
  def unknown_locked_until(email) do
    case Cachex.get(:cache, {__MODULE__, :unknown_locked, normalize(email)}) do
      {:ok, %DateTime{} = until} -> if DateTime.compare(until, DateTime.utc_now()) == :gt, do: until
      _ -> nil
    end
  end

  @doc "Starts `user`'s count of failures again, after a sign-in, and ends a lockout."
  @spec clear(map()) :: :ok
  def clear(%{id: user_id}) do
    from(s in Security, where: s.user_id == ^user_id and (s.failed_attempts > 0 or not is_nil(s.locked_until)))
    |> Repo.update_all(set: [failed_attempts: 0, failures_since: nil, locked_until: nil])

    :ok
  end

  @doc false
  # Forgets every count in the cache, for tests.
  def reset do
    {:ok, keys} = Cachex.keys(:cache)

    for key <- keys, match?({{__MODULE__, _}, _}, key) or match?({__MODULE__, _, _}, key), do: Cachex.del(:cache, key)

    :ok
  end
end
