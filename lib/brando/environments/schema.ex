defmodule Brando.Environments.Schema do
  @moduledoc """
  PostgreSQL schema lifecycle operations for named Brando environments.

  Prefixes are accepted only when they were produced by `Brando.Tenant`, then
  quoted before interpolation into DDL. Registry metadata remains in `public`;
  only environment content schemas are managed here.
  """

  alias Brando.Tenant
  alias Ecto.Adapters.SQL

  @spec create(String.t()) :: :ok | {:error, Exception.t()}
  def create(prefix) do
    with :ok <- validate_prefix(prefix),
         {:ok, _result} <- SQL.query(repo(), ~s|CREATE SCHEMA "#{prefix}"|, []) do
      :ok
    end
  end

  @spec drop(String.t()) :: :ok | {:error, Exception.t()}
  def drop(prefix) do
    with :ok <- validate_prefix(prefix),
         {:ok, _result} <- SQL.query(repo(), ~s|DROP SCHEMA IF EXISTS "#{prefix}" CASCADE|, []) do
      :ok
    end
  end

  @spec exists?(String.t()) :: boolean()
  def exists?(prefix) do
    with :ok <- validate_prefix(prefix),
         {:ok, %{rows: [[exists?]]}} <-
           SQL.query(
             repo(),
             "SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = $1)",
             [prefix]
           ) do
      exists?
    else
      _ -> false
    end
  end

  defp validate_prefix(prefix) do
    case Regex.run(~r/^tenant_([a-z0-9]+(?:-[a-z0-9]+)*)_([a-z0-9]+(?:-[a-z0-9]+)*)$/, prefix) do
      [^prefix, site_key, environment_key] ->
        if Tenant.prefix(site_key, environment_key) == prefix,
          do: :ok,
          else: {:error, ArgumentError.exception("invalid tenant prefix: #{inspect(prefix)}")}

      _ ->
        {:error, ArgumentError.exception("invalid tenant prefix: #{inspect(prefix)}")}
    end
  end

  defp repo, do: Brando.Repo.repo()
end
