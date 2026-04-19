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

      %{name: name, type: {:list, schema}, value_fn: value_fn}, acc ->
        items = value_fn.(data)
        result = if is_list(items), do: Enum.map(items, &schema.build/1), else: nil
        Map.put(acc, name, result)

      %{name: name, type: schema, value_fn: value_fn}, acc ->
        result = schema.build(value_fn.(data))
        Map.put(acc, name, result)
    end)
    |> maybe_override_type(data)
    |> maybe_add_id(data)
  end

  defp maybe_add_id(struct, %{__meta__: %{current_url: url}}) do
    type =
      struct
      |> Map.get(:"@type", "")
      |> to_string()
      |> String.downcase()

    Map.put(struct, :"@id", "#{url}##{type}")
  end

  defp maybe_add_id(struct, _), do: struct

  defp maybe_override_type(struct, %{json_ld_type: type}) when is_binary(type) do
    Map.put(struct, :"@type", type)
  end

  defp maybe_override_type(struct, _), do: struct

  @doc """
  Converts struct to JSON. Strips out all nil fields
  """
  @spec to_json(%{:__struct__ => atom, optional(atom) => any}) :: any
  def to_json(struct) do
    map = to_slim_map(struct)
    Jason.encode!(map)
  end

  @doc """
  Assembles a list of JSON-LD entities into a single @graph structure.

  Strips @context from individual entities (it goes at the top level only)
  and wraps everything in a single JSON-LD document.
  """
  def to_graph_json(entities) do
    graph_items =
      entities
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn entity ->
        entity
        |> to_slim_map()
        |> Map.delete(:"@context")
        |> Map.delete("@context")
      end)
      |> Enum.reject(&is_nil/1)

    %{
      "@context" => "https://schema.org",
      "@graph" => graph_items
    }
    |> Jason.encode!()
  end

  @doc """
  Converts a struct or map to a slim map, stripping nil values recursively.
  """
  def to_slim_map(%_{} = struct) do
    for {k, v} <- Map.from_struct(struct),
        v != nil,
        into: %{} do
      {k, slim_map(v)}
    end
  end

  def to_slim_map(map) when is_map(map) do
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
