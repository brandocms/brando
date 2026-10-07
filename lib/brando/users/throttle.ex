defmodule Brando.Users.Throttle do
  @moduledoc """
  Limits sign-in attempts, two-factor codes and password reset requests, and
  locks an account for a while after repeated failures.

  Attempts are counted per IP address and per account in fixed windows
  (`Brando.RateLimit`, so each node counts its own). Failures — a wrong
  password, a wrong two-factor code, a wrong password or code when
  confirming a change — are counted on the account itself, in the database:
  after `lockout_after` in a row, the account is locked for
  `lockout_minutes`, on every node, and the lockout is recorded in the
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
        lockout_minutes: 15

  Behind a proxy, the IP address is the proxy's unless the application sets
  `conn.remote_ip` from a trusted header (for example with the `remote_ip`
  library) and the admin socket gives `:peer_data` that does the same.
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
    lockout_minutes: 15
  ]

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
  """
  @spec failed(map(), atom(), SecurityLog.meta()) :: :ok | {:locked, DateTime.t()}
  def failed(%{id: user_id} = user, reason, meta \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    naive_now = DateTime.to_naive(now)

    {:ok, %{failed_attempts: count}} =
      Repo.insert(%Security{user_id: user_id, failed_attempts: 1},
        on_conflict: [inc: [failed_attempts: 1], set: [updated_at: naive_now]],
        conflict_target: :user_id,
        returning: [:failed_attempts]
      )

    SecurityLog.record(:login_failed, user, meta: meta, details: %{"reason" => to_string(reason)})

    if count >= config(:lockout_after) do
      until = DateTime.add(now, config(:lockout_minutes) * 60, :second)

      from(s in Security, where: s.user_id == ^user_id)
      |> Repo.update_all(set: [failed_attempts: 0, locked_until: until, updated_at: naive_now])

      SecurityLog.record(:locked, user, meta: meta, details: %{"until" => DateTime.to_iso8601(until)})
      {:locked, until}
    else
      :ok
    end
  end

  @doc """
  Counts a failed sign-in for an address with no account, so that it is
  answered as an account's would be. Returns `:ok`, or `{:locked, until}`.
  """
  @spec failed_unknown(String.t()) :: :ok | {:locked, DateTime.t()}
  def failed_unknown(email) do
    key = {__MODULE__, :unknown_failures, normalize(email)}
    {_, count} = Cachex.incr(:cache, key, 1)
    if count == 1, do: Cachex.expire(:cache, key, config(:lockout_minutes) * 60_000)

    if count >= config(:lockout_after),
      do: {:locked, DateTime.add(DateTime.utc_now(), config(:lockout_minutes) * 60, :second)},
      else: :ok
  end

  @doc "Whether an address with no account has failed as often as locks an account."
  @spec unknown_locked?(String.t()) :: boolean()
  def unknown_locked?(email) do
    case Cachex.get(:cache, {__MODULE__, :unknown_failures, normalize(email)}) do
      {:ok, count} when is_integer(count) -> count >= config(:lockout_after)
      _ -> false
    end
  end

  @doc "Starts `user`'s count of failures again, after a sign-in, and ends a lockout."
  @spec clear(map()) :: :ok
  def clear(%{id: user_id}) do
    from(s in Security, where: s.user_id == ^user_id and (s.failed_attempts > 0 or not is_nil(s.locked_until)))
    |> Repo.update_all(set: [failed_attempts: 0, locked_until: nil])

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
