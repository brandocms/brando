defmodule Brando.Content.Transfer.Recovery do
  @moduledoc false
  def copy(blocks) do
    uids = blocks |> Brando.Content.Transfer.Portable.walk(& &1["uid"]) |> Map.new(&{&1, Brando.Utils.generate_uid()})
    scrub(blocks, uids)
  end

  def validate_dependencies!(blocks, actor) do
    references(blocks)
    |> Enum.uniq()
    |> Enum.each(fn {kind, id} ->
      Brando.Content.Transfer.Dependencies.load!(kind, id, actor)
    end)
  end

  defp references(value) when is_map(value) do
    fields =
      Brando.Content.Transfer.Portable.asset_fields()
      |> Map.merge(%{"source_id" => "markdown_source", "version_id" => "markdown_version"})
      |> Map.delete("gallery_id")

    Enum.flat_map(value, fn {key, value} ->
      if fields[key] && value, do: [{fields[key], value}], else: references(value)
    end)
  end

  defp references(value) when is_list(value), do: Enum.flat_map(value, &references/1)
  defp references(_), do: []

  defp scrub(value, uids) when is_map(value) do
    value
    |> Map.drop(~w(id entry_id parent_id block_id table_row_id module_version))
    |> Map.new(fn
      {"gallery", snapshot} -> {"gallery", snapshot}
      {"uid", uid} -> {"uid", Map.get(uids, uid, Brando.Utils.generate_uid())}
      {key, val} -> {key, scrub(val, uids)}
    end)
  end

  defp scrub(value, uids) when is_list(value), do: Enum.map(value, &scrub(&1, uids))

  defp scrub(value, uids) when is_binary(value) do
    Regex.replace(~r/(data-footnote-uid\s*=\s*)(["'])([^"']+)\2/, value, fn _, prefix, quote, uid ->
      prefix <> quote <> Map.get(uids, uid, uid) <> quote
    end)
  end

  defp scrub(value, _), do: value
end
