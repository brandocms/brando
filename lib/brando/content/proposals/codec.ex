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
      %{"op" => "move_block", "target" => target, "block_uid" => uid, "placement" => placement}
      %{"op" => "delete_block", "target" => target, "block_uid" => uid}

  A `target` is `%{"content_type" => …, "id" => 12}` or `%{"new" => ref}`. An
  `asset` is `%{"kind" => "image" | "video", "id" => 3}` or the alias of a
  conversation attachment such as `"image1"`.
  """
  alias Brando.Content.Proposals.{
    CreateEntry,
    DeleteBlock,
    InsertBlock,
    MoveBlock,
    SetBlockMedia,
    SetBlockText,
    SetBlockValues,
    SetFields
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

  defp decode!("create_entry", map, _),
    do: %CreateEntry{schema: schema!(map["content_type"]), ref: string!(map["ref"], "ref"), fields: map!(map["fields"])}

  defp decode!("set_fields", map, _), do: %SetFields{target: target!(map["target"]), fields: map!(map["fields"])}

  defp decode!("insert_block", map, attachments) do
    %InsertBlock{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      module: module!(map["module"]),
      parent: optional_string!(map["parent"], "parent"),
      placement: placement!(map["placement"] || "append"),
      values: values(map!(map["values"])),
      texts: map!(map["texts"]),
      media: Map.new(map!(map["media"]), fn {name, asset} -> {name, asset!(asset, attachments)} end),
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

  defp decode!("set_block_values", map, _) do
    %SetBlockValues{
      target: target!(map["target"]),
      field: map["field"] || "blocks",
      block_uid: string!(map["block_uid"], "block_uid"),
      values: values(map!(map["values"]))
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
      placement: placement!(map["placement"])
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
    do: %{"op" => "create_entry", "content_type" => content_type(op.schema), "ref" => op.ref, "fields" => op.fields}

  def encode(%SetFields{} = op), do: %{"op" => "set_fields", "target" => target(op.target), "fields" => op.fields}

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

  defp placement!("append"), do: :append
  defp placement!(%{"before" => uid}) when is_binary(uid), do: {:before, uid}
  defp placement!(%{"after" => uid}) when is_binary(uid), do: {:after, uid}

  defp placement!(_),
    do: invalid!(dgettext("content_proposals", "Placement is \"append\", {before: uid} or {after: uid}."))

  defp asset({kind, id}), do: %{"kind" => to_string(kind), "id" => id}

  defp asset!(%{"kind" => kind, "id" => id}, _) when kind in ~w(image video) and is_integer(id),
    do: {String.to_existing_atom(kind), id}

  defp asset!(alias, attachments) when is_binary(alias) do
    case Map.fetch(attachments, alias) do
      {:ok, {kind, id}} -> {kind, id}
      :error -> invalid!(dgettext("content_proposals", "No attachment is called %{alias}.", alias: alias))
    end
  end

  defp asset!(_, _),
    do: invalid!(dgettext("content_proposals", "Media is {kind: image|video, id} or an attachment alias."))

  # A reference to an entry the proposal creates. It is kept so validation
  # can report the draft dependency.
  defp values(values), do: Map.new(values, fn {key, value} -> {key, decode_value(value)} end)
  defp decode_value(%{"new" => ref}) when is_binary(ref), do: {:new, ref}
  defp decode_value(value), do: value

  defp value({:new, ref}), do: %{"new" => ref}
  defp value(value), do: value

  defp map!(nil), do: %{}
  defp map!(map) when is_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp map!(_), do: invalid!(dgettext("content_proposals", "Expected an object."))

  defp string!(value, _) when is_binary(value) and value != "", do: value
  defp string!(value, _) when is_atom(value) and not is_nil(value), do: to_string(value)
  defp string!(_, key), do: invalid!(dgettext("content_proposals", "%{key} is required.", key: key))

  defp optional_string!(nil, _key), do: nil
  defp optional_string!(value, key), do: string!(value, key)

  defp invalid!(message), do: throw({:invalid, message})
end
