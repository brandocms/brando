defmodule Brando.Type.Json do
  @moduledoc """
  Defines a type for casting to json
  """
  use Ecto.Type

  @doc """
  Returns the internal type representation of our `Module` type for pg
  """
  def type, do: :map

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(map) when is_map(map) do
    {:ok, map}
  end

  # Cast anything else is a failure
  def cast(_), do: :error

  def load(map) do
    {:ok, map}
  end

  def blank?(""), do: true
  def blank?(_), do: false

  def dump(nil) do
    {:ok, nil}
  end

  def dump(map) when is_map(map) do
    # clean up the map

    map =
      Enum.reduce(map, %{}, fn {key, value}, acc ->
        cleaned_value =
          Enum.reduce(value, %{}, fn
            {"_unused_" <> _k, _v}, inner_acc -> inner_acc
            {k, v}, inner_acc -> Map.put(inner_acc, k, v)
          end)

        Map.put(acc, key, cleaned_value)
      end)

    {:ok, map}
  end

  def dump(_), do: :error
end
