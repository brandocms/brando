defimpl Poison.Encoder, for: Tuple do
  def encode(tuple, _) do
    tuple
    |> Tuple.to_list
    |> Poison.encode!
  end
end
