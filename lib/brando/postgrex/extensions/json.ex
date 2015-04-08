defmodule Brando.Postgrex.Extension.JSON do
  alias Postgrex.TypeInfo

  @behaviour Postgrex.Extension

  def init(_parameters, opts),
    do: Keyword.fetch!(opts, :library)

  def matching(_library),
    do: [type: "json"]

  def format(_library),
    do: :binary

  def encode(%TypeInfo{type: "json"}, map, _state, library) do
    library.encode!(map)
  end

  def decode(%TypeInfo{type: "json"}, json, _state, library) do
    library.decode!(json)
  end
end