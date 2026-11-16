defmodule Brando.Environments.Migrator do
  @moduledoc """
  Runs application-owned tenant migrations inside one environment schema.

  Tenant migrations live under the configured repository's
  `priv/repo/tenant_migrations` directory by default. Applications can set
  `config :brando, :tenant_migrations_path, path` when they keep migrations
  elsewhere.

  A migrator may also implement `migrate/3`, which takes options:
  `Brando.Environments.create_environment/3` calls it with `log: :debug`, the
  level for the migrations' instructions (`Ecto.Migrator.run/4`'s `:log`), so
  a create does not log each one at info. `migrate/2` runs them at info, as
  `mix brando.migrate --tenants` prints them.
  """

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Tenant

  @callback migrate(Site.t(), Environment.t()) :: {:ok, [integer()]} | {:error, term()}
  @callback migrate(Site.t(), Environment.t(), keyword()) :: {:ok, [integer()]} | {:error, term()}
  @optional_callbacks migrate: 3

  @behaviour __MODULE__

  @impl true
  def migrate(%Site{} = site, %Environment{} = environment), do: migrate(site, environment, [])

  @impl true
  def migrate(%Site{} = site, %Environment{} = environment, opts) do
    prefix = Tenant.prefix(site, environment)

    try do
      versions =
        Ecto.Migrator.run(repo(), migrations_path(), :up,
          all: true,
          prefix: prefix,
          log: Keyword.get(opts, :log, :info)
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
