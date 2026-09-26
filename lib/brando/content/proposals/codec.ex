defmodule Brando.Content.Proposals.Codec do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  JSON form of proposal operations.

  One shape serves both directions: the operations an agent submits through
  the `prepare_proposal` tool, and the frozen operations stored with a
  proposal. Content types are Blueprint module names (`"Brando.Pages.Page"`)
  and are resolved against the registered schemas, never turned into atoms.

      %{"op" => "create_entry", "content_type" => "…", "ref" => "case", "fields" => %{}}
      %{"op" => "set_fields", "target" => target, "fields" => %{}}
      %{"op" => "insert_block", "target" => target, "field" => "blocks", "module" => "local:12",
        "parent" => uid | nil, "placement" => "append" | %{"before" => uid} | %{"after" => uid},
        "values" => %{}, "texts" => %{}, "media" => %{"cover" => asset}}
      %{"op" => "set_block_media", "target" => target, "block_uid" => uid, "ref" => name, "asset" => asset}
      %{"op" => "set_block_values", "target" => target, "block_uid" => uid, "values" => %{}}
      %{"op" => "set_block_text", "target" => target, "block_uid" => uid, "ref" => name, "text" => text}
      %{"op" => "move_block", "target" => target, "block_uid" => uid, "placement" => placement | %{"into" => uid}}
      %{"op" => "set_block_active", "target" => target, "block_uid" => uid, "ref" => name | nil, "active" => false}
      %{"op" => "delete_block", "target" => target, "block_uid" => uid}
      %{"op" => "copy_block", "target" => target, "block_uid" => uid, "placement" => placement, "uid" => uid}
      %{"op" => "set_block_details", "target" => target, "block_uid" => uid, "anchor" => a, "description" => d}
      %{"op" => "set_ref_config", "target" => target, "block_uid" => uid, "ref" => name, "config" => %{}}
      %{"op" => "set_block_table", "target" => target, "block_uid" => uid, "rows" => [%{}]}
      %{"op" => "set_block_selection", "target" => target, "block_uid" => uid, "identifiers" => [id]}

  A `target` is `%{"content_type" => …, "id" => 12}` or `%{"new" => ref}`. An
  `asset` is `%{"kind" => "image" | "video" | "file", "id" => 3}`, the alias
  of a conversation attachment such as `"image1"`, or `%{"gallery" => [asset]}`
  for a gallery. In `values`, a media var takes `%{"kind" => …, "id" => …}`,
  `%{"asset" => "image1"}` or `%{"gallery" => […]}`, and a link var an entry
  as `%{"content_type" => …, "id" => …}`.
  """
  alias Brando.Content.Proposals.{
    CopyBlock,
    CreateEntry,
    DeleteBlock,
    InsertBlock,
    MoveBlock,
    SetBlockActive,
    SetBlockDetails,
    SetBlockMedia,
    SetBlockSelection,
    SetBlockTable,
    SetBlockText,
    SetBlockValues,
    SetFields,
    SetRefConfig
  }

  @doc "Decode one operation. `attachments` maps aliases to `{:image | :video, id}`."
  @spec decode(map(), map()) :: {:ok, struct()} | {:error, String.t()}
  def decode(map, attachments \\ %{})

  def decode(%{"op" => op} = map, attachments) do
    {:ok, decode!(op, map, attachments)}
  catch
    {:invalid, message} -> {:error, message}
  end

  def decode(_, _), do: {:error, dgettext("content_proposals", "Each operation needs an \"op\".")}

  @doc "Decode a list, stopping at the first invalid operation (reported with its index)."
  @spec decode_all([map()], map()) :: {:ok, [struct()]} | {:error, String.t()}
  def decode_all(maps, attachments \\ %{}) when is_list(maps) do
    maps
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {map, index}, {:ok, acc} ->
      case decode(map, attachments) do
        {:ok, op} -> {:cont, {:ok, [op | acc]}}
        {:error, message} -> {:halt, {:error, "Operation #{index}: #{message}"}}
      end
    end)
    |> then(fn
      {:ok, ops} -> {:ok, Enum.reverse(ops)}
      error -> error
    end)
  end

  defp decode!("create_entry", map, attachments),
    do: %CreateEntry{
      schema: schema!(map["content_type"]),
      ref: string!(map["ref"], "ref"),
      fields: values(map!(map["fields"]), attachments)
    }

  defp decode!("set_fields", map, attachments),
    do: %SetFields{target: target!(map["target"]), fields: values(map!(map["fields"]), attachments)}

  defp decode!("insert_block", map, attachments) do
    %InsertBlock{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      module: module!(map["module"]),
      parent: optional_string!(map["parent"], "parent"),
      placement: placement!(map["placement"] || "append"),
      values: values(map!(map["values"]), attachments),
      texts: map!(map["texts"]),
      media: Map.new(map!(map["media"]), fn {name, asset} -> {name, asset!(asset, attachments)} end),
      configs: Map.new(map!(map["configs"]), fn {name, config} -> {name, map!(config)} end),
      uid: optional_string!(map["uid"], "uid"),
      ref_uids: map!(map["ref_uids"])
    }
  end

  defp decode!("set_block_media", map, attachments) do
    %SetBlockMedia{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      ref: string!(map["ref"], "ref"),
      asset: asset!(map["asset"], attachments)
    }
  end

  defp decode!("set_block_values", map, attachments) do
    %SetBlockValues{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      values: values(map!(map["values"]), attachments)
    }
  end

  defp decode!("set_block_active", map, _) do
    %SetBlockActive{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      ref: optional_string!(map["ref"], "ref"),
      active: boolean!(map["active"], "active")
    }
  end

  defp decode!("set_block_text", map, _) do
    %SetBlockText{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      ref: string!(map["ref"], "ref"),
      text: string!(map["text"], "text")
    }
  end

  defp decode!("move_block", map, _) do
    %MoveBlock{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      placement: placement!(map["placement"], true)
    }
  end

  defp decode!("set_block_table", map, attachments) do
    rows =
      case map["rows"] do
        rows when is_list(rows) -> Enum.map(rows, &values(map!(&1), attachments))
        _ -> invalid!(dgettext("content_proposals", "rows is a list of objects."))
      end

    %SetBlockTable{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      rows: rows
    }
  end

  defp decode!("set_block_selection", map, _) do
    identifiers =
      case map["identifiers"] do
        ids when is_list(ids) -> Enum.map(ids, &id!/1)
        _ -> invalid!(dgettext("content_proposals", "identifiers is a list of identifier ids."))
      end

    %SetBlockSelection{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      identifiers: identifiers
    }
  end

  defp decode!("set_ref_config", map, _) do
    %SetRefConfig{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      ref: string!(map["ref"], "ref"),
      config: map!(map["config"])
    }
  end

  defp decode!("copy_block", map, _) do
    %CopyBlock{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      placement: placement!(map["placement"] || "append", true),
      uid: optional_string!(map["uid"], "uid"),
      to_target: map["to"] && target!(map["to"]),
      to_field: optional_string!(map["to_field"], "to_field")
    }
  end

  defp decode!("set_block_details", map, _) do
    %SetBlockDetails{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      anchor: optional_text!(map["anchor"], "anchor"),
      description: optional_text!(map["description"], "description")
    }
  end

  defp decode!("delete_block", map, _) do
    %DeleteBlock{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid")
    }
  end

  defp decode!(op, _, _), do: invalid!(dgettext("content_proposals", "Unknown operation %{op}.", op: inspect(op)))

  @doc "Encode one operation to its JSON form."
  @spec encode(struct()) :: map()
  def encode(%CreateEntry{} = op),
    do: %{
      "op" => "create_entry",
      "content_type" => content_type(op.schema),
      "ref" => op.ref,
      "fields" => Map.new(op.fields, fn {key, value} -> {key, value(value)} end)
    }

  def encode(%SetFields{} = op),
    do: %{
      "op" => "set_fields",
      "target" => target(op.target),
      "fields" => Map.new(op.fields, fn {key, value} -> {key, value(value)} end)
    }

  def encode(%InsertBlock{} = op) do
    %{
      "op" => "insert_block",
      "target" => target(op.target),
      "field" => op.field,
      "module" => module(op.module),
      "parent" => op.parent,
      "placement" => placement(op.placement),
      "values" => Map.new(op.values, fn {key, value} -> {key, value(value)} end),
      "texts" => op.texts,
      "media" => Map.new(op.media, fn {name, asset} -> {name, asset(asset)} end),
      "configs" => op.configs,
      "uid" => op.uid,
      "ref_uids" => op.ref_uids
    }
  end

  def encode(%SetBlockMedia{} = op),
    do: %{
      "op" => "set_block_media",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "ref" => to_string(op.ref),
      "asset" => asset(op.asset)
    }

  def encode(%SetBlockValues{} = op),
    do: %{
      "op" => "set_block_values",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "values" => Map.new(op.values, fn {key, value} -> {key, value(value)} end)
    }

  def encode(%SetBlockText{} = op),
    do: %{
      "op" => "set_block_text",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "ref" => to_string(op.ref),
      "text" => op.text
    }

  def encode(%MoveBlock{} = op),
    do: %{
      "op" => "move_block",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "placement" => placement(op.placement)
    }

  def encode(%SetBlockActive{} = op),
    do: %{
      "op" => "set_block_active",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "ref" => op.ref,
      "active" => op.active
    }

  def encode(%SetBlockTable{} = op),
    do: %{
      "op" => "set_block_table",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "rows" => Enum.map(op.rows, fn row -> Map.new(row, fn {key, value} -> {key, value(value)} end) end)
    }

  def encode(%SetBlockSelection{} = op),
    do: %{
      "op" => "set_block_selection",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "identifiers" => op.identifiers
    }

  def encode(%SetRefConfig{} = op),
    do: %{
      "op" => "set_ref_config",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "ref" => op.ref,
      "config" => op.config
    }

  def encode(%CopyBlock{} = op),
    do: %{
      "op" => "copy_block",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "placement" => placement(op.placement),
      "uid" => op.uid,
      "to" => op.to_target && target(op.to_target),
      "to_field" => op.to_field
    }

  def encode(%SetBlockDetails{} = op),
    do: %{
      "op" => "set_block_details",
      "target" => target(op.target),
      "field" => op.field,
      "block_uid" => op.block_uid,
      "anchor" => op.anchor,
      "description" => op.description
    }

  def encode(%DeleteBlock{} = op),
    do: %{"op" => "delete_block", "target" => target(op.target), "field" => op.field, "block_uid" => op.block_uid}

  @doc "The name agents use for a content type."
  @spec content_type(module()) :: String.t()
  def content_type(schema), do: inspect(schema)

  @doc "Resolve a content type name to a registered schema."
  @spec schema(term()) :: {:ok, module()} | :error
  def schema(name) when is_binary(name) do
    case Enum.find(Brando.Authorization.Catalog.schemas(), &(inspect(&1) == name || to_string(&1) == name)) do
      nil -> :error
      schema -> {:ok, schema}
    end
  end

  def schema(schema) when is_atom(schema) and not is_nil(schema), do: schema(inspect(schema))
  def schema(_), do: :error

  @doc "Encode a proposal target."
  @spec target(term()) :: map()
  def target({:new, ref}), do: %{"new" => ref}
  def target({schema, id}), do: %{"content_type" => content_type(schema), "id" => id}

  defp target!(%{"new" => ref}), do: {:new, string!(ref, "new")}

  defp target!(%{"content_type" => name, "id" => id}) do
    {schema!(name), Brando.Content.Transfer.Catalog.id!(id)}
  rescue
    Brando.Content.Transfer.Error -> invalid!(dgettext("content_proposals", "A target needs a numeric id."))
  end

  defp target!(_),
    do: invalid!(dgettext("content_proposals", "A target is {content_type, id} or {new: ref}."))

  defp schema!(name) do
    case schema(name) do
      {:ok, schema} -> schema
      :error -> invalid!(dgettext("content_proposals", "Unknown content type %{name}.", name: inspect(name)))
    end
  end

  defp module(id) when is_integer(id), do: "local:#{id}"
  defp module({origin, id}), do: "#{origin}:#{id}"
  defp module(reference) when is_binary(reference), do: reference

  defp module!(reference) when is_integer(reference) or is_binary(reference) do
    Brando.Content.SharedLibrary.reference(reference)
  rescue
    _ -> invalid!(dgettext("content_proposals", "Unknown module reference %{module}.", module: inspect(reference)))
  end

  defp module!(reference),
    do: invalid!(dgettext("content_proposals", "Unknown module reference %{module}.", module: inspect(reference)))

  defp placement(:append), do: "append"
  defp placement({side, uid}), do: %{to_string(side) => uid}

  defp placement!(placement, into? \\ false)
  defp placement!("append", _), do: :append
  defp placement!(%{"before" => uid}, _) when is_binary(uid), do: {:before, uid}
  defp placement!(%{"after" => uid}, _) when is_binary(uid), do: {:after, uid}
  defp placement!(%{"into" => uid}, true) when is_binary(uid), do: {:into, uid}

  defp placement!(_, true),
    do: invalid!(dgettext("content_proposals", "Placement is \"append\", {before: uid}, {after: uid} or {into: uid}."))

  defp placement!(_, false),
    do: invalid!(dgettext("content_proposals", "Placement is \"append\", {before: uid} or {after: uid}."))

  defp asset({:gallery, items}), do: %{"gallery" => Enum.map(items, &asset/1)}
  defp asset({kind, id}), do: %{"kind" => to_string(kind), "id" => id}

  defp asset!(%{"kind" => kind, "id" => id}, _) when kind in ~w(image video file) and is_integer(id),
    do: {String.to_existing_atom(kind), id}

  defp asset!(%{"gallery" => items}, attachments) when is_list(items) do
    {:gallery,
     Enum.map(items, fn item ->
       case asset!(item, attachments) do
         {kind, _} = asset when kind in [:image, :video] -> asset
         _ -> invalid!(dgettext("content_proposals", "A gallery holds images and videos."))
       end
     end)}
  end

  defp asset!(alias, attachments) when is_binary(alias) do
    case Map.fetch(attachments, alias) do
      {:ok, {kind, id}} -> {kind, id}
      :error -> invalid!(dgettext("content_proposals", "No attachment is called %{alias}.", alias: alias))
    end
  end

  defp asset!(_, _),
    do:
      invalid!(
        dgettext("content_proposals", "Media is {kind: image|video|file, id}, an attachment alias or {gallery: [media]}.")
      )

  # A reference to an entry the proposal creates. It is kept so validation
  # can report the draft dependency.
  defp values(values, attachments),
    do: Map.new(values, fn {key, value} -> {key, decode_value(value, attachments)} end)

  defp decode_value(%{"new" => ref}, _) when is_binary(ref), do: {:new, ref}
  defp decode_value(%{"asset" => alias}, attachments), do: asset!(alias, attachments)
  defp decode_value(%{"kind" => _, "id" => _} = asset, attachments), do: asset!(asset, attachments)
  defp decode_value(%{"gallery" => _} = asset, attachments), do: asset!(asset, attachments)

  defp decode_value(%{"content_type" => name, "id" => id}, _) do
    {:entry, schema!(name), Brando.Content.Transfer.Catalog.id!(id)}
  rescue
    Brando.Content.Transfer.Error -> invalid!(dgettext("content_proposals", "A target needs a numeric id."))
  end

  defp decode_value(list, attachments) when is_list(list), do: Enum.map(list, &decode_value(&1, attachments))
  defp decode_value(value, _), do: value

  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  defp value({:new, ref}), do: %{"new" => ref}
  defp value({:entry, schema, id}), do: %{"content_type" => content_type(schema), "id" => id}
  defp value({kind, _} = asset) when kind in [:image, :video, :file, :gallery], do: asset(asset)
  defp value(value), do: value

  defp map!(nil), do: %{}
  defp map!(map) when is_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp map!(_), do: invalid!(dgettext("content_proposals", "Expected an object."))

  defp string!(value, _) when is_binary(value) and value != "", do: value
  defp string!(value, _) when is_atom(value) and not is_nil(value), do: to_string(value)
  defp string!(_, key), do: invalid!(dgettext("content_proposals", "%{key} is required.", key: key))

  defp boolean!(value, _key) when is_boolean(value), do: value
  defp boolean!(_, key), do: invalid!(dgettext("content_proposals", "%{key} is true or false.", key: key))

  defp id!(id) when is_integer(id), do: id

  defp id!(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> invalid!(dgettext("content_proposals", "Expected a numeric id."))
    end
  end

  defp id!(_), do: invalid!(dgettext("content_proposals", "Expected a numeric id."))

  # Text that may be cleared with "".
  defp optional_text!(value, _key) when is_nil(value) or is_binary(value), do: value
  defp optional_text!(_, key), do: invalid!(dgettext("content_proposals", "%{key} is text.", key: key))

  defp optional_string!(nil, _key), do: nil
  defp optional_string!(value, key), do: string!(value, key)

  defp invalid!(message), do: throw({:invalid, message})
end
