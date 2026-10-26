defmodule Brando.Forms.RateLimit do
  @moduledoc """
  Limits form submissions per visitor and per form, in fixed windows.

      config :brando, Brando.Forms,
        rate_limit: [window: :timer.minutes(10), per_visitor: 10, per_form: 200]

  Visitors are counted by a hash of their IP address. Counts live in the
  `:cache` Cachex cache, so each node counts its own (`Brando.RateLimit`).

  A form's confirmation to the visitor goes to the address filled in, which
  can be anyone's. So that the site does not send one person email after
  email, each address gets a few confirmations an hour, from all forms
  together; past that, the submission is kept and notified as usual, without
  the confirmation:

      config :brando, Brando.Forms,
        confirmation_limit: [window: :timer.hours(1), per_address: 3]
  """

  @defaults [window: :timer.minutes(10), per_visitor: 10, per_form: 200]
  @confirmation_defaults [window: :timer.hours(1), per_address: 3]

  @doc "Counts a submission; `:ok` while both counts are within their limits."
  @spec hit(String.t(), String.t(), String.t()) :: :ok | {:error, :rate_limited}
  def hit(scope, form_key, ip_hash) do
    config = Keyword.merge(@defaults, Application.get_env(:brando, Brando.Forms, [])[:rate_limit] || [])
    window = div(System.system_time(:millisecond), config[:window])

    visitor = count({:form_rate, scope, form_key, ip_hash, window}, config[:window])
    form = count({:form_rate, scope, form_key, window}, config[:window])

    if visitor <= config[:per_visitor] and form <= config[:per_form], do: :ok, else: {:error, :rate_limited}
  end

  @doc "Counts a confirmation to `address`; `:ok` while the address is within its limit."
  @spec confirmation(String.t(), String.t()) :: :ok | {:error, :rate_limited}
  def confirmation(scope, address) do
    config =
      Keyword.merge(@confirmation_defaults, Application.get_env(:brando, Brando.Forms, [])[:confirmation_limit] || [])

    address = address |> String.trim() |> String.downcase()
    hash = :sha256 |> :crypto.hash(address) |> Base.encode16(case: :lower)

    case Brando.RateLimit.hit({:form_confirmation, scope, hash}, config[:per_address], config[:window]) do
      :ok -> :ok
      {:error, :rate_limited, _retry_after} -> {:error, :rate_limited}
    end
  end

  @doc false
  # Forgets every count, for tests. Clearing the whole cache would also drop
  # the warm caches other tests read without a database connection.
  def reset do
    {:ok, keys} = Cachex.keys(:cache)
    for key <- keys, is_tuple(key) and elem(key, 0) == :form_rate, do: Cachex.del(:cache, key)
    Brando.RateLimit.reset(&match?({:form_confirmation, _, _}, &1))
  end

  defp count(key, ttl), do: Brando.RateLimit.increment(key, ttl)
end
