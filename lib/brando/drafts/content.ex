defmodule Brando.Drafts.Content do
  @moduledoc "Comparison of recovery content without changing the stored restore payload."

  @override_fields ~w(title credits alt autoplay loop muted controls preload)
  @override_keys ["object_id", "object_type"] ++ @override_fields ++ Enum.map(@override_fields, &("use_default_" <> &1))

  def checksum(payload), do: payload |> normalize_payload() |> Brando.Drafts.checksum()

  defp normalize_payload(%{"main" => _, "blocks" => blocks} = payload) when is_map(blocks) do
    Map.new(payload, fn
      {"blocks", fields} -> {"blocks", Map.new(fields, fn {name, rows} -> {name, ordered(rows, &entry_block/1)} end)}
      {key, value} -> {key, normalize(value)}
    end)
  end

  defp normalize_payload(payload), do: normalize(payload)

  defp normalize(values) when is_list(values), do: Enum.map(values, &normalize/1)
  defp normalize(value) when is_map(value), do: Map.new(value, &normalize_field/1)
  defp normalize(value), do: value

  defp normalize_field({"vars", vars}) when is_list(vars), do: {"vars", Enum.map(vars, &variable/1)}

  defp normalize_field({"gallery_object_overrides", overrides}) when is_list(overrides),
    do: {"gallery_object_overrides", overrides |> Enum.reject(&default_override?/1) |> normalize()}

  defp normalize_field({key, child}), do: {key, normalize(child)}

  defp entry_block(%{"block" => block} = row), do: row |> Map.put("block", block(block)) |> normalize()
  defp entry_block(row), do: block(row)

  defp block(value) when is_map(value) do
    value
    |> Map.delete("sequence")
    |> Map.new(fn
      {"children", children} -> {"children", ordered(children, &block/1)}
      {"refs", refs} -> {"refs", ordered(refs, &normalize/1)}
      {"table_rows", rows} -> {"table_rows", ordered(rows, &normalize/1)}
      {"block_identifiers", identifiers} -> {"block_identifiers", ordered(identifiers, &normalize/1)}
      field -> normalize_field(field)
    end)
  end

  defp block(value), do: normalize(value)

  # Ecto's positional casts and the block store derive these sequence values
  # from the list. Keep the list order: moving an item must still change the hash.
  defp ordered(rows, fun) when is_list(rows) do
    Enum.map(rows, fn
      row when is_map(row) -> row |> Map.delete("sequence") |> fun.()
      row -> fun.(row)
    end)
  end

  defp ordered(value, _), do: normalize(value)

  # Var casting fills missing ownership and rewrites sequence on mount. Neither
  # is an edit. Keep IDs, types, values, flags and configuration verbatim.
  defp variable(%{"key" => key, "type" => type} = var) when is_binary(key) and is_binary(type),
    do: var |> Map.drop(["creator_id", "sequence"]) |> normalize()

  defp variable(value), do: normalize(value)

  # A gallery initializes one override per object even when every value inherits
  # its default. Unknown keys, explicit false/empty values and dormant custom
  # values are retained, so comparison cannot conceal real or invalid input.
  defp default_override?(%{"object_id" => id, "object_type" => type} = override)
       when not is_nil(id) and type in ["image", "video"] do
    valid_object_id?(id) && Enum.all?(Map.keys(override), &(&1 in @override_keys)) &&
      Enum.all?(@override_fields, fn field ->
        is_nil(override[field]) && Map.get(override, "use_default_" <> field, true) == true
      end)
  end

  defp default_override?(_), do: false

  defp valid_object_id?(id) when is_integer(id), do: id > 0

  defp valid_object_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 -> true
      _ -> false
    end
  end

  defp valid_object_id?(_), do: false
end
