defmodule BrandoAdmin.Components.Form.DraftPreview.Structure do
  @moduledoc false
  use Gettext, backend: Brando.Gettext
  alias BrandoAdmin.Components.Form.DraftPreview.References

  # A presentation-only collection. Items are aligned by identity, while their
  # original positions are retained separately for the movement summary.
  defstruct items: []

  def compare(saved, recovered) do
    block_fields = keys(saved["blocks"], recovered["blocks"])

    blocks =
      Enum.flat_map(block_fields, fn field ->
        before = get_in(saved, ["blocks", field]) || []
        after_rows = get_in(recovered, ["blocks", field]) || []
        prefix = if field == "blocks", do: [], else: [label(field)]
        blocks(before, after_rows, prefix)
      end)

    entry = content(gettext("Entry fields"), saved["main"], recovered["main"])

    related =
      Enum.flat_map(keys(saved["transformers"], recovered["transformers"]), fn field ->
        content(label(field), get_in(saved, ["transformers", field]), get_in(recovered, ["transformers", field]))
      end)

    blocks ++ entry ++ related
  end

  defp blocks(before, after_rows, path) do
    {before, after_rows} = {indexed(before, &block_key/2), indexed(after_rows, &block_key/2)}
    title = Enum.join(path ++ [gettext("Block order")], " · ")
    order = order(title, before, after_rows, :block)

    comparisons =
      Enum.flat_map(union(before, after_rows), fn key ->
        old = find(before, key)
        new = find(after_rows, key)
        item = new || old
        position = gettext("Block %{number}", number: item.position)
        current_path = path ++ [position]
        old_block = old && unwrap(old.value)
        new_block = new && unwrap(new.value)

        content(Enum.join(current_path, " › "), without_children(old_block), without_children(new_block)) ++
          blocks(children(old_block), children(new_block), current_path)
      end)

    order ++ comparisons
  end

  defp block_key(row, index) do
    block = unwrap(row)

    cond do
      present(block["uid"]) -> {:uid, block["uid"]}
      present(block["id"]) -> {:id, to_string(block["id"])}
      true -> {:position, index}
    end
  end

  defp unwrap(%{"block" => block}) when is_map(block), do: block
  defp unwrap(row), do: row
  defp without_children(nil), do: nil
  defp without_children(block), do: Map.delete(block, "children")
  defp children(nil), do: []
  defp children(block), do: block["children"] || []

  defp content(title, before, after_value) do
    {before, after_value, orders} = align(before, after_value, [title])
    # A ref may contain both its gallery and per-placement overrides. They
    # describe the same movement, so present that order just once.
    Enum.uniq_by(orders, &{&1.title, Enum.map(&1.moves, fn move -> {move.title, move.from, move.to} end)}) ++
      [%{kind: :content, title: title, before: before, after: after_value}]
  end

  defp align(%References{} = before, after_value, _), do: {before, after_value, []}
  defp align(before, %References{} = after_value, _), do: {before, after_value, []}

  defp align(before, after_value, path)
       when (is_map(before) and (is_map(after_value) or is_nil(after_value))) or
              (is_nil(before) and is_map(after_value)) do
    old = if is_map(before), do: before, else: %{}
    new = if is_map(after_value), do: after_value, else: %{}

    Enum.reduce(keys(old, new), {%{}, %{}, []}, fn key, {a, b, orders} ->
      nested_path = if key in ~w(block data refs vars gallery), do: path, else: path ++ [label(key)]

      {left, right, nested} =
        if key in ~w(gallery_objects gallery_object_overrides) && is_list(old[key] || []) && is_list(new[key] || []) do
          gallery(old[key] || [], new[key] || [], path, key)
        else
          align(old[key], new[key], nested_path)
        end

      {if(Map.has_key?(old, key), do: Map.put(a, key, left), else: a),
       if(Map.has_key?(new, key), do: Map.put(b, key, right), else: b), orders ++ nested}
    end)
  end

  defp align(before, after_value, path)
       when (is_list(before) and (is_list(after_value) or is_nil(after_value))) or
              (is_nil(before) and is_list(after_value)) do
    old = indexed(before || [], &named_key/2)
    new = indexed(after_value || [], &named_key/2)

    {left, right, orders} =
      Enum.reduce(union(old, new), {[], [], []}, fn key, {a, b, orders} ->
        x = find(old, key)
        y = find(new, key)
        item = y || x
        name = if is_map(item.value), do: item.value["name"] || item.value["key"]
        nested_path = path ++ [if(name, do: label(name), else: to_string(item.position))]
        {l, r, nested} = align(x && x.value, y && y.value, nested_path)
        {if(x, do: a ++ [l], else: a), if(y, do: b ++ [r], else: b), orders ++ nested}
      end)

    {left, right, orders}
  end

  defp align(before, after_value, _), do: {before, after_value, []}

  defp named_key(value, index) when is_map(value), do: value["name"] || value["key"] || {:position, index}
  defp named_key(_, index), do: {:position, index}

  defp gallery(before, after_rows, path, field) do
    old = indexed(before, &media_key/2)
    new = indexed(after_rows, &media_key/2)
    title = Enum.join(path ++ [gettext("Gallery order")], " · ")
    orders = order(title, old, new, :gallery)

    {left, right} =
      Enum.reduce(union(old, new), {[], []}, fn key, {a, b} ->
        x = find(old, key)
        y = find(new, key)
        item = y || x
        reference = reference(item.value)
        name = if reference, do: reference.title, else: gettext("Item %{number}", number: item.position)
        make = fn value -> %{key: key, label: name, value: gallery_content(value, field)} end
        {if(x, do: a ++ [make.(x.value)], else: a), if(y, do: b ++ [make.(y.value)], else: b)}
      end)

    {%__MODULE__{items: left}, %__MODULE__{items: right}, orders}
  end

  defp media_key(value, index) do
    cond do
      present(value["id"]) ->
        {:id, to_string(value["id"])}

      ref = reference(value) ->
        {ref.kind, to_string(ref.id)}

      present(value["object_id"]) ->
        {if(value["object_type"] == "image", do: :image, else: :video), to_string(value["object_id"])}

      present(value["image_id"]) ->
        {:image, to_string(value["image_id"])}

      present(value["video_id"]) ->
        {:video, to_string(value["video_id"])}

      true ->
        {:position, index}
    end
  end

  defp gallery_content(value, "gallery_objects"), do: Map.drop(value, ~w(id sequence gallery_id))

  defp gallery_content(value, "gallery_object_overrides") do
    settings =
      value
      |> Map.drop(~w(object_id object_type _gallery_preview))
      |> Map.reject(fn {key, value} -> is_nil(value) || (String.starts_with?(key, "use_default_") && value == true) end)

    if settings == %{}, do: %{}, else: Map.put(settings, "media", reference(value))
  end

  defp order(title, before, after_rows, kind) do
    before_keys = Enum.map(before, & &1.key)
    after_keys = Enum.map(after_rows, & &1.key)
    common = MapSet.intersection(MapSet.new(before_keys), MapSet.new(after_keys))
    # Insertion/removal shifts positions but does not reorder surviving items.
    reordered? =
      Enum.filter(before_keys, &MapSet.member?(common, &1)) != Enum.filter(after_keys, &MapSet.member?(common, &1))

    moves =
      if reordered? do
        Enum.flat_map(after_rows, fn item ->
          old = find(before, item.key)

          if old && old.position != item.position do
            reference = reference(item.value)

            name =
              if kind == :block,
                do: block_label(unwrap(item.value), old.position),
                else: (reference && reference.title) || gettext("Item %{number}", number: old.position)

            [
              %{
                key: item.key,
                title: name,
                thumbnail: reference && reference.thumbnail,
                from: old.position,
                to: item.position
              }
            ]
          else
            []
          end
        end)
      else
        []
      end

    if moves == [], do: [], else: [%{kind: :order, title: title, moves: moves, before: [], after: []}]
  end

  defp block_label(block, position) do
    present(block["description"]) || first_text(block) || gettext("Block %{number}", number: position)
  end

  defp first_text(%References{}), do: nil

  defp first_text(%{"text" => text}) when is_binary(text) and text != "",
    do: text |> HtmlSanitizeEx.strip_tags() |> HtmlEntities.decode() |> String.trim() |> String.slice(0, 100) |> present()

  defp first_text(map) when is_map(map), do: map |> Enum.sort() |> Enum.find_value(fn {_, value} -> first_text(value) end)
  defp first_text(list) when is_list(list), do: Enum.find_value(list, &first_text/1)
  defp first_text(_), do: nil

  defp reference(%References{} = value), do: value
  defp reference(map) when is_map(map), do: map |> Enum.sort() |> Enum.find_value(fn {_, value} -> reference(value) end)
  defp reference(list) when is_list(list), do: Enum.find_value(list, &reference/1)
  defp reference(_), do: nil

  # Occurrences distinguish repeated placements of the same media item.
  defp indexed(values, identity) do
    {items, _} =
      values
      |> Enum.with_index(1)
      |> Enum.map_reduce(%{}, fn {value, index}, counts ->
        key = identity.(value, index)
        occurrence = Map.get(counts, key, 0)
        {%{key: {key, occurrence}, value: value, position: index}, Map.put(counts, key, occurrence + 1)}
      end)

    items
  end

  defp find(items, key), do: Enum.find(items, &(&1.key == key))
  defp union(before, after_rows), do: Enum.map(after_rows ++ before, & &1.key) |> Enum.uniq()

  defp keys(before, after_value),
    do: (Map.keys(before || %{}) ++ Map.keys(after_value || %{})) |> Enum.uniq() |> Enum.sort()

  defp label(key), do: Phoenix.Naming.humanize(key)
  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value
end
