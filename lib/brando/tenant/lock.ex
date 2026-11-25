defmodule Brando.Tenant.Lock do
  @moduledoc false

  alias Brando.Repo

  @doc "Runs `fun` holding the session advisory lock `key`, waiting for it."
  @spec with(String.t(), (-> result)) :: result when result: var
  def with(key, fun) when is_binary(key) and is_function(fun, 0) do
    checkout(fn repo ->
      Ecto.Adapters.SQL.query!(repo, "SELECT pg_advisory_lock(hashtextextended($1, 0))", [key])
      run_and_unlock(repo, key, fun)
    end)
  end

  @doc """
  Runs `fun` holding the session advisory lock `key` when no other session
  holds it, and returns `:busy` without running it when one does.
  """
  @spec try_with(String.t(), (-> result)) :: result | :busy when result: var
  def try_with(key, fun) when is_binary(key) and is_function(fun, 0) do
    checkout(fn repo ->
      case Ecto.Adapters.SQL.query!(repo, "SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [key]) do
        %{rows: [[true]]} -> run_and_unlock(repo, key, fun)
        %{rows: [[false]]} -> :busy
      end
    end)
  end

  @doc """
  Runs `fun` holding the session advisory lock `key`, waiting up to
  `timeout` milliseconds for it and for a connection to hold it on, and
  returns `{:ok, result}`. Returns `:busy` without running `fun` when the
  lock is still held, or no connection free, at the deadline. Once started,
  `fun` runs for as long as it takes.
  """
  @spec with_timeout(String.t(), non_neg_integer(), (-> result)) :: {:ok, result} | :busy when result: var
  def with_timeout(key, timeout, fun) when is_binary(key) and is_integer(timeout) and is_function(fun, 0) do
    deadline = System.monotonic_time(:millisecond) + timeout
    try_until(key, deadline, fun)
  end

  @retry_interval 50

  defp try_until(key, deadline, fun) do
    case attempt(key, deadline, fun) do
      {:ran, result} ->
        {:ok, result}

      {:raised, kind, reason, stacktrace} ->
        :erlang.raise(kind, reason, stacktrace)

      :not_taken ->
        if System.monotonic_time(:millisecond) + @retry_interval <= deadline do
          Process.sleep(@retry_interval)
          try_until(key, deadline, fun)
        else
          :busy
        end
    end
  end

  @started {__MODULE__, :started}

  # Without queueing for a connection: a busy pool is retried like a held
  # lock, so the wait ends at the deadline. What `fun` raises is carried out
  # of the checkout, and a connection error once `fun` has started (in the
  # unlock) is raised, so that `fun` never runs twice.
  defp attempt(key, deadline, fun) do
    checkout(&try_lock_and_run(&1, key, deadline, fun), queue: false)
  rescue
    error in DBConnection.ConnectionError ->
      if Process.get(@started), do: reraise(error, __STACKTRACE__), else: :not_taken
  after
    Process.delete(@started)
  end

  defp try_lock_and_run(repo, key, deadline, fun) do
    case Ecto.Adapters.SQL.query!(repo, "SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [key]) do
      %{rows: [[true]]} -> run_and_unlock(repo, key, fn -> run_before(deadline, fun) end)
      %{rows: [[false]]} -> :not_taken
    end
  end

  defp run_before(deadline, fun) do
    if System.monotonic_time(:millisecond) <= deadline do
      Process.put(@started, true)

      try do
        {:ran, fun.()}
      catch
        kind, reason -> {:raised, kind, reason, __STACKTRACE__}
      end
    else
      :not_taken
    end
  end

  @doc "Whether another session holds the advisory lock `key` now."
  @spec held?(String.t()) :: boolean()
  def held?(key) when is_binary(key), do: try_with(key, fn -> :free end) == :busy

  @doc "The lock an environment operation (copy, live switch, deletion) of a site holds."
  @spec environment_operation_key(pos_integer()) :: String.t()
  def environment_operation_key(site_id), do: "brando:environment-operation:#{site_id}"

  @doc """
  The lock a site's static deploys, rollbacks and prunes hold
  (`Brando.SSG.Deploy`), and a change of its delivery
  (`Brando.Tenant.Setup.update_delivery/4`) inside the lifecycle lock. Nothing
  takes the lifecycle lock while holding this one.
  """
  @spec deploy_key(pos_integer()) :: String.t()
  def deploy_key(site_id), do: "ssg-deploy:#{site_id}"

  @doc """
  The lock a change to a site's files under `ssg/deploy/` holds
  (`Brando.SSG.DeployFiles`): its key, its accepted host keys. A deploy reads
  them without it, as each is written whole.
  """
  @spec deploy_files_key(pos_integer()) :: String.t()
  def deploy_files_key(site_id), do: "ssg-deploy-files:#{site_id}"

  @doc "The lock a site's lifecycle operation (provisioning, archiving, deletion) holds."
  @spec lifecycle_key(String.t()) :: String.t()
  def lifecycle_key(site_key), do: "brando:site-lifecycle:#{site_key}"

  defp checkout(fun, opts \\ []) do
    repo = Repo.repo()
    repo.checkout(fn -> fun.(repo) end, Keyword.put(opts, :timeout, :infinity))
  end

  defp run_and_unlock(repo, key, fun) do
    fun.()
  after
    Ecto.Adapters.SQL.query!(repo, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
  end
end
