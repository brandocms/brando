defimpl Jason.EncodeError, for: Tuple do
  def encode(tuple, _) do
    tuple
    |> Tuple.to_list()
    |> Jason.encode!()
  end
end
