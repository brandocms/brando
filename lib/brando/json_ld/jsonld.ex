defmodule Brando.JSONLD do
  @moduledoc """
  JSON LD helpers
  """

  @doc """
  Converts struct to JSON. Strips out all nil fields
  """
  @spec to_json(%{:__struct__ => atom, optional(atom) => any}) :: any
  def to_json(struct) do
    map = to_slim_map(struct)
    Jason.encode!(map)
  end

  defp to_slim_map(%_{} = struct) do
    for {k, v} <- Map.from_struct(struct),
        v != nil,
        into: %{} do
      {k, slim_map(v)}
    end
  end

  defp to_slim_map(map) when is_map(map) do
    for {k, v} <- map,
        v != nil,
        into: %{} do
      {k, slim_map(v)}
    end
  end

  defp slim_map(map) when is_map(map) do
    map_without_nils = :maps.filter(fn _, v -> v != nil end, map)

    key_count =
      map_without_nils
      |> Map.keys()
      |> Enum.reject(&String.starts_with?(to_string(&1), ["@context", "@type"]))
      |> Enum.count()

    if key_count > 0, do: to_slim_map(map), else: nil
  end

  defp slim_map(value), do: value

  @doc """
  Convert date to ISO friendly string
  """
  @spec to_date(date :: any) :: String.t()
  def to_date(date),
    do: Timex.format!(Timex.to_date(date), "{ISOdate}")

  @doc """
  Convert datetime to ISO friendly string
  """
  @spec to_datetime(datetime :: any) :: String.t()
  def to_datetime(datetime),
    do: Timex.format!(Timex.to_datetime(datetime, "Etc/UTC"), "{ISO:Extended:Z}")
end
