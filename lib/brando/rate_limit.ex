defmodule Brando.RateLimit do
  @moduledoc """
  Fixed-window counters, kept in the `:cache` Cachex cache, so each node
  counts its own. Form submissions (`Brando.Forms.RateLimit`) and sign-in
  attempts (`Brando.Users.Throttle`) count with it.
  """

  @doc """
  Counts a hit on `bucket` in the current window of `window` milliseconds.
  `:ok` while the window has seen no more than `limit` hits, otherwise
  `{:error, :rate_limited, retry_after}`, with the milliseconds left of the
  window.
  """
  @spec hit(term(), pos_integer(), pos_integer()) :: :ok | {:error, :rate_limited, non_neg_integer()}
  def hit(bucket, limit, window) do
    now = System.system_time(:millisecond)
    current = div(now, window)

    if increment({bucket, current}, window) <= limit,
      do: :ok,
      else: {:error, :rate_limited, (current + 1) * window - now}
  end

  @doc """
  Adds one to the counter `key` and returns the new count. A new counter
  expires after twice `ttl` milliseconds.
  """
  @spec increment(term(), pos_integer()) :: pos_integer()
  def increment(key, ttl) do
    {_, count} = Cachex.incr(:cache, key, 1)
    if count == 1, do: Cachex.expire(:cache, key, ttl * 2)
    count
  end

  @doc "Forgets the counters whose bucket matches `fun`, for tests."
  @spec reset((term() -> boolean())) :: :ok
  def reset(fun) do
    {:ok, keys} = Cachex.keys(:cache)
    for {bucket, window} = key <- keys, is_integer(window), fun.(bucket), do: Cachex.del(:cache, key)
    :ok
  end
end
