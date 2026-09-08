defmodule Brando.Content.Definition.References do
  @moduledoc false

  alias Brando.Content.Definition.{Error, Value}
  alias Brando.Repo

  @schemas %{
    "image" => Brando.Images.Image,
    "video" => Brando.Videos.Video,
    "file" => Brando.Files.File,
    "gallery" => Brando.Galleries.Gallery,
    "palette" => Brando.Content.Palette,
    "identifier" => Brando.Content.Identifier,
    "gallery_object" => Brando.Galleries.GalleryObject
  }

  def scope do
    config = Repo.repo().config()
    uri = URI.parse(config[:url] || "")

    Value.digest([
      config[:hostname] || uri.host,
      config[:port] || uri.port,
      config[:database] || uri.path,
      Brando.Tenant.current_prefix() || "public"
    ])
  end

  def bind!(bundle, supplied, actor) do
    declared = collect!(bundle["modules"] || [], %{}) |> then(&collect!(bundle["table_templates"] || [], &1))

    bindings =
      Map.new(declared, fn {token, kind} ->
        binding = get_in(bundle, ["references", token]) || %{"kind" => kind}
        if binding["kind"] != kind, do: Error.raise!(token, "reference kind does not match its use")
        {token, binding}
      end)

    same_scope? = bundle["source"] == scope()
    unknown = Map.keys(supplied) -- Map.keys(bindings)
    if unknown != [], do: Error.raise!("references", "unknown mapping keys #{inspect(unknown)}")

    Map.new(bindings, fn {token, binding} ->
      schema = Map.get(@schemas, binding["kind"]) || Error.raise!(token, "unknown reference kind")

      if same_scope? && binding["id"] && supplied[token] && supplied[token] != binding["id"],
        do: Error.raise!(token, "use a new token when changing an existing destination binding")

      id = Map.get(supplied, token) || (same_scope? && binding["id"])
      unless id, do: Error.raise!(token, "requires a destination reference mapping")
      unless is_integer(id) and id > 0, do: Error.raise!(token, "expected a positive destination record ID")
      record = Repo.get(schema, id)

      if is_nil(record) or Map.get(record, :deleted_at),
        do: Error.raise!(token, "destination reference is missing or deleted")

      authorize!(actor, binding["kind"], schema, record)
      {token, %{"kind" => binding["kind"], "id" => record.id}}
    end)
  end

  defp collect!(value, bindings) when is_list(value), do: Enum.reduce(value, bindings, &collect!/2)

  defp collect!(value, bindings) when is_map(value) do
    Enum.reduce(value, bindings, fn
      {"assets", assets}, bindings ->
        Enum.reduce(assets, bindings, fn {kind, token}, bindings -> declare!(token, kind, bindings) end)

      {"object_id", token}, bindings ->
        declare!(token, "gallery_object", bindings)

      {_key, nested}, bindings ->
        collect!(nested, bindings)
    end)
  end

  defp collect!(_, bindings), do: bindings

  defp declare!(nil, _kind, bindings), do: bindings

  defp declare!(token, kind, bindings) do
    Value.nonempty!(token, "reference token")
    unless Map.has_key?(@schemas, kind), do: Error.raise!(token, "unknown reference kind")
    if bindings[token] && bindings[token] != kind, do: Error.raise!(token, "token is used for different reference kinds")
    Map.put(bindings, token, kind)
  end

  defp authorize!(actor, kind, schema, record) do
    {schema, id} =
      case kind do
        "gallery_object" -> {Brando.Galleries.Gallery, record.gallery_id}
        "identifier" -> {record.schema, record.entry_id}
        _ -> {schema, record.id}
      end

    if Brando.Authorization.Boundary.authorize_record(actor, :read, schema, id) != :ok,
      do: Error.raise!("references", "forbidden")
  end

  def encode(record, fields, bindings) do
    Enum.reduce(fields, {%{}, bindings}, fn kind, {assets, bindings} ->
      id = Map.get(record, String.to_existing_atom(kind <> "_id"))
      {token, bindings} = token(kind, id, bindings)
      {Map.put(assets, kind, token), bindings}
    end)
  end

  def token(_kind, nil, bindings), do: {nil, bindings}

  def token(kind, id, bindings) do
    existing = Enum.find(bindings, fn {_token, binding} -> binding == %{"kind" => kind, "id" => id} end)

    if existing do
      {elem(existing, 0), bindings}
    else
      key = kind <> ":" <> to_string(id)
      key = if Map.has_key?(bindings, key), do: key <> ":" <> Value.digest([kind, id, scope()]), else: key
      {key, Map.put(bindings, key, %{"kind" => kind, "id" => id})}
    end
  end

  def decode!(assets, bindings) do
    Map.new(assets, fn {kind, token} ->
      id = if token, do: resolve!(token, kind, bindings), else: nil
      {kind <> "_id", id}
    end)
  end

  def resolve!(token, kind, bindings) do
    case bindings[token] do
      %{"kind" => ^kind, "id" => id} -> id
      _ -> Error.raise!(to_string(token), "unresolved #{kind} reference")
    end
  end

  def encode_data(data, bindings) when is_map(data) do
    Enum.reduce(data, {%{}, bindings}, fn
      {"object_id", id}, {map, refs} when not is_nil(id) ->
        id =
          case Integer.parse(to_string(id)) do
            {id, ""} -> id
            _ -> Error.raise!("gallery object", "invalid object ID")
          end

        {token, refs} = token("gallery_object", id, refs)
        {Map.put(map, "object_id", token), refs}

      {key, value}, {map, refs} ->
        {value, refs} = encode_data(value, refs)
        {Map.put(map, key, value), refs}
    end)
  end

  def encode_data(data, bindings) when is_list(data), do: Enum.map_reduce(data, bindings, &encode_data/2)
  def encode_data(data, bindings), do: {data, bindings}

  def decode_data!(data, bindings) when is_map(data) do
    Map.new(data, fn
      {"object_id", token} when not is_nil(token) ->
        {"object_id", token |> resolve!("gallery_object", bindings) |> to_string()}

      {key, value} ->
        {key, decode_data!(value, bindings)}
    end)
  end

  def decode_data!(data, bindings) when is_list(data), do: Enum.map(data, &decode_data!(&1, bindings))
  def decode_data!(data, _bindings), do: data
end
