defmodule BrandoAdmin.Components.Form.DraftPreview do
  @moduledoc false
  use Gettext, backend: Brando.Gettext

  # Presentation only: the original payload remains intact for restore/export.
  @metadata ~w(id uid creator_id entry_id parent_id module_id block_id table_row_id module_version source sequence)

  def sections(payload) do
    entry = section(gettext("Entry fields"), payload["main"])

    blocks =
      payload
      |> groups("blocks")
      |> Enum.flat_map(fn {field, rows} ->
        rows
        |> List.wrap()
        |> Enum.with_index(1)
        |> Enum.map(fn {row, index} ->
          title =
            if field == "blocks",
              do: gettext("Block %{number}", number: index),
              else: gettext("%{field} · Block %{number}", field: label(field), number: index)

          section(title, row)
        end)
      end)

    related =
      payload
      |> groups("transformers")
      |> Enum.map(fn {field, rows} -> section(label(field), rows) end)

    Enum.reject(blocks ++ [entry] ++ related, &(&1.rows == []))
  end

  defp groups(payload, key) do
    case payload[key] do
      values when is_map(values) -> Enum.sort(values)
      _ -> []
    end
  end

  defp section(title, content), do: %{title: title, rows: rows(content, [])}

  defp rows(%{"key" => key, "type" => type} = var, path) when is_binary(key) do
    name = if var["label"] in [nil, ""], do: label(key), else: var["label"]
    path = path ++ [name]

    case type do
      "boolean" -> rows(var["value_boolean"], path)
      asset when asset in ["image", "video", "file", "gallery"] -> rows(Map.take(var, [asset <> "_id"]), path)
      "link" -> rows(Map.take(var, ~w(value identifier_id link_text link_type link_target_blank)), path)
      _ -> rows(var["value"], path)
    end
  end

  defp rows(%{"name" => name, "data" => data}, path) when is_binary(name),
    do: rows(data, path ++ [label(name)])

  defp rows(%{"type" => type, "refs" => _} = block, path) when type in ["module", "module_entry", "container"] do
    block
    |> Map.take(~w(refs vars children table_rows anchor description))
    |> content_rows(path)
  end

  defp rows(value, path) when is_map(value) do
    content_rows(value, path)
  end

  defp rows(values, path) when is_list(values) do
    values
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {value, index} ->
      if is_map(value) && (is_binary(value["key"]) || is_binary(value["name"])) do
        rows(value, path)
      else
        rows(value, path ++ [to_string(index)])
      end
    end)
  end

  defp rows(value, _) when value in [nil, ""], do: []
  defp rows(value, path), do: [%{field: Enum.join(path, " › "), value: readable(value)}]

  defp content_rows(value, path) do
    value
    |> Map.drop(@metadata)
    |> Enum.sort_by(fn {key, _} -> {key not in ~w(title text value refs vars), key} end)
    |> Enum.flat_map(fn {key, value} ->
      # These are serialization wrappers, not field names an editor recognizes.
      next = if key in ["block", "data", "refs", "vars"], do: path, else: path ++ [label(key)]
      rows(value, next)
    end)
  end

  # Keep recovery text selectable without executing stored markup.
  defp readable(value) when is_binary(value) do
    if String.contains?(value, ["<p", "<br", "<div", "<h", "<ul", "<ol", "<strong", "<em", "<a "]) do
      value
      |> String.replace(~r/<br\s*\/?\s*>|<\/(p|div|h[1-6]|li)>/i, "\n")
      |> HtmlSanitizeEx.strip_tags()
      |> HtmlEntities.decode()
      |> String.trim()
    else
      value
    end
  end

  defp readable(value), do: value

  defp label(key) do
    label = Phoenix.Naming.humanize(key)
    if String.ends_with?(key, "_id"), do: label <> " ID", else: label
  end
end
