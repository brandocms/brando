defmodule Brando.Forms.RateLimit do
  @moduledoc """
  Limits form submissions per visitor and per form, in fixed windows.

      config :brando, Brando.Forms,
        rate_limit: [window: :timer.minutes(10), per_visitor: 10, per_form: 200]

  Every post counts against its visitor (`check_visitor/3`), before Turnstile
  is asked, so one visitor cannot make many Turnstile calls. Only a
  submission that passed Turnstile and validation counts against the form
  (`count_form/2`), so posts that are refused cannot use up the form's budget
  and block it for everyone else.

  Visitors are counted by a hash of their IP address. Counts live in the
  `:cache` Cachex cache, so each node counts its own (`Brando.RateLimit`).
  """

  @defaults [window: :timer.minutes(10), per_visitor: 10, per_form: 200]

  @doc """
  Counts a post from the visitor `ip_hash`. `:ok` while the visitor is within
  its limit and the form's budget is not used up; the form's count is only
  read.
  """
  @spec check_visitor(String.t(), String.t(), String.t() | nil) :: :ok | {:error, :rate_limited}
  def check_visitor(scope, form_key, ip_hash) do
    config = config()
    window = window(config)

    cond do
      count({:form_rate, scope, form_key, ip_hash, window}, config[:window]) > config[:per_visitor] ->
        {:error, :rate_limited}

      current({:form_rate, scope, form_key, window}) >= config[:per_form] ->
        {:error, :rate_limited}

      true ->
        :ok
    end
  end

  @doc """
  Counts a submission the form is about to store. `:ok` while the form is
  within its limit.
  """
  @spec count_form(String.t(), String.t()) :: :ok | {:error, :rate_limited}
  def count_form(scope, form_key) do
    config = config()

    if count({:form_rate, scope, form_key, window(config)}, config[:window]) <= config[:per_form],
      do: :ok,
      else: {:error, :rate_limited}
  end

  @doc false
  # Forgets every count, for tests. Clearing the whole cache would also drop
  # the warm caches other tests read without a database connection.
  def reset do
    {:ok, keys} = Cachex.keys(:cache)
    for key <- keys, is_tuple(key) and elem(key, 0) == :form_rate, do: Cachex.del(:cache, key)
    :ok
  end

  defp config, do: Keyword.merge(@defaults, Application.get_env(:brando, Brando.Forms, [])[:rate_limit] || [])
  defp window(config), do: div(System.system_time(:millisecond), config[:window])
  defp count(key, ttl), do: Brando.RateLimit.increment(key, ttl)

  defp current(key) do
    case Cachex.get(:cache, key) do
      {:ok, count} when is_integer(count) -> count
      _ -> 0
    end
  end
end
