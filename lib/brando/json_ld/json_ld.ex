defmodule Brando.JSONLD do
  @moduledoc """
  JSON-LD is a lightweight Linked Data format.
  """

  @doc """
  Allows us to have same formatting when adding additional json_ld fields in a controller
  """
  def convert_format(fields) do
    Enum.reduce(fields, [], fn
      {name, {:references, target}}, acc ->
        [{name, {:references, target}} | acc]

      {name, :string, path}, acc when is_list(path) ->
        [{name, {:string, path}} | acc]

      {name, :string, path, mutation_function}, acc when is_list(path) ->
        [{name, {{:string, path}, {:mutator, mutation_function}}} | acc]

      {name, :string, mutation_function}, acc when is_function(mutation_function) ->
        [{name, {:string, mutation_function}} | acc]

      {name, schema, nil}, _acc ->
        raise "=> JSONLD/Schema >> Populating a field as schema requires a populator function - #{
                name
              } - #{inspect(schema)}"

      {name, schema, _}, _acc when is_binary(schema) ->
        raise "=> JSONLD/Schema >> Populating a field as schema requires a schema as second arg - #{
                name
              } - #{inspect(schema)}"

      {name, schema, path}, acc when is_list(path) ->
        [{name, {schema, path}} | acc]

      {name, schema, populator_function}, acc ->
        [{name, {schema, populator_function}} | acc]

      {name, schema, path, mutation_function}, acc
      when not is_binary(schema) and is_list(path) ->
        [{name, {{schema, path}, mutation_function}} | acc]
    end)
  end

  @doc """
  Converts struct to JSON. Strips out all nil fields
  """
  @spec to_json(%{:__struct__ => atom, optional(atom) => any}) :: any
  def to_json(struct) do
    map = to_slim_map(struct)
    Jason.encode!(map)
  end

  @doc """
  Convert date to ISO friendly string
  """
  @spec to_date(date :: any) :: binary
  def to_date(date),
    do: Timex.format!(Timex.to_date(date), "{ISOdate}")

  @doc """
  Convert datetime to ISO friendly string
  """
  @spec to_datetime(datetime :: any) :: binary
  def to_datetime(datetime),
    do: Timex.format!(Timex.to_datetime(datetime, "Etc/UTC"), "{ISO:Extended:Z}")

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
end
