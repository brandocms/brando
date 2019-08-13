defmodule Brando.JSONLD do
  @doc """
  Converts struct to JSON. Strips out all nil fields
  """

  @spec to_json(atom | %{:__struct__ => atom, optional(atom) => any}) :: any
  def to_json(struct) do
    map = to_slim_map(struct)
    Jason.encode!(map)
  end

  defp to_slim_map(struct) do
    for {k, v} <- Map.from_struct(struct),
        v != nil,
        into: %{} do
      {k, if(is_map(v), do: to_slim_map(v), else: v)}
    end
  end

  def to_date(date) do
    Timex.format!(Timex.to_date(date), "{ISOdate}")
  end

  def to_datetime(datetime) do
    Timex.format!(Timex.to_datetime(datetime, "Etc/UTC"), "{ISO:Extended:Z}")
  end
end
