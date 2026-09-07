defmodule Brando.Blueprint.Migrations.Plan do
  @moduledoc """
  A read-only storage change prepared for review before persistence.

  The migration and snapshot must be committed together through
  `Brando.Blueprint.Migrations.commit_plan/1`. Do not write either file through
  a generic source writer: the commit rechecks history and the compiled schema
  under the existing migration/snapshot locks.
  """

  @enforce_keys [:module, :options, :history_digest, :schema, :result, :metadata]
  defstruct [:module, :options, :history_digest, :schema, :result, :metadata, :migration_source, :snapshot]

  @type t :: %__MODULE__{
          module: module(),
          options: keyword(),
          history_digest: binary(),
          schema: map(),
          result: :ok | :noop,
          metadata: map(),
          migration_source: String.t() | nil,
          snapshot: Brando.Blueprint.Snapshot.t() | nil
        }
end
