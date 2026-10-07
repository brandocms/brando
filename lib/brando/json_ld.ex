defmodule Brando.JSONLD do
  @moduledoc """
  JSON-LD structured data generation.

  Extracts JSON-LD entities from blueprint DSL definitions and assembles
  them into a connected `@graph` document following schema.org vocabulary.
  """

  @doc """
  Extracts a JSON-LD entity from a blueprint module's `json_ld_schema` DSL.

  Returns a struct populated with field values extracted from `data`.
  Additional fields can be passed via `extra_fields` to supplement
  the blueprint definition at runtime. Returns `nil` when the Blueprint has no
  JSON-LD schema.
  """
  @spec extract_json_ld(module(), term(), [map()]) :: struct() | nil
  def extract_json_ld(module, data, extra_fields \\ []) do
    json_ld_data =
      module
      |> Spark.Dsl.Extension.get_entities(:json_ld_schemas)
      |> List.first()

    extract_json_ld_schema(module, json_ld_data, data, extra_fields)
  end

  defp extract_json_ld_schema(_module, nil, _data, _extra_fields), do: nil

  defp extract_json_ld_schema(module, json_ld_data, data, extra_fields) do
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

      %{name: name, type: :duration, value_fn: value_fn}, acc ->
        result =
          data
          |> value_fn.()
          |> to_duration()

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

      %{name: name, type: :person, value_fn: value_fn}, acc ->
        Map.put(acc, name, Brando.JSONLD.Author.build(value_fn.(data)))

      %{name: name, type: {:list, schema}, value_fn: value_fn}, acc ->
        items = value_fn.(data)
        result = if is_list(items), do: Enum.map(items, &schema.build/1), else: nil
        Map.put(acc, name, result)

      %{name: name, type: schema, value_fn: value_fn}, acc ->
        result = schema.build(value_fn.(data))
        Map.put(acc, name, result)
    end)
    |> maybe_put_videos(module, json_ld_data, fields, data)
    |> maybe_override_type(data)
    |> maybe_add_id(data)
  end

  # The videos the entry shows, on schemas with a `video` property, unless the
  # blueprint maps `video` itself or opts out with `videos: false`.
  defp maybe_put_videos(struct, module, json_ld_data, fields, data) do
    with true <- Map.get(json_ld_data, :videos, true),
         true <- Map.has_key?(struct, :video),
         false <- Enum.any?(fields, &(&1.name == :video)),
         [_ | _] = videos <- Brando.JSONLD.Videos.from_entry(module, data) do
      Map.put(struct, :video, single_or_list(videos))
    else
      _ -> struct
    end
  end

  defp single_or_list([one]), do: one
  defp single_or_list(many), do: many

  defp maybe_add_id(struct, %{__meta__: %{current_url: url}}) when is_binary(url) and url != "" do
    type =
      struct
      |> Map.get(:"@type", "")
      |> to_string()
      |> String.downcase()

    Map.put(struct, :"@id", Path.join(url, "##{type}"))
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
      |> lift_linked_nodes()
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

  # Nodes the graph links to rather than nests: a `Person` built for an author
  # and a `VideoObject`. Each is lifted out of the entity that holds it and
  # left there as an `@id` reference, so the graph has one node per person or
  # video however many entities point at it — the first occurrence wins.
  @linked_nodes [Brando.JSONLD.Schema.Person, Brando.JSONLD.Schema.VideoObject]

  @doc """
  Lifts linked nodes (`Person`s with an `@id`, `VideoObject`s) out of
  `entities` into top-level graph nodes, replacing each with an `@id`
  reference. Nodes already at the top level keep their place; duplicates by
  `@id` are dropped.
  """
  @spec lift_linked_nodes([term()]) :: [term()]
  def lift_linked_nodes(entities) do
    {entities, lifted} = Enum.map_reduce(entities, [], &lift_fields/2)

    (entities ++ Enum.reverse(lifted))
    |> Enum.uniq_by(fn
      %{"@id": id} when is_binary(id) -> id
      other -> {:unidentified, make_ref(), other}
    end)
  end

  defp lift_fields(%_{} = struct, acc) do
    struct
    |> Map.from_struct()
    |> Enum.reduce({struct, acc}, fn {key, value}, {struct, acc} ->
      {value, acc} = lift(value, acc)
      {Map.put(struct, key, value), acc}
    end)
  end

  defp lift_fields(other, acc), do: {other, acc}

  defp lift(%module{"@id": id} = node, acc) when module in @linked_nodes and is_binary(id) do
    {node, acc} = lift_fields(node, acc)
    {%{"@id": id}, [node | acc]}
  end

  defp lift(%_{} = struct, acc), do: lift_fields(struct, acc)
  defp lift(list, acc) when is_list(list), do: Enum.map_reduce(list, acc, &lift/2)
  defp lift(value, acc), do: {value, acc}

  @doc """
  Converts a struct or map to a slim map, stripping nil values recursively.
  """
  def to_slim_map(%_{} = struct), do: struct |> Map.from_struct() |> slim_entries()
  def to_slim_map(map) when is_map(map), do: slim_entries(map)

  # A nested entity with nothing to say is left out, not emitted as null.
  defp slim_entries(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc ->
        case slim_map(value) do
          nil -> acc
          slimmed -> Map.put(acc, key, slimmed)
        end
    end)
  end

  defp slim_map(map) when is_map(map) do
    map_without_nils = :maps.filter(fn _, v -> v != nil end, map)

    key_count =
      map_without_nils
      |> Map.keys()
      |> Enum.reject(&(&1 == :__struct__ or String.starts_with?(to_string(&1), ["@context", "@type"])))
      |> Enum.count()

    # A nested entity is read in its document's context; a Place or
    # PostalAddress built for the top level repeats it otherwise
    if key_count > 0, do: map |> to_slim_map() |> Map.delete(:"@context")
  end

  defp slim_map(list) when is_list(list) do
    list
    |> Enum.map(&slim_map/1)
    |> Enum.reject(&is_nil/1)
  end

  defp slim_map(value), do: value

  @doc """
  Convert date to ISO friendly string
  """
  @spec to_date(Date.t() | nil) :: binary() | nil
  def to_date(nil), do: nil
  def to_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

  @doc """
  Converts a duration to ISO 8601, as Google wants for `totalTime`,
  `prepTime`, `cookTime` and `duration`.

  Takes whole minutes (`90` is `"PT1H30M"`), a `Duration`, an
  `"HH:MM:SS"` or `"MM:SS"` string, or an ISO 8601 duration, which is kept.
  `nil` for anything else.

      iex> Brando.JSONLD.to_duration(90)
      "PT1H30M"
      iex> Brando.JSONLD.to_duration("00:45:00")
      "PT45M"
      iex> Brando.JSONLD.to_duration("PT20M")
      "PT20M"
  """
  @spec to_duration(term()) :: String.t() | nil
  def to_duration(minutes) when is_integer(minutes) and minutes > 0,
    do: Brando.JSONLD.Schema.VideoObject.duration("#{div(minutes, 60)}:#{rem(minutes, 60)}:00")

  def to_duration(%Duration{year: 0, month: 0} = duration) do
    seconds = duration |> to_timeout() |> div(1000)
    if seconds > 0, do: Brando.JSONLD.Schema.VideoObject.duration("0:0:#{seconds}")
  end

  def to_duration("P" <> _ = iso), do: if(iso_duration?(iso), do: iso)

  def to_duration(value) when is_binary(value), do: Brando.JSONLD.Schema.VideoObject.duration(value)
  def to_duration(_value), do: nil

  @doc "Whether `value` is an ISO 8601 duration, such as `PT1H30M`."
  @spec iso_duration?(term()) :: boolean()
  def iso_duration?(value) when is_binary(value),
    do: Regex.match?(~r/^P(?!$)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?=\d)(\d+H)?(\d+M)?(\d+(\.\d+)?S)?)?$/, value)

  def iso_duration?(_value), do: false

  @doc """
  Convert datetime to ISO friendly string
  """
  @spec to_datetime(DateTime.t() | NaiveDateTime.t() | nil) :: binary() | nil
  def to_datetime(nil), do: nil

  def to_datetime(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  def to_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
