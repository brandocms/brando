defmodule Brando.Type.Module do
  @moduledoc """
  Defines a type for casting to module
  """
  use Ecto.Type

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :string

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(binary) when is_binary(binary) do
    module =
      binary
      |> List.wrap()
      |> Module.concat()

    {:ok, module}
  end

  def cast(module) when is_atom(module) do
    {:ok, module}
  end

  # Cast anything else is a failure
  def cast(_), do: :error

  def blank?(""), do: true
  def blank?(_), do: false

  @doc """
  Loading from string
  """
  def cast(binary) when is_binary(binary) do
    module =
      binary
      |> List.wrap()
      |> Module.concat()

    {:ok, module}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(binary) when is_binary(binary) do
    module =
      binary
      |> List.wrap()
      |> Module.concat()

    {:ok, module}
  end

  def dump(module) when is_atom(module) do
    {:ok, module}
  end

  def dump(_), do: :error
end
