defmodule Brando.Migration.LegacyMediaRepair do
  @moduledoc """
  Puts back the media that brando_133 left out of converted refs, from the
  Villain JSON the site still has.

  Until brando_133 made images of legacy picture and gallery data that no
  live `images` row matched, it linked a picture ref to an image by `path`
  only, among rows not in the trash, and left a picture without one empty;
  a gallery lost the images it found no row for. 0.53 showed them all from
  the ref's own data. Earlier versions of brando_133 also lost embeds saved
  with only a remote id.

  `run/2` takes the media findings of `Brando.Migration.LegacyConversion.check/1`,
  which pairs each entry's Villain blocks with its converted ones, and for
  each:

    * a picture ref without an image is linked to the live image its legacy
      `sizes` or `path` name (as brando_133 matches them now), or to a new
      row made from the legacy data;
    * a gallery ref gets the images its gallery lacks, in their legacy
      places, each found or made the same way, and a gallery when it has
      none. A gallery whose images are not in the legacy order any more
      was edited since, and is skipped;
    * a video ref without a video is linked to the video with its legacy
      source URL, or to a new one made from the legacy data.

  A ref in a module block whose module is not the one Villain had there is
  skipped: the pairing by position no longer holds. A second run finds
  nothing left to do.
  """

  alias Brando.Migration.LegacyConversion

  @type action ::
          {:link_image, integer(), String.t()}
          | {:make_image, String.t()}
          | {:link_video, integer(), String.t()}
          | {:make_video, String.t()}
          | {:gallery, %{gallery_id: integer() | nil, add: [image_action()]}}
          | {:skip, String.t()}
  @type image_action :: {:link_image, integer(), String.t()} | {:make_image, String.t()}
  @type result :: %{
          schema: String.t(),
          sources: [map()],
          dropped: [map()],
          repairs: [{LegacyConversion.finding(), action()}]
        }

  @doc """
  Plans the repairs in `schema` and, unless `dry_run: true`, makes them in
  one transaction. Returns what was (or would be) done for each finding.
  """
  @spec run(String.t(), keyword()) :: {:ok, result()} | {:error, String.t()}
  def run(schema \\ "public", opts \\ []) do
    with {:ok, report} <- LegacyConversion.check(schema) do
      findings = Enum.filter(report.findings, & &1.repair)
      repairs = plan(schema, findings)
      unless Keyword.get(opts, :dry_run, false), do: apply_repairs(schema, findings, repairs)
      {:ok, %{schema: schema, sources: report.sources, dropped: report.dropped, repairs: repairs}}
    end
  end

  defp apply_repairs(schema, findings, repairs) do
    if Enum.any?(repairs, &(not match?({_, {:skip, _}}, &1))) do
      Brando.repo().transaction(fn -> Enum.each(findings, &repair(schema, &1)) end)
    end
  end

  @doc "What a repair does, as the end of a finding's line."
  @spec describe(action()) :: String.t()
  def describe({:link_image, id, path}), do: "links image ##{id} (#{path})"
  def describe({:make_image, path}), do: "makes an image of #{path} from the legacy data and links it"
  def describe({:link_video, id, url}), do: "links video ##{id} (#{url})"
  def describe({:make_video, url}), do: "makes a video of #{url} from the legacy data and links it"
  def describe({:skip, reason}), do: "skipped: #{reason}"

  def describe({:gallery, %{gallery_id: gallery_id, add: add}}) do
    made = Enum.count(add, &match?({:make_image, _}, &1))
    images = if length(add) == 1, do: "1 image", else: "#{length(add)} images"
    gallery = if gallery_id, do: "gallery ##{gallery_id}", else: "a new gallery"
    made = if made > 0, do: " (#{made} made from the legacy data)", else: ""
    "adds #{images} to #{gallery}#{made}"
  end

  @doc "How many images and videos the repairs make, each legacy path or URL once."
  @spec made([{LegacyConversion.finding(), action()}]) :: %{images: non_neg_integer(), videos: non_neg_integer()}
  def made(repairs) do
    actions =
      Enum.flat_map(repairs, fn
        {_, {:gallery, %{add: add}}} -> add
        {_, action} -> [action]
      end)

    %{
      images: actions |> Enum.flat_map(&List.wrap(made_path(&1))) |> Enum.uniq() |> length(),
      videos:
        actions
        |> Enum.flat_map(fn
          {:make_video, url} -> [url]
          _ -> []
        end)
        |> Enum.uniq()
        |> length()
    }
  end

  defp made_path({:make_image, path}), do: path
  defp made_path(_action), do: nil

  ## Planning

  defp plan(schema, findings) do
    Enum.map(findings, fn finding -> {finding, plan_one(schema, finding.repair)} end)
  end

  defp plan_one(_schema, {:unpaired, reason}), do: {:skip, reason}

  defp plan_one(schema, {:picture, _ref_id, data}), do: image_target(schema, data)

  defp plan_one(schema, {:video, _ref_id, data}) do
    url = video_source(data)

    case find_video(schema, url) do
      nil -> {:make_video, url}
      id -> {:link_video, id, url}
    end
  end

  defp plan_one(schema, {:gallery, _ref_id, gallery_id, images}) do
    case placements(schema, gallery_id, images) do
      {:ok, %{add: add}} -> {:gallery, %{gallery_id: gallery_id, add: Enum.map(add, &elem(&1, 1))}}
      {:error, reason} -> {:skip, reason}
    end
  end

  defp image_target(schema, data) do
    case find_image(schema, data) do
      {id, path} -> {:link_image, id, path}
      nil -> image_to_make(data)
    end
  end

  defp image_to_make(data) do
    case canonical_path(LegacyConversion.legacy_path(data)) do
      nil -> {:skip, "the legacy data has no path to make an image of"}
      path -> {:make_image, path}
    end
  end

  # Where each legacy image goes: the gallery's objects must be legacy
  # images it still has, in their legacy order (what brando_133 linked), and
  # the others are added at their legacy places. Returns the objects kept
  # and the images to add, each with its legacy index.
  defp placements(schema, gallery_id, images) do
    targets = Enum.map(images, &image_target(schema, &1))

    current =
      if gallery_id,
        do:
          rows(
            "SELECT id, image_id FROM #{name(schema, "galleries_gallery_objects")} WHERE gallery_id = $1 ORDER BY sequence, id",
            [gallery_id]
          ),
        else: []

    {left, kept, add} =
      targets
      |> Enum.with_index()
      |> Enum.reduce({current, [], []}, fn
        {{:link_image, image_id, _}, index}, {[[object_id, image_id] | rest], kept, add} ->
          {rest, [{object_id, index} | kept], add}

        {target, index}, {rest, kept, add} ->
          {rest, kept, [{index, target} | add]}
      end)

    cond do
      left != [] ->
        {:error, "its gallery was edited since the conversion"}

      Enum.any?(add, &match?({_, {:skip, _}}, &1)) ->
        {:error, "a legacy image matches no row and has no path to make one of"}

      true ->
        {:ok, %{kept: Enum.reverse(kept), add: Enum.reverse(add)}}
    end
  end

  ## Repairing

  defp repair(schema, %{repair: {:picture, ref_id, data}}) do
    case find_or_make(schema, ref_id, data) do
      {id, _path} -> query!("UPDATE #{name(schema, "content_refs")} SET image_id = $1 WHERE id = $2", [id, ref_id])
      nil -> :skip
    end
  end

  defp repair(schema, %{repair: {:video, ref_id, data}}) do
    id = find_video(schema, video_source(data)) || make_video(schema, ref_id, data)
    query!("UPDATE #{name(schema, "content_refs")} SET video_id = $1 WHERE id = $2", [id, ref_id])
  end

  defp repair(schema, %{repair: {:gallery, ref_id, gallery_id, images}}) do
    with {:ok, %{kept: kept, add: add}} <- placements(schema, gallery_id, images) do
      gallery_id = gallery_id || make_gallery(schema, ref_id)
      creator_id = creator_id(schema, ref_id) || 1

      added =
        for {index, _target} <- add do
          data = Enum.at(images, index)
          {image_id, _path} = find_or_make(schema, ref_id, data)

          [[object_id]] =
            rows(
              """
              INSERT INTO #{name(schema, "galleries_gallery_objects")}
                (gallery_id, image_id, sequence, creator_id, config, inserted_at, updated_at)
              VALUES ($1, $2, $3, $4, $5, now(), now()) RETURNING id
              """,
              [gallery_id, image_id, index, creator_id, object_config(data)]
            )

          {object_id, index}
        end

      (kept ++ added)
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.with_index()
      |> Enum.each(fn {{object_id, _index}, sequence} ->
        query!("UPDATE #{name(schema, "galleries_gallery_objects")} SET sequence = $1 WHERE id = $2", [
          sequence,
          object_id
        ])
      end)
    end
  end

  defp repair(_schema, _finding), do: :skip

  defp find_or_make(schema, ref_id, data), do: find_image(schema, data) || make_image(schema, ref_id, data)

  defp object_config(data) do
    for key <- ~w(title alt credits), is_binary(data[key]) and data[key] != "", into: %{}, do: {key, data[key]}
  end

  defp make_gallery(schema, ref_id) do
    [[id]] =
      rows(
        """
        INSERT INTO #{name(schema, "galleries")} (config_target, creator_id, inserted_at, updated_at)
        VALUES ('default', $1, now(), now()) RETURNING id
        """,
        [creator_id(schema, ref_id) || 1]
      )

    query!("UPDATE #{name(schema, "content_refs")} SET gallery_id = $1 WHERE id = $2", [id, ref_id])
    id
  end

  # As brando_133 makes it: the legacy path and sizes without the media
  # prefix, dimensions, formats (from the extension when the data has none),
  # dominant color and focal point
  defp make_image(schema, ref_id, data) do
    case canonical_path(LegacyConversion.legacy_path(data)) do
      nil ->
        nil

      path ->
        [[id]] =
          rows(
            """
            INSERT INTO #{name(schema, "images")} (
              path, sizes, width, height, formats, dominant_color, focal, cdn,
              config_target, status, creator_id, inserted_at, updated_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'default', 'processed', $9, now(), now())
            RETURNING id
            """,
            [
              path,
              sizes(data["sizes"]),
              integer(data["width"]),
              integer(data["height"]),
              formats(data["formats"], path),
              data["dominant_color"],
              if(is_map(data["focal"]), do: data["focal"], else: %{"x" => 50, "y" => 50}),
              data["cdn"] == true,
              creator_id(schema, ref_id)
            ]
          )

        {id, path}
    end
  end

  defp make_video(schema, ref_id, data) do
    source = data["source"]

    type =
      case source do
        "youtube" -> "youtube"
        "vimeo" -> "vimeo"
        _ -> "external_file"
      end

    remote_id =
      if source in ["vimeo", "youtube"] and is_binary(data["remote_id"]),
        do: data["remote_id"] |> String.split("?") |> hd()

    [[id]] =
      rows(
        """
        INSERT INTO #{name(schema, "videos")} (
          source_url, type, title, caption, aspect_ratio, width, height, remote_id,
          config_target, creator_id, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, $3, $4, $5, $6, $7, 'default', $8, now(), now())
        RETURNING id
        """,
        [
          video_source(data),
          type,
          data["title"],
          data["aspect_ratio"],
          integer(data["width"]),
          integer(data["height"]),
          remote_id,
          creator_id(schema, ref_id)
        ]
      )

    id
  end

  ## Matching, as brando_133 does

  # The live image the legacy `sizes` name, then the one with the legacy
  # `path`. A soft-deleted row is no match: emptying the trash deletes it.
  defp find_image(schema, data) do
    by_size =
      case first_size(data) do
        nil ->
          []

        size ->
          rows(
            """
            SELECT id, path FROM #{name(schema, "images")}
            WHERE deleted_at IS NULL AND regexp_replace(path, '\\.[^.]+$', '') = ANY($1)
            ORDER BY id LIMIT 1
            """,
            [size_candidates(size)]
          )
      end

    by_path = fn ->
      case LegacyConversion.legacy_path(data) do
        nil ->
          []

        path ->
          rows(
            "SELECT id, path FROM #{name(schema, "images")} WHERE deleted_at IS NULL AND path = ANY($1) ORDER BY id LIMIT 1",
            [path_variants(path)]
          )
      end
    end

    case by_size do
      [[id, path]] ->
        {id, path}

      [] ->
        case by_path.() do
          [[id, path]] -> {id, path}
          [] -> nil
        end
    end
  end

  defp find_video(schema, url) do
    case rows(
           "SELECT id FROM #{name(schema, "videos")} WHERE source_url = $1 AND deleted_at IS NULL ORDER BY id LIMIT 1",
           [url]
         ) do
      [[id]] -> id
      [] -> nil
    end
  end

  defp first_size(%{"sizes" => %{} = sizes}) do
    sizes |> Enum.sort() |> Enum.find_value(fn {_key, value} -> if is_binary(value) and value != "", do: value end)
  end

  defp first_size(_data), do: nil

  defp size_candidates(size) do
    size
    |> path_variants()
    |> Enum.map(&(&1 |> String.replace(~r{/[^/]+/([^/]+)$}, "/\\1") |> String.replace(~r/\.[^.]+$/, "")))
  end

  defp path_variants(path) do
    stripped =
      for prefix <- media_prefixes(), String.starts_with?(path, prefix), do: String.replace_prefix(path, prefix, "")

    Enum.uniq([path | stripped] ++ [String.trim_leading(path, "/")])
  end

  defp canonical_path(nil), do: nil

  defp canonical_path(path) do
    stripped =
      case Enum.find(media_prefixes(), &String.starts_with?(path, &1)) do
        nil -> String.trim_leading(path, "/")
        prefix -> String.replace_prefix(path, prefix, "")
      end

    case String.trim(stripped) do
      "" -> nil
      path -> path
    end
  end

  defp media_prefixes do
    configured =
      case Brando.config(:media_url) do
        url when is_binary(url) -> URI.parse(url).path
        _ -> nil
      end

    [configured, "/media"]
    |> Enum.reject(&(&1 in [nil, "", "/"]))
    |> Enum.map(&(String.trim_trailing(&1, "/") <> "/"))
    |> Enum.uniq()
  end

  defp sizes(%{} = sizes) do
    Map.new(sizes, fn {key, value} -> {key, if(is_binary(value), do: canonical_path(value), else: value)} end)
  end

  defp sizes(_sizes), do: nil

  defp formats([_ | _] = formats, _path), do: Enum.map(formats, &to_string/1)

  defp formats(_formats, path) do
    case path |> Path.extname() |> String.trim_leading(".") |> String.downcase() do
      ext when ext in ~w(jpeg jpg) -> ["jpg"]
      ext when ext in ~w(png gif webp avif svg) -> [ext]
      _ -> ["original"]
    end
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer(_value), do: nil

  # The source brando_133 gives a legacy video: its url, or for an embed with
  # only a remote id, the provider URL built from it
  defp video_source(data) do
    remote_id = if is_binary(data["remote_id"]), do: data["remote_id"] |> String.split("?") |> hd()

    case {data["source"], data["url"]} do
      {"vimeo", nil} when is_binary(remote_id) -> "https://vimeo.com/" <> remote_id
      {"youtube", nil} when is_binary(remote_id) -> "https://www.youtube.com/watch?v=" <> remote_id
      _ -> LegacyConversion.legacy_video(data)
    end
  end

  defp creator_id(schema, ref_id) do
    case rows(
           """
           SELECT b.creator_id FROM #{name(schema, "content_refs")} r
           LEFT JOIN #{name(schema, "content_blocks")} b ON b.id = r.block_id WHERE r.id = $1
           """,
           [ref_id]
         ) do
      [[id]] -> id
      [] -> nil
    end
  end

  ## SQL

  defp rows(sql, params), do: query!(sql, params).rows

  defp query!(sql, params), do: Brando.repo().query!(sql, params, log: false)

  defp name(schema, table), do: quote_name(schema) <> "." <> quote_name(table)

  defp quote_name(name), do: ~s(") <> String.replace(name, ~s("), ~s("")) <> ~s(")
end
