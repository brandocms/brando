defmodule Brando.SoftDelete.Schema do
  @moduledoc """
  Macro for adding field to schema.

  ## Example

      use Brando.SoftDelete.Schema, obfuscated_fields: [:slug, :key]

  Obfuscated fields will have a random string added to it when soft
  deleting, and reset to its original value if undeleted. This should
  only be used for values that must be unique.
  """

  defmacro __using__(opts) do
    obfuscated_fields = Keyword.get(opts, :obfuscated_fields, [])

    quote do
      import unquote(__MODULE__)

      def __soft_delete__, do: true
      def __soft_delete__(:obfuscated_fields), do: unquote(obfuscated_fields)
    end
  end

  @doc """
  Add soft delete field to schema
  """
  defmacro soft_delete do
    quote do
      field :deleted_at, :utc_datetime
    end
  end
end
