defmodule BrandoAdmin.Components.Form.DraftPreview.References do
  @moduledoc false
  use Gettext, backend: Brando.Gettext
  import Ecto.Query, only: [from: 2]
  alias Brando.Repo

  defstruct [:kind, :id, :title, :detail, :thumbnail]

  @schemas %{
    image: Brando.Images.Image,
    video: Brando.Videos.Video,
    file: Brando.Files.File,
    entry: Brando.Content.Identifier
  }
  @fields %{
    "image_id" => :image,
    "thumbnail_id" => :image,
    "video_id" => :video,
    "file_id" => :file,
    "identifier_id" => :entry
  }

  # Resolve both sides together: one query per kind, within the current tenant.
  # The recovery payload itself is never changed, including missing references.
  def prepare(saved, recovered, opts) do
    schema = opts[:schema]
    fields = if schema, do: asset_fields(schema), else: @fields
    index = Keyword.get_lazy(opts, :references, fn -> load([saved, recovered], fields) end)
    {decorate(saved, fields, index), decorate(recovered, fields, index)}
  end

  defp asset_fields(schema) do
    schema
    |> Brando.Blueprint.Assets.__assets__()
    |> Enum.filter(&Map.has_key?(@schemas, &1.type))
    |> Map.new(&{to_string(&1.name) <> "_id", &1.type})
    |> then(&Map.merge(@fields, &1))
  end

  defp load(payloads, fields) do
    payloads
    |> references(fields)
    |> Enum.uniq()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {kind, ids} ->
      schema = Map.fetch!(@schemas, kind)
      query = from record in schema, where: record.id in ^ids
      records = Repo.all(query)
      records = if kind == :video, do: Repo.preload(records, [:file, :thumbnail]), else: records
      Enum.map(records, &{{kind, &1.id}, preview(kind, &1)})
    end)
    |> Map.new()
  end

  defp references(%{"object_id" => value, "object_type" => type} = map, fields)
       when type in ["image", "video"] do
    kind = if type == "image", do: :image, else: :video
    reference = if id(value), do: [{kind, id(value)}], else: []
    reference ++ references(Map.drop(map, ["object_id", "object_type"]), fields)
  end

  defp references(map, fields) when is_map(map) do
    Enum.flat_map(map, fn {key, value} ->
      case {fields[key], id(value)} do
        {kind, id} when not is_nil(kind) and not is_nil(id) -> [{kind, id}]
        _ -> references(value, fields)
      end
    end)
  end

  defp references(list, fields) when is_list(list), do: Enum.flat_map(list, &references(&1, fields))
  defp references(_, _), do: []

  defp decorate(%{"object_id" => value, "object_type" => type} = map, fields, index)
       when type in ["image", "video"] do
    kind = if type == "image", do: :image, else: :video
    rest = decorate(Map.drop(map, ["object_id", "object_type"]), fields, index)
    map = Map.merge(rest, Map.take(map, ["object_id", "object_type"]))
    if id(value), do: Map.put(map, "_gallery_preview", lookup(index, kind, id(value))), else: map
  end

  defp decorate(map, fields, index) when is_map(map) do
    map
    |> Map.reject(fn {key, _} -> fields[key <> "_id"] && id(map[key <> "_id"]) end)
    |> Map.new(fn {key, value} ->
      case {fields[key], id(value)} do
        {kind, id} when not is_nil(kind) and not is_nil(id) ->
          preview = lookup(index, kind, id)

          {String.trim_trailing(key, "_id"), preview}

        _ ->
          {key, decorate(value, fields, index)}
      end
    end)
  end

  defp decorate(list, fields, index) when is_list(list), do: Enum.map(list, &decorate(&1, fields, index))
  defp decorate(value, _, _), do: value

  defp lookup(index, kind, id) do
    Map.get(index, {kind, id}, %__MODULE__{
      kind: kind,
      id: id,
      title: gettext("Unavailable %{type}", type: kind_label(kind)),
      detail: gettext("Reference #%{id}", id: id)
    })
  end

  defp id(id) when is_integer(id) and id > 0, do: id

  defp id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp id(_), do: nil

  defp preview(:image, image) do
    %__MODULE__{
      kind: :image,
      id: image.id,
      title: if(present(image.path), do: Path.basename(image.path), else: present(image.title) || kind_label(:image)),
      detail: details([kind_label(:image), dimensions(image)]),
      thumbnail: image_url(image)
    }
  end

  defp preview(:file, file) do
    %__MODULE__{
      kind: :file,
      id: file.id,
      title: file.filename,
      detail: details([kind_label(:file), file.mime_type, file.filesize && Brando.Utils.human_size(file.filesize)])
    }
  end

  defp preview(:video, video) do
    filename = (video.file && video.file.filename) || source_name(video.source_url)
    title = present(video.title) || filename || present(video.remote_id) || kind_label(:video)

    %__MODULE__{
      kind: :video,
      id: video.id,
      title: title,
      detail: details([kind_label(:video), filename, dimensions(video), video.duration]),
      thumbnail: video.thumbnail && image_url(video.thumbnail)
    }
  end

  defp preview(:entry, entry) do
    %__MODULE__{
      kind: :entry,
      id: entry.id,
      title: present(entry.title) || gettext("Untitled entry"),
      detail: details([kind_label(:entry), entry.language && to_string(entry.language)]),
      thumbnail: present(entry.cover)
    }
  end

  defp source_name(value) when value in [nil, ""], do: nil

  defp source_name(value) do
    uri = URI.parse(value)
    if present(uri.path), do: Path.basename(uri.path), else: uri.host
  end

  defp image_url(%{path: path}) when path in [nil, ""], do: nil

  defp image_url(image) do
    Brando.Utils.img_url(image, :original, prefix: Brando.Utils.media_url())
  end

  defp dimensions(%{width: w, height: h}) when is_number(w) and is_number(h), do: "#{w} × #{h}"
  defp dimensions(_), do: nil
  defp details(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")
  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  def kind_label(:image), do: gettext("Image")
  def kind_label(:video), do: gettext("Video")
  def kind_label(:file), do: gettext("File")
  def kind_label(:entry), do: gettext("Related entry")
end
