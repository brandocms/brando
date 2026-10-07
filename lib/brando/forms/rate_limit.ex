defmodule Brando.Forms.RateLimit do
  @moduledoc """
  Limits form submissions per visitor and per form, in fixed windows.

      config :brando, Brando.Forms,
        rate_limit: [window: :timer.minutes(10), per_visitor: 10, per_form: 200]

  Visitors are counted by a hash of their IP address. Counts live in the
  `:cache` Cachex cache, so each node counts its own (`Brando.RateLimit`).
  """

  @defaults [window: :timer.minutes(10), per_visitor: 10, per_form: 200]

  @doc "Counts a submission; `:ok` while both counts are within their limits."
  @spec hit(String.t(), String.t(), String.t()) :: :ok | {:error, :rate_limited}
  def hit(scope, form_key, ip_hash) do
    config = Keyword.merge(@defaults, Application.get_env(:brando, Brando.Forms, [])[:rate_limit] || [])
    window = div(System.system_time(:millisecond), config[:window])

    visitor = count({:form_rate, scope, form_key, ip_hash, window}, config[:window])
    form = count({:form_rate, scope, form_key, window}, config[:window])

    if visitor <= config[:per_visitor] and form <= config[:per_form], do: :ok, else: {:error, :rate_limited}
  end

  @doc false
  # Forgets every count, for tests. Clearing the whole cache would also drop
  # the warm caches other tests read without a database connection.
  def reset do
    {:ok, keys} = Cachex.keys(:cache)
    for key <- keys, is_tuple(key) and elem(key, 0) == :form_rate, do: Cachex.del(:cache, key)
    :ok
  end

  defp count(key, ttl), do: Brando.RateLimit.increment(key, ttl)
end
