defmodule Brando.Type.Image do
  @moduledoc """
  Defines a type for an image field.
  """

  @behaviour Ecto.Type

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :string

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val), do: {:ok, val}

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: false

  @doc """
  When loading `roles` from the database, we are guaranteed to
  receive an integer (as database are stricts) and we will
  just return it to be stored in the model struct.
  """
  def load(val) do
    {:ok, val}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val), do: {:ok, val}
end