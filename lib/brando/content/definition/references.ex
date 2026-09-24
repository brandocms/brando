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
    "markdown_source" => Brando.MarkdownSources.Source,
    "markdown_version" => Brando.MarkdownSources.Version
  }

  @markdown_fields %{"source_id" => "markdown_source", "version_id" => "markdown_version"}

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
    declared = declared!(bundle)

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

  @doc """
  Reads bundles written before gallery overrides were bound by media. They
  recorded an override's (media) id under a `gallery_object` reference kind;
  it becomes the kind of the image or video the override is for.
  """
  def upgrade(%{"references" => references} = bundle) when is_map(references) do
    if Enum.any?(references, &match?({_, %{"kind" => "gallery_object"}}, &1)) do
      declared = declared!(bundle)

      references =
        Map.new(references, fn
          {token, %{"kind" => "gallery_object"} = binding} when is_map_key(declared, token) ->
            {token, Map.put(binding, "kind", declared[token])}

          pair ->
            pair
        end)

      Map.put(bundle, "references", references)
    else
      bundle
    end
  end

  def upgrade(bundle), do: bundle

  defp declared!(bundle),
    do: collect!(bundle["modules"] || [], %{}) |> then(&collect!(bundle["table_templates"] || [], &1))

  defp collect!(value, bindings) when is_list(value), do: Enum.reduce(value, bindings, &collect!/2)

  defp collect!(%{"type" => "markdown_source", "data" => data}, bindings) do
    Enum.reduce(@markdown_fields, bindings, fn {field, kind}, bindings -> declare!(data[field], kind, bindings) end)
  end

  defp collect!(%{"object_id" => token} = override, bindings) when not is_nil(token) do
    bindings = declare!(token, override_kind!(override), bindings)
    collect!(Map.delete(override, "object_id"), bindings)
  end

  defp collect!(value, bindings) when is_map(value) do
    Enum.reduce(value, bindings, fn
      {"assets", assets}, bindings ->
        Enum.reduce(assets, bindings, fn {kind, token}, bindings -> declare!(token, kind, bindings) end)

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

  defp authorize!(actor, kind, _schema, _record) when kind in ~w(markdown_source markdown_version) do
    if Brando.MarkdownSources.authorize(actor, :read) != :ok, do: Error.raise!("references", "forbidden")
  end

  defp authorize!(actor, kind, schema, record) do
    {schema, id} =
      case kind do
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

  def encode_data(%{"type" => "markdown_source", "data" => data} = ref, bindings) do
    {data, bindings} =
      Enum.reduce(@markdown_fields, {data, bindings}, fn {field, kind}, {data, bindings} ->
        {token, bindings} = token(kind, data[field], bindings)
        {Map.put(data, field, token), bindings}
      end)

    {Map.put(ref, "data", data), bindings}
  end

  def encode_data(%{"object_id" => id} = override, bindings) when not is_nil(id) do
    id =
      case Integer.parse(to_string(id)) do
        {id, ""} -> id
        _ -> Error.raise!("gallery override", "invalid image or video ID")
      end

    {token, bindings} = token(override_kind!(override), id, bindings)
    {override, bindings} = encode_data(Map.delete(override, "object_id"), bindings)
    {Map.put(override, "object_id", token), bindings}
  end

  def encode_data(data, bindings) when is_map(data) do
    Enum.reduce(data, {%{}, bindings}, fn
      {key, value}, {map, refs} ->
        {value, refs} = encode_data(value, refs)
        {Map.put(map, key, value), refs}
    end)
  end

  def encode_data(data, bindings) when is_list(data), do: Enum.map_reduce(data, bindings, &encode_data/2)
  def encode_data(data, bindings), do: {data, bindings}

  def decode_data!(%{"type" => "markdown_source", "data" => data} = ref, bindings) do
    data =
      Enum.reduce(@markdown_fields, data, fn {field, kind}, data ->
        token = data[field]
        Map.put(data, field, if(token, do: resolve!(token, kind, bindings), else: nil))
      end)

    Map.put(ref, "data", data)
  end

  def decode_data!(%{"object_id" => token} = override, bindings) when not is_nil(token) do
    override
    |> Map.delete("object_id")
    |> decode_data!(bindings)
    |> Map.put("object_id", token |> resolve!(override_kind!(override), bindings) |> to_string())
  end

  def decode_data!(data, bindings) when is_map(data),
    do: Map.new(data, fn {key, value} -> {key, decode_data!(value, bindings)} end)

  def decode_data!(data, bindings) when is_list(data), do: Enum.map(data, &decode_data!(&1, bindings))
  def decode_data!(data, _bindings), do: data

  # A gallery override's `object_id` is the id of an image or a video, told
  # apart by `object_type`.
  defp override_kind!(override) do
    case Brando.Villain.Blocks.GalleryObjectOverride.media_key(override) do
      {type, _id} when type in [:image, :video] -> Atom.to_string(type)
      _ -> Error.raise!("gallery override", "object_type must be image or video")
    end
  end
end
