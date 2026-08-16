defmodule Brando.Environments.SchemaCloner do
  @moduledoc """
  Behaviour for making a complete copy of one PostgreSQL schema under another
  schema name.
  """

  @callback clone_schema(source_prefix :: String.t(), target_prefix :: String.t()) ::
              :ok | {:error, term()}
end
