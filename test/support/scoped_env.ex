defmodule Brando.Test.ScopedEnv do
  @moduledoc """
  Configuration one test sees, and other tests running at the same time do
  not: `Brando.Test.Support.put_test_env/2` puts the keys in `@keys` here
  rather than into the application environment.

  `Brando.RuntimeConfig.get/1` (`Brando.config/1`) looks a key up for the
  calling process, then for each process in its `$callers`, before the
  application environment. That reaches what a test starts on its behalf: a
  LiveView mounted with `Phoenix.LiveViewTest.live/2` (which puts the test in
  its `$callers`), a Task, a `start_supervised` child. A long-lived process
  that does not carry the test in its `$callers` (one in the application's
  supervision tree) reads the application environment, as it does in a site.

  Only `Brando.RuntimeConfig.get/1` reads this, and only when Brando is
  compiled with `config :brando, scoped_test_env: true` (config/test.exs): a
  site's build has no lookup at all.
  """

  @table __MODULE__

  # Keys whose every read goes through `Brando.config/1`. Another key
  # set with `put_test_env/2` still changes the application environment, for
  # every test at once, so a module that sets one stays synchronous.
  @keys [:tenancy_mode, :authorization_mode]

  @doc "The keys `put/2` takes."
  @spec keys() :: [atom()]
  def keys, do: @keys

  @doc """
  Creates the table. Call it once, before any test runs; the table belongs to
  the calling process.
  """
  @spec install() :: :ok
  def install do
    @table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    :ok
  end

  @doc """
  Sets `key` for the calling process and the processes that carry it in
  their `$callers`, until `delete/1`.
  """
  @spec put(atom(), term()) :: :ok
  def put(key, value) when key in @keys do
    true = :ets.insert(@table, {{self(), key}, value})
    :ok
  end

  @doc "Removes what `put/2` set for `key` in `owner`."
  @spec delete(pid(), atom()) :: :ok
  def delete(owner, key) do
    true = :ets.delete(@table, {owner, key})
    :ok
  end

  @doc """
  The value set for `key` by the calling process or the first of its
  `$callers` that set one, or `:error`. Also `:error` before `install/0`
  (Brando reads its configuration while the tests compile).
  """
  @spec fetch(term()) :: {:ok, term()} | :error
  def fetch(key) when key in @keys do
    if :ets.whereis(@table) == :undefined do
      :error
    else
      lookup([self() | Process.get(:"$callers", [])], key)
    end
  end

  def fetch(_key), do: :error

  defp lookup([], _key), do: :error

  defp lookup([pid | rest], key) do
    case :ets.lookup(@table, {pid, key}) do
      [{_, value}] -> {:ok, value}
      [] -> lookup(rest, key)
    end
  end
end
