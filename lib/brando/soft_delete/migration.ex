defmodule Brando.SoftDelete.Migration do
  @moduledoc """
  Macro for adding field to migration.
  """

  @doc """
  Add soft delete field to migration
  """
  defmacro soft_delete do
    quote do
      add :deleted_at, :utc_datetime, []
    end
  end
end
