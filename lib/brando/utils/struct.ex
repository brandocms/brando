defmodule Brando.Utils.Struct do
  @moduledoc """
  Small struct-conversion helpers with no dependency on the general `Brando.Utils`
  module.
  """

  @doc """
  Converts a map with atom or string keys into `target_struct`.

  Unknown keys are discarded and existing atoms are reused rather than created.
  """
  @spec map_to_struct(map() | nil, module() | struct()) :: struct()
  def map_to_struct(nil, target_struct), do: struct(target_struct, %{})

  def map_to_struct(source_map, target_struct) when is_map(source_map) do
    target_keys = target_struct |> struct([]) |> Map.from_struct() |> Map.keys()
    string_keys = Map.new(target_keys, &{Atom.to_string(&1), &1})

    string_values =
      Enum.reduce(source_map, %{}, fn
        {key, value}, acc when is_binary(key) ->
          case string_keys do
            %{^key => atom_key} -> Map.put(acc, atom_key, value)
            _ -> acc
          end

        _entry, acc ->
          acc
      end)

    string_values
    |> Map.merge(Map.take(source_map, target_keys))
    |> then(&struct(target_struct, &1))
  end
end
