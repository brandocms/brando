defmodule BrandoAdmin.ContentPreview do
  @moduledoc """
  Readable, identity-aware block lines for `Components.TextDiff`.

  Saved blocks must have their normal BlockPreloads loaded. Portable blocks use
  an asset index from `bundle_assets/2`. Projection never queries or changes data.
  This is a content summary, not a complete rendering or configuration diff.
  """
  use Gettext, backend: Brando.Gettext
  alias Brando.Content.Transfer.Labels
  alias Brando.Drafts.Params
  alias Brando.Villain.Blocks.GalleryObjectOverride

  @media ~w(image file video gallery)
  @associations ~w(image file video thumbnail gallery gallery_objects refs vars table_rows children)a

  @doc "Use the selected destination asset's identity and metadata when it is mapped."
  def bundle_assets(dependencies, bindings) do
    dependencies
    |> Enum.filter(fn {_, dep} -> dep["kind"] in @media end)
    |> Map.new(fn {token, dep} ->
      asset =
        if record = bindings[token] do
          snapshot(record)
          |> Map.put("preview_identity", {dep["kind"], record.id})
        else
          (dep["data"] || %{})
          |> Map.put("preview_identity", {:bundle, token})
          |> Map.put("gallery_objects", dep["objects"] || [])
        end

      {token, Map.put(asset, "preview_label", dep["label"])}
    end)
  end

  def lines(blocks, assets \\ %{}), do: block_lines(snapshot(blocks), assets, [])

  defp block_lines(blocks, assets, parent) do
    # Description + occurrence gives independently saved entries comparable
    # locations without mistaking a repeated asset in another block for context.
    {groups, _} =
      Enum.map_reduce(blocks, %{}, fn block, counts ->
        title = present(block["description"]) || Labels.field(block["type"] || "block")
        count = Map.get(counts, title, 0)
        location = parent ++ [{title, count}]

        content =
          [line(title, nil, :heading)] ++
            Enum.flat_map(block["refs"] || [], &ref_lines(&1, assets, location)) ++
            Enum.flat_map(block["vars"] || [], &var_lines(&1, assets, location)) ++
            table_lines(block["table_rows"] || [], assets, location) ++
            block_lines(block["children"] || [], assets, location)

        {content, Map.put(counts, title, count + 1)}
      end)

    groups |> Enum.intersperse([line("")]) |> List.flatten()
  end

  defp ref_lines(ref, assets, location) do
    data = get_in(ref, ["data", "data"]) || %{}
    label = present(ref["description"]) || ref["name"]
    text = data["text"] || data["html"] || data["code"]
    text_lines = if is_binary(text), do: plain_lines(text, data["code"] != nil), else: []
    text_lines ++ media_lines(ref, Map.reject(data, fn {_, value} -> value == "" end), label, assets, location)
  end

  defp var_lines(var, assets, location) do
    label = present(var["label"]) || var["key"]
    text = if present(var["value"]), do: plain_lines("#{label}: #{var["value"]}"), else: []
    text ++ media_lines(var, %{}, label, assets, location)
  end

  defp table_lines(rows, assets, location) do
    rows
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {row, index} ->
      [line(dgettext("content_transfer", "Row %{number}", number: index), nil, :heading)] ++
        Enum.flat_map(row["vars"] || [], &var_lines(&1, assets, location ++ [{:row, index}]))
    end)
  end

  defp media_lines(owner, overrides, label, assets, location) do
    Enum.flat_map(@media, fn kind ->
      case asset(owner, kind, assets) do
        nil -> []
        media -> media_lines(kind, media, overrides, label, assets, location)
      end
    end)
  end

  defp media_lines("gallery", gallery, overrides, label, assets, location) do
    objects = Enum.sort_by(gallery["gallery_objects"] || [], &(&1["sequence"] || 0))
    location = location ++ [{:gallery, label}]
    index = GalleryObjectOverride.index(overrides["gallery_object_overrides"])

    [line(media_label("gallery", label), location, :media)] ++
      Enum.flat_map(objects, fn object ->
        # Saved objects hold media ids and bundle objects hold media tokens;
        # overrides carry the same kind of value in `object_id`.
        override =
          cond do
            id = object["image_id"] -> GalleryObjectOverride.lookup(index, :image, id)
            id = object["video_id"] -> GalleryObjectOverride.lookup(index, :video, id)
            true -> nil
          end || %{}

        defaults = Map.reject(object["config"] || %{}, fn {_, value} -> value in [nil, ""] end)

        config =
          Enum.reduce(override, defaults, fn {field, value}, acc ->
            if field in ~w(title alt caption credits) && override["use_default_" <> field] != true && !is_nil(value),
              do: Map.put(acc, field, value),
              else: acc
          end)

        media_lines(object, config, nil, assets, location)
      end)
  end

  defp media_lines(kind, media, overrides, label, assets, location) do
    identity = media["preview_identity"] || {kind, media["id"]}
    key = {location, label, identity}
    metadata = Map.merge(media, Map.reject(overrides, fn {_, value} -> is_nil(value) end))
    filename = filename(kind, media, assets)

    [line(media_label(kind, label) <> ": " <> filename, key, :media)] ++
      metadata_lines(metadata, key) ++ thumbnail_lines(kind, media, assets, key)
  end

  defp thumbnail_lines("video", media, assets, key) do
    case asset(media, "thumbnail", assets) do
      nil -> []
      image -> media_lines("image", image, %{}, dgettext("content_transfer", "Poster"), assets, [key])
    end
  end

  defp thumbnail_lines(_, _, _, _), do: []

  defp metadata_lines(metadata, key) do
    fields = [
      {"title", dgettext("content_transfer", "Title")},
      {"alt", dgettext("content_transfer", "Alt text")},
      {"caption", dgettext("content_transfer", "Caption")},
      {"credits", dgettext("content_transfer", "Credits")},
      {"link", dgettext("content_transfer", "Link")}
    ]

    text =
      Enum.flat_map(fields, fn {field, label} ->
        if value = present(text_value(metadata[field])),
          do: [line("#{label}: #{plain(value)}", {key, field}, :detail)],
          else: []
      end)

    focal =
      case metadata["focal"] do
        %{"x" => x, "y" => y} when is_number(x) and is_number(y) ->
          [line(dgettext("content_transfer", "Focal point: %{x}% / %{y}%", x: x, y: y), {key, :focal}, :detail)]

        _ ->
          []
      end

    text ++ focal
  end

  defp asset(owner, kind, assets) do
    case owner[kind <> "_id"] do
      nil -> owner[kind]
      token when is_binary(token) -> assets[token] || owner[kind] || missing_asset(kind, token)
      id -> owner[kind] || missing_asset(kind, id)
    end
  end

  defp missing_asset(kind, id),
    do: %{"preview_identity" => {kind, id}, "preview_label" => dgettext("content_transfer", "Unavailable media")}

  defp filename("image", media, _), do: basename(media["path"]) || media_name(media)
  defp filename("file", media, _), do: present(media["filename"]) || media_name(media)

  defp filename("video", media, assets) do
    file = asset(media, "file", assets)

    (file && present(file["filename"])) || present(media["source_url"]) || present(media["remote_id"]) ||
      media_name(media)
  end

  defp media_name(media),
    do:
      present(Brando.Type.I18nString.get(media["title"], nil)) || present(media["preview_label"]) ||
        dgettext("content_transfer", "Unnamed media")

  # An image's texts are language → text maps: show every language, so a
  # difference in any of them is visible in the comparison.
  defp text_value(%{} = values) do
    values
    |> Enum.reject(fn {_language, text} -> text in [nil, ""] end)
    |> Enum.sort()
    |> Enum.map_join(" · ", fn {language, text} -> "#{String.upcase(to_string(language))}: #{text}" end)
  end

  defp text_value(value), do: value

  defp basename(path) when is_binary(path) and path != "", do: Path.basename(path)
  defp basename(_), do: nil
  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp media_label(kind, nil), do: kind_label(kind)
  defp media_label(kind, ""), do: kind_label(kind)
  defp media_label(kind, label), do: kind_label(kind) <> " · " <> label
  defp kind_label("image"), do: dgettext("content_transfer", "Image")
  defp kind_label("file"), do: dgettext("content_transfer", "File")
  defp kind_label("video"), do: dgettext("content_transfer", "Video")
  defp kind_label("gallery"), do: dgettext("content_transfer", "Gallery")

  defp plain_lines(text, code? \\ false),
    do: if(code?, do: text, else: plain(text)) |> String.split(~r/\r\n|\n|\r/) |> Enum.map(&line/1)

  defp plain(text) do
    text
    |> Floki.parse_fragment!()
    |> Floki.traverse_and_update(fn
      {tag, attrs, children} when tag in ~w(p div li h1 h2 h3 h4 h5 h6 blockquote pre) ->
        {tag, attrs, children ++ ["\n"]}

      node ->
        node
    end)
    |> Floki.text(style: false)
    |> String.trim_trailing("\n")
  end

  defp line(text, key \\ nil, type \\ nil), do: %{text: text, key: key, type: type}

  # Params deliberately excludes belongs_to assets. Keep just the loaded media
  # associations needed here; do not serialize parent/module graphs or query them.
  defp snapshot(%Ecto.Association.NotLoaded{}), do: nil

  defp snapshot(%_{} = record) do
    Enum.reduce(@associations, Params.snapshot(record), fn key, acc ->
      case Map.get(record, key) do
        nil -> acc
        %Ecto.Association.NotLoaded{} -> acc
        value -> Map.put(acc, to_string(key), snapshot(value))
      end
    end)
  end

  defp snapshot(list) when is_list(list), do: Enum.map(list, &snapshot/1)
  defp snapshot(value), do: value
end
