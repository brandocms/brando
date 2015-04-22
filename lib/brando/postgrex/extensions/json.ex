defmodule Brando.Postgrex.Extension.JSON do
  @moduledoc """
  Postgrex Extension for the JSON type.
  Encodes and decodes json through Poison.
  """
  alias Postgrex.TypeInfo

  @behaviour Postgrex.Extension

  def init(_parameters, opts),
    do: Keyword.fetch!(opts, :library)

  def matching(_library),
    do: [type: "json"]

  def format(_library),
    do: :binary

  def encode(%TypeInfo{type: "json"}, map, _state, library) do
    library.encode!(map, keys: :atoms!)
  end

  def decode(%TypeInfo{type: "json"}, json, _state, library) do
    library.decode!(json, keys: :atoms!)
  end
end