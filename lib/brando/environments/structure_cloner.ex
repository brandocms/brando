defmodule Brando.Environments.StructureCloner do
  @moduledoc """
  Copies table structure, without data, into a freshly created environment schema.

  `public` always holds the application's content tables, because ordinary
  migrations create them there in every tenancy mode. It is therefore the
  canonical structural template for a new environment, and provisioning clones
  from it rather than requiring applications to restate every table as a tenant
  migration.

  Tenant migrations still run afterwards, and are reserved for evolving existing
  environments.
  """

  @callback clone_structure(source_prefix :: String.t(), target_prefix :: String.t()) ::
              :ok | {:error, term()}
end
