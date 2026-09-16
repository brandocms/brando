defmodule Brando.Content.Transfer.Portable do
  @moduledoc "Version 1 of the portable block tree. Ownership is rebuilt exclusively at the destination."
  alias Brando.Content.Transfer.{Catalog, Dependencies, Error}
  alias Brando.Content.Definition.Value
  alias Brando.Drafts.Params

  @block ~w(uid type active collapsed anchor description multi datasource sequence slot_name slot_kind slot_module_set module_id container_id palette_id fragment_id identifier_metas)
  @ref ~w(uid name description active collapsed sequence data image_id video_id file_id gallery_id)
  @asset_fields %{
    "module_id" => "module",
    "container_id" => "container",
    "palette_id" => "palette",
    "fragment_id" => "fragment",
    "image_id" => "image",
    "file_id" => "file",
    "video_id" => "video",
    "gallery_id" => "gallery",
    "identifier_id" => "identifier",
    "thumbnail_id" => "image"
  }
  @identifier_attribute ~r/(data-identifier-id\s*=\s*)(["'])([^"']+)\2/i
  @footnote_attribute ~r/(data-footnote-uid\s*=\s*)(["'])([^"']+)\2/i
  @unquoted_attribute ~r/(\bdata-(?:identifier-id|footnote-uid)\s*=\s*)([^"'\s>][^\s>]*)/i

  def asset_fields, do: @asset_fields
  def var_fields, do: Enum.map(Brando.Content.VarAttrs.carried(), &to_string/1) ++ ["options"]

  def encode(block, state) do
    if block.module_origin == :shared || block.container_origin == :shared || block.palette_origin == :shared,
      do: Error.fail!("Shared-library blocks must be installed as local definitions before transfer.")

    params = Params.snapshot(block)
    {base, state} = params |> Map.take(@block) |> encode_values(state)

    {refs, state} =
      Enum.map_reduce(block.refs, state, fn ref, acc ->
        ref |> Params.snapshot() |> Map.take(@ref) |> Map.update!("data", &strip_embed_ids/1) |> encode_values(acc)
      end)

    {vars, state} = encode_vars(block.vars, state)

    {rows, state} =
      Enum.map_reduce(block.table_rows, state, fn row, acc ->
        {vars, acc} = encode_vars(row.vars, acc)
        {%{"vars" => vars}, acc}
      end)

    {identifiers, state} =
      Enum.map_reduce(block.block_identifiers, state, fn join, acc ->
        {token, acc} = Dependencies.add("identifier", join.identifier_id, acc)
        {%{"identifier_id" => token}, acc}
      end)

    {children, state} = Enum.map_reduce(block.children, state, &encode/2)

    {Map.merge(base, %{
       "refs" => refs,
       "vars" => vars,
       "table_rows" => rows,
       "block_identifiers" => identifiers,
       "children" => children
     }), state}
  end

  def encode_vars(vars, state),
    do:
      Enum.map_reduce(vars, state, fn var, acc ->
        var |> Params.snapshot() |> Map.take(var_fields()) |> encode_values(acc)
      end)

  def encode_values(value, state) when is_map(value) do
    Enum.reduce(value, {%{}, state}, fn {key, nested}, {map, acc} ->
      whole = value
      value = nested

      {encoded, acc} =
        cond do
          Map.has_key?(@asset_fields, key) ->
            Dependencies.add(@asset_fields[key], value, acc)

          key == "identifier_metas" ->
            encode_metas(value, acc)

          key in ~w(slot_module_set module_set footnote_module_set) and value not in [nil, "", "all"] and
              (key != "footnote_module_set" or whole["footnotes"] == true) ->
            Dependencies.add_set(value, acc)

          key == "object_id" and value not in [nil, ""] ->
            {"gallery_object:#{value}", acc}

          key in ~w(source_id version_id) and not is_nil(value) ->
            kind = if key == "source_id", do: "markdown_source", else: "markdown_version"
            Dependencies.add(kind, value, acc)

          true ->
            encode_values(value, acc)
        end

      {Map.put(map, key, encoded), acc}
    end)
  end

  def encode_values(value, state) when is_list(value), do: Enum.map_reduce(value, state, &encode_values/2)

  def encode_values(value, state) when is_binary(value) do
    value = normalize_attributes(value)

    Regex.scan(@identifier_attribute, value)
    |> Enum.reduce({value, state}, fn [match, prefix, quote, id], {html, acc} ->
      {token, acc} = Dependencies.add("identifier", Catalog.id!(id), acc)
      {String.replace(html, match, prefix <> quote <> token <> quote), acc}
    end)
  end

  def encode_values(value, state), do: {value, state}

  defp encode_metas(nil, state), do: {%{}, state}

  defp encode_metas(metas, state) do
    Enum.reduce(metas, {%{}, state}, fn {key, value}, {map, acc} ->
      identifier = Dependencies.identifier_for_meta!(key)
      {token, acc} = Dependencies.add("identifier", identifier.id, acc)
      {Map.put(map, token, value), acc}
    end)
  end

  def validate!(bundle) do
    Value.keys!(bundle, ~w(format version id created_at source fields entries dependencies definitions), "content bundle")

    unless bundle["format"] == "brando-content" && bundle["version"] in [1, 2],
      do: Error.fail!("This is not a supported Brando content bundle (versions 1 and 2).")

    Value.nonempty!(bundle["id"], "package ID")
    Value.nonempty!(bundle["source"]["scope"], "source scope")
    Value.nonempty!(bundle["source"]["label"], "source label")
    if bundle["definitions"], do: Brando.Content.Definition.Model.validate_graph!(bundle["definitions"])

    minimum = if bundle["version"] == 2, do: 0, else: 1

    unless is_list(bundle["fields"]) && length(bundle["fields"]) in minimum..100,
      do: Error.fail!("A bundle can contain up to 100 saved block fields.")

    unless is_map(bundle["dependencies"]) && map_size(bundle["dependencies"]) <= 2_000,
      do: Error.fail!("The dependency manifest is invalid or too large.")

    Value.unique!(Enum.map(bundle["fields"], & &1["key"]), "field keys")

    Enum.each(bundle["fields"], fn field ->
      Value.keys!(field, ~w(key entry_key schema field title language hints blocks fingerprint), "content field")
      Value.nonempty!(field["key"], "source field key")
      Value.nonempty!(field["schema"], "source schema")
      Value.nonempty!(field["field"], "source field")
      Value.nonempty!(field["title"], "source title")
      unless is_map(field["hints"]) && is_binary(field["language"]), do: Error.fail!("Invalid content matching hints.")
      unless is_list(field["blocks"]), do: Error.fail!("A field must contain an ordered block list.")
      Enum.each(field["blocks"], &validate_block!(&1, bundle["dependencies"], 0))
      uids = walk(field["blocks"], & &1["uid"])
      Value.unique!(uids, "block instance UIDs")
      if length(uids) > 5_000, do: Error.fail!("A field exceeds 5,000 blocks.")
    end)

    Enum.each(bundle["dependencies"], fn {token, dep} ->
      unless is_map(dep) && dep["kind"] in Dependencies.kinds() && String.starts_with?(token, dep["kind"] <> ":"),
        do: Error.fail!("An unknown dependency type was found.")

      unless Regex.match?(~r/^[a-z_]+:[A-Za-z0-9_-]+$/, token), do: Error.fail!("Invalid dependency token.")

      Dependencies.validate!(dep)

      case dep["kind"] do
        "module" ->
          if dep["parent"], do: reference!(dep["parent"], "module", bundle["dependencies"])
          if dep["table_template"], do: reference!(dep["table_template"], "table_template", bundle["dependencies"])

        "container" ->
          if dep["palette"], do: reference!(dep["palette"], "palette", bundle["dependencies"])

        "module_set" ->
          unless is_list(dep["members"]), do: Error.fail!("Invalid module set membership.")
          Enum.each(dep["members"], &reference!(&1, "module", bundle["dependencies"]))

        _ ->
          :ok
      end

      if dep["data"], do: validate_references!(dep["data"], bundle["dependencies"])
      if dep["objects"], do: validate_references!(dep["objects"], bundle["dependencies"])
    end)

    if bundle["version"] == 2 do
      Brando.Content.Transfer.Entries.validate!(bundle)
    else
      if bundle["entries"], do: Error.fail!("Entry content requires bundle version 2.")
    end

    bundle
  end

  def validate_blocks!(blocks, deps), do: Enum.each(blocks, &validate_block!(&1, deps, 0))
  def validate_values!(values, deps), do: validate_references!(values, deps)

  defp validate_block!(block, deps, depth) when is_map(block) and depth <= 40 do
    Value.keys!(block, @block ++ ~w(refs vars children table_rows block_identifiers), "block")
    Value.nonempty!(block["uid"], "block UID")
    unless block["type"] in ~w(module module_entry container fragment slot), do: Error.fail!("Unsupported block type.")

    Enum.each(~w(refs vars children table_rows block_identifiers), fn key ->
      unless is_list(block[key]), do: Error.fail!("Invalid #{key} collection.")
    end)

    Enum.each(block["refs"], fn ref ->
      Value.keys!(ref, @ref, "reference")
      type = get_in(ref, ["data", "type"])

      schema = Brando.Content.Definition.Model.block_schema!(type)
      Brando.Content.Definition.Model.validate_fields!(schema, ref["data"], "reference data")
    end)

    Enum.each(block["vars"], &Value.keys!(&1, var_fields(), "variable"))

    Enum.each(block["table_rows"], fn row ->
      Value.keys!(row, ~w(vars), "table row")
      Enum.each(row["vars"], &Value.keys!(&1, var_fields(), "table variable"))
    end)

    Enum.each(block["block_identifiers"], &Value.keys!(&1, ~w(identifier_id), "selected entry"))
    validate_references!(Map.delete(block, "children"), deps)
    Enum.each(block["children"], &validate_block!(&1, deps, depth + 1))
  end

  defp validate_block!(_, _, _), do: Error.fail!("The block tree is malformed or exceeds 40 nesting levels.")

  defp validate_references!(map, deps) when is_map(map) do
    Enum.each(map, fn {key, value} ->
      cond do
        Map.has_key?(@asset_fields, key) and not is_nil(value) ->
          reference!(value, @asset_fields[key], deps)

        key == "identifier_metas" and is_map(value) ->
          Enum.each(Map.keys(value), &reference!(&1, "identifier", deps))

        key in ~w(slot_module_set module_set footnote_module_set) and value not in [nil, "", "all"] and
            (key != "footnote_module_set" or map["footnotes"] == true) ->
          reference!(value, "module_set", deps)

        key in ~w(source_id version_id) and not is_nil(value) ->
          reference!(value, if(key == "source_id", do: "markdown_source", else: "markdown_version"), deps)

        true ->
          validate_references!(value, deps)
      end
    end)
  end

  defp validate_references!(values, deps) when is_list(values), do: Enum.each(values, &validate_references!(&1, deps))

  defp validate_references!(value, deps) when is_binary(value) do
    value = normalize_attributes(value)
    Enum.each(Regex.scan(@identifier_attribute, value), fn [_, _, _, token] -> reference!(token, "identifier", deps) end)
  end

  defp validate_references!(_, _), do: :ok

  defp reference!(token, kind, deps) do
    unless is_binary(token) && match?(%{"kind" => ^kind}, deps[token]),
      do: Error.fail!("An unresolved #{kind} reference was found. Database IDs are not portable references.")
  end

  def decode(blocks, bindings, source, creator, uids \\ nil) do
    uids = uids || blocks |> walk(& &1["uid"]) |> Map.new(&{&1, Brando.Utils.generate_uid()})
    Enum.with_index(blocks, fn block, index -> decode_block(block, bindings, source, creator, uids, index) end)
  end

  defp decode_block(block, bindings, source, creator, uids, index) do
    children =
      Enum.with_index(block["children"], fn child, n -> decode_block(child, bindings, source, creator, uids, n) end)

    block
    |> Map.delete("children")
    |> decode_values(bindings, uids)
    |> Map.merge(%{
      "uid" => Map.fetch!(uids, block["uid"]),
      "creator_id" => creator,
      "source" => to_string(source),
      "sequence" => index,
      "children" => children
    })
    |> Map.update!("refs", fn refs -> Enum.map(refs, &fresh_uids/1) end)
    |> Map.update!("table_rows", &sequence/1)
    |> Map.update!("block_identifiers", &sequence/1)
  end

  defp sequence(items), do: Enum.with_index(items, fn item, n -> Map.put(item, "sequence", n) end)

  def decode_values(value, bindings, uids \\ %{})

  def decode_values(value, bindings, uids) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      whole = value
      value = nested

      decoded =
        cond do
          Map.has_key?(@asset_fields, key) and not is_nil(value) ->
            resolve!(bindings, value).id

          key == "object_id" and value not in [nil, ""] ->
            to_string(resolve!(bindings, value).id)

          key == "identifier_metas" ->
            Map.new(value || %{}, fn {token, meta} ->
              identifier = resolve!(bindings, token)
              {"#{inspect(identifier.schema)}_#{identifier.entry_id}", meta}
            end)

          key in ~w(slot_module_set module_set footnote_module_set) and value not in [nil, "", "all"] and
              (key != "footnote_module_set" or whole["footnotes"] == true) ->
            resolve!(bindings, value).title

          key in ~w(source_id version_id) and not is_nil(value) ->
            resolve!(bindings, value).id

          true ->
            decode_values(value, bindings, uids)
        end

      {key, decoded}
    end)
  end

  def decode_values(value, bindings, uids) when is_list(value), do: Enum.map(value, &decode_values(&1, bindings, uids))

  def decode_values(value, bindings, uids) when is_binary(value) do
    value = normalize_attributes(value)

    value =
      Regex.replace(@footnote_attribute, value, fn _, prefix, quote, uid ->
        fresh = Map.get(uids, uid) || Error.fail!("A footnote points outside its owned field.")
        prefix <> quote <> fresh <> quote
      end)

    if Regex.match?(@identifier_attribute, value) do
      {:ok, nodes} = Floki.parse_fragment(value)

      nodes
      |> Floki.traverse_and_update(fn
        {tag, attrs, children} ->
          case List.keyfind(attrs, "data-identifier-id", 0) do
            {_, token} ->
              identifier = resolve!(bindings, token)
              attrs = List.keystore(attrs, "data-identifier-id", 0, {"data-identifier-id", to_string(identifier.id)})
              attrs = if tag == "a", do: List.keystore(attrs, "href", 0, {"href", identifier.url || ""}), else: attrs
              {tag, attrs, children}

            _ ->
              {tag, attrs, children}
          end

        node ->
          node
      end)
      |> Floki.raw_html()
    else
      value
    end
  end

  def decode_values(value, _, _), do: value

  def resolve!(bindings, token),
    do: Map.get(bindings, token) || Error.fail!("Resolve dependency #{token} before importing.")

  defp fresh_uids(map) when is_map(map),
    do:
      Map.new(map, fn
        {"uid", _} -> {"uid", Brando.Utils.generate_uid()}
        {key, value} -> {key, fresh_uids(value)}
      end)

  defp fresh_uids(list) when is_list(list), do: Enum.map(list, &fresh_uids/1)
  defp fresh_uids(value), do: value

  defp strip_embed_ids(value) when is_map(value),
    do: value |> Map.delete("id") |> Map.new(fn {key, nested} -> {key, strip_embed_ids(nested)} end)

  defp strip_embed_ids(value) when is_list(value), do: Enum.map(value, &strip_embed_ids/1)
  defp strip_embed_ids(value), do: value

  defp normalize_attributes(value), do: Regex.replace(@unquoted_attribute, value, "\\1\"\\2\"")

  def walk(blocks, fun), do: Enum.flat_map(blocks, fn block -> [fun.(block) | walk(block["children"] || [], fun)] end)
  def count(blocks), do: blocks |> walk(fn _ -> 1 end) |> length()
end
