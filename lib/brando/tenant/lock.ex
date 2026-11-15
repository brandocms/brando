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

  @doc "Whether another session holds the advisory lock `key` now."
  @spec held?(String.t()) :: boolean()
  def held?(key) when is_binary(key), do: try_with(key, fn -> :free end) == :busy

  @doc "The lock an environment operation (copy, live switch, deletion) of a site holds."
  @spec environment_operation_key(pos_integer()) :: String.t()
  def environment_operation_key(site_id), do: "brando:environment-operation:#{site_id}"

  @doc "The lock a site's lifecycle operation (provisioning, archiving, deletion) holds."
  @spec lifecycle_key(String.t()) :: String.t()
  def lifecycle_key(site_key), do: "brando:site-lifecycle:#{site_key}"

  defp checkout(fun) do
    repo = Repo.repo()
    repo.checkout(fn -> fun.(repo) end, timeout: :infinity)
  end

  defp run_and_unlock(repo, key, fun) do
    fun.()
  after
    Ecto.Adapters.SQL.query!(repo, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
  end
end
