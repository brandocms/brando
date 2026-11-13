defmodule Brando.Tenant.PublicDataMigrator do
  @moduledoc "Copies legacy public-schema content into a migrated tenant schema."

  @callback migrate(source_prefix :: String.t(), target_prefix :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Whether `migrate/2` relocates the content rather than copying it, leaving
  the target the only copy. `Brando.Tenant.Migration.migrate_public/3` then
  keeps the new site when a step after the migrator fails. Defaults to
  `false` when not implemented.
  """
  @callback relocates?() :: boolean()

  @optional_callbacks relocates?: 0

  @behaviour __MODULE__

  @impl true
  def migrate(source_prefix, target_prefix) do
    Brando.Tenant.PublicDataMigrator.Postgres.migrate(source_prefix, target_prefix)
  end
end
