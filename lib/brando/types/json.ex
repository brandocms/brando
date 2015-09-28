defmodule Brando.Type.Json do
  @moduledoc """
  Defines a type for json data when using Postgrex json type.
  """

  @behaviour Ecto.Type

  @doc """
  Returns the internal type representation of our `JSON` type for pg/postgrex
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(json) when is_map(json), do: {:ok, json}
  def cast(json) when is_list(json), do: {:ok, json}
  def cast(json) when is_binary(json), do: {:ok, Poison.decode!(json)}

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: false

  @doc """
  Load json from DB
  """
  def load(json) when is_map(json), do: {:ok, json}
  def load(json) when is_list(json), do: {:ok, json}

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(json) when is_map(json), do: {:ok, json}
  def dump(json) when is_list(json), do: {:ok, json}
  def dump(json) when is_binary(json), do: {:ok, Poison.decode!(json)}
end
