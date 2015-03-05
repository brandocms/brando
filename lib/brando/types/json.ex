defmodule Brando.Type.Json do
  @moduledoc """
  Defines a type for json data when using Postgrex json type.
  """

  @behaviour Ecto.Type

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(json), do: {:ok, json}

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: false

  @doc """
  When loading `roles` from the database, we are guaranteed to
  receive an integer (as database are stricts) and we will
  just return it to be stored in the model struct.
  """
  def load(json) do
    {:ok, json}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(json), do: {:ok, json}
end