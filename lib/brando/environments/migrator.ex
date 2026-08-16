defmodule Brando.Environments.Migrator do
  @moduledoc """
  Runs application-owned tenant migrations inside one environment schema.

  Tenant migrations live under the configured repository's
  `priv/repo/tenant_migrations` directory by default. Applications can set
  `config :brando, :tenant_migrations_path, path` when they keep migrations
  elsewhere.
  """

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Tenant

  @callback migrate(Site.t(), Environment.t()) :: {:ok, [integer()]} | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def migrate(%Site{} = site, %Environment{} = environment) do
    prefix = Tenant.prefix(site, environment)

    try do
      versions =
        Ecto.Migrator.run(repo(), migrations_path(), :up,
          all: true,
          prefix: prefix
        )

      {:ok, versions}
    rescue
      exception -> {:error, exception}
    end
  end

  @spec migrations_path() :: String.t()
  def migrations_path do
    Brando.config(:tenant_migrations_path) ||
      Ecto.Migrator.migrations_path(repo(), "tenant_migrations")
  end

  defp repo, do: Brando.Repo.repo()
end
