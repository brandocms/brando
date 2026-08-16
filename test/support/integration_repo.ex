defmodule Brando.IntegrationRepo do
  @moduledoc """
  Starts an isolated PostgreSQL repo for integration tests and restores its
  application configuration when the test module exits.
  """

  @doc "Starts `repo` with the integration database connection options."
  @spec start(module()) :: :ok
  def start(repo) do
    repo_options =
      BrandoIntegration.Repo.config()
      |> Keyword.take([:database, :hostname, :password, :port, :socket_options, :ssl, :username])
      |> Keyword.merge(pool: DBConnection.ConnectionPool, pool_size: 3)

    previous_repo_config = Application.fetch_env(:brando, repo)
    Application.put_env(:brando, repo, repo_options)
    {:ok, repo_pid} = repo.start_link()

    ExUnit.Callbacks.on_exit(fn ->
      stop(repo_pid)
      restore_env(repo, previous_repo_config)
    end)

    :ok
  end

  @doc "Restores a previously captured Brando application environment value."
  @spec restore_env(atom() | module(), {:ok, term()} | :error) :: :ok
  def restore_env(key, {:ok, value}), do: Application.put_env(:brando, key, value)
  def restore_env(key, :error), do: Application.delete_env(:brando, key)

  defp stop(repo_pid) do
    GenServer.stop(repo_pid)
  catch
    :exit, _reason -> :ok
  end
end
