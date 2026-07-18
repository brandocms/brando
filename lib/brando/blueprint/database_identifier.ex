defmodule Brando.Blueprint.DatabaseIdentifier do
  @moduledoc """
  Builds PostgreSQL-safe names for Blueprint indexes and constraints.

  PostgreSQL stores at most 63 bytes for an identifier. It silently truncates
  longer names, so runtime changeset constraints must use the same stored name
  as generated migrations or database violations cannot become changeset
  errors.
  """

  @max_bytes 63

  @doc """
  Returns an index name using Ecto's conventional table/field ordering.
  """
  @spec index_name(String.t() | atom(), [String.t() | atom()]) :: String.t()
  def index_name(table, fields) do
    normalize(Enum.join([table | fields] ++ ["index"], "_"))
  end

  @doc """
  Returns a foreign-key name using Ecto's conventional table/field ordering.
  """
  @spec foreign_key_name(String.t() | atom(), String.t() | atom()) :: String.t()
  def foreign_key_name(table, field) do
    normalize(Enum.join([table, field, "fkey"], "_"))
  end

  @doc """
  Normalizes a database identifier to PostgreSQL's 63-byte storage limit.

  UTF-8 identifiers are shortened only at a valid codepoint boundary.
  """
  @spec normalize(String.t() | atom()) :: String.t()
  def normalize(identifier) do
    identifier = to_string(identifier)

    if byte_size(identifier) <= @max_bytes do
      identifier
    else
      truncate_utf8(identifier, @max_bytes)
    end
  end

  defp truncate_utf8(identifier, byte_count) do
    candidate = binary_part(identifier, 0, byte_count)

    if String.valid?(candidate) do
      candidate
    else
      truncate_utf8(identifier, byte_count - 1)
    end
  end
end
