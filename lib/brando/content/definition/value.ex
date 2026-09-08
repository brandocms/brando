defmodule Brando.Content.Definition.Value do
  @moduledoc false

  alias Brando.Content.Definition.Error

  def plain(%{__struct__: schema} = value) do
    cond do
      function_exported?(schema, :__schema__, 1) ->
        fields = schema.__schema__(:fields) -- schema.__schema__(:primary_key)
        value |> Map.take(fields) |> plain()

      schema in [Date, DateTime, NaiveDateTime, Time] ->
        to_string(value)

      true ->
        Error.raise!(inspect(schema), "cannot serialize this value")
    end
  end

  def plain(value) when is_map(value), do: Map.new(value, fn {key, val} -> {to_string(key), plain(val)} end)

  def plain(value) when is_list(value) do
    if value != [] and Keyword.keyword?(value), do: value |> Map.new() |> plain(), else: Enum.map(value, &plain/1)
  end

  def plain(value) when value in [true, false, nil], do: value
  def plain(value) when is_atom(value), do: Atom.to_string(value)
  def plain(value) when is_binary(value) or is_number(value), do: value
  def plain(value), do: Error.raise!(inspect(value), "expected a serializable literal")

  def object(value) when is_map(value), do: plain(value)

  def object(value) when is_list(value) do
    if Keyword.keyword?(value),
      do: value |> Map.new() |> plain(),
      else: Error.raise!("definition", "expected a map or keyword list")
  end

  def object(nil), do: %{}
  def object(_), do: Error.raise!("definition", "expected a map or keyword list")

  def digest(value), do: :crypto.hash(:sha256, :erlang.term_to_binary(canonical(value))) |> Base.encode16(case: :lower)

  # Maps are encoded as sorted pairs so hashes are independent of VM map layout.
  defp canonical(value) when is_map(value), do: value |> Enum.sort() |> Enum.map(fn {k, v} -> {k, canonical(v)} end)
  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value

  def unique!(values, path) do
    if length(Enum.uniq(values)) != length(values), do: Error.raise!(path, "duplicate identity")
    values
  end

  def nonempty!(value, path) when is_binary(value) do
    if String.trim(value) == "", do: Error.raise!(path, "must not be empty")
    value
  end

  def nonempty!(_, path), do: Error.raise!(path, "expected a nonempty string")

  def keys!(map, allowed, path) do
    case Map.keys(map) -- Enum.map(allowed, &to_string/1) do
      [] -> :ok
      unknown -> Error.raise!(path, "unknown fields #{inspect(Enum.sort(unknown))}")
    end
  end
end
