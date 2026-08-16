defmodule Brando.Tenant.PublicDataMigrator do
  @moduledoc "Copies legacy public-schema content into a migrated tenant schema."

  @callback migrate(source_prefix :: String.t(), target_prefix :: String.t()) ::
              :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def migrate(source_prefix, target_prefix) do
    Brando.Tenant.PublicDataMigrator.Postgres.migrate(source_prefix, target_prefix)
  end
end
