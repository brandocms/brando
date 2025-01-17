defmodule Brando.JSONLD do
  @moduledoc """
  JSON-LD is a lightweight Linked Data format.
  """
  def extract_json_ld(module, data, extra_fields \\ []) do
    json_ld_data =
      module
      |> Spark.Dsl.Extension.get_entities(:json_ld_schemas)
      |> List.first()

    fields = json_ld_data.fields ++ extra_fields
    schema = json_ld_data.schema

    Enum.reduce(fields, struct(schema), fn
      %{name: name, type: :identity, value_fn: _}, acc ->
        result = %{"@id": "#{Brando.Utils.hostname()}/#identity"}
        Map.put(acc, name, result)

      %{name: name, type: :datetime, value_fn: value_fn}, acc ->
        result =
          data
          |> value_fn.()
          |> Brando.JSONLD.to_datetime()

        Map.put(acc, name, result)

      %{name: name, type: :date, value_fn: value_fn}, acc ->
        result =
          data
          |> value_fn.()
          |> Brando.JSONLD.to_date()

        Map.put(acc, name, result)

      %{name: name, type: :image, value_fn: value_fn}, acc ->
        result = Brando.JSONLD.Schema.ImageObject.build(value_fn.(data))
        Map.put(acc, name, result)

      %{name: name, type: :current_url, value_fn: _}, acc ->
        result = data.__meta__.current_url
        Map.put(acc, name, result)

      %{name: name, type: :language, value_fn: _}, acc ->
        result = Map.get(data, :language, get_in(data, [Access.key(:__meta__, %{}), :language]))
        Map.put(acc, name, result)

      %{name: name, type: :string, value_fn: value_fn}, acc ->
        result = value_fn.(data)
        Map.put(acc, name, result)

      %{name: name, type: :integer, value_fn: value_fn}, acc ->
        result = value_fn.(data)
        Map.put(acc, name, result)

      %{name: name, type: schema, value_fn: value_fn}, acc ->
        result = schema.build(value_fn.(data))
        Map.put(acc, name, result)
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

    if key_count > 0, do: to_slim_map(map)
  end

  defp slim_map(value), do: value

  @doc """
  Convert date to ISO friendly string
  """
  @spec to_date(date :: any) :: binary
  def to_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

  @doc """
  Convert datetime to ISO friendly string
  """
  @spec to_datetime(datetime :: any) :: binary
  def to_datetime(%NaiveDateTime{} = datetime), do: datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  def to_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
