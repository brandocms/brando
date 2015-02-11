defmodule Brando.Type.Status do
  @moduledoc """
  Defines a type for managing status in post models.
  """

  @behaviour Ecto.Type
  @status_codes %{draft: 0, pending: 1, published: 2, deleted: 3}

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :integer

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(atom) when is_atom(atom), do: {:ok, @status_codes[atom]}
  def cast(binary) when is_binary(binary), do: {:ok, String.to_integer(binary)}

  @doc """
  Cast anything else is a failure
  """
  def cast(_), do: :error

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: false

  @doc """
  When loading `roles` from the database, we are guaranteed to
  receive an integer (as database are stricts) and we will
  just return it to be stored in the model struct.
  """
  def load(status) when is_integer(status) do
    case status do
      0 -> {:ok, :draft}
      1 -> {:ok, :pending}
      2 -> {:ok, :published}
      3 -> {:ok, :deleted}
    end
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(atom) when is_atom(atom), do: {:ok, @status_codes[atom]}
  def dump(binary) when is_binary(binary), do: {:ok, String.to_integer(binary)}
  def dump(integer) when is_integer(integer), do: {:ok, integer}
  def dump(_), do: :errorend
end