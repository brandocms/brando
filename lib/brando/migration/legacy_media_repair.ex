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
      data names, as brando_133 matches it now, or to a row made from that
      data;
    * a gallery ref gets the images its gallery lacks, in their legacy
      places, found or made the same way, and a gallery when it has none;
    * a video ref without a video is linked to the video with its legacy
      source URL, or to a video made from the legacy data.

  It runs weeks after the conversion, against content editors have worked
  on since, so it writes only where it can tell the media was lost in the
  conversion and not removed by an editor. It skips, with the reason:

    * every ref of an entry whose blocks no longer line up with its Villain
      list at any level (`LegacyConversion` sets `:unpaired`), or whose ref
      is of another type now;
    * every ref of an entry edited since the conversion (its `edited_at`,
      which only an editor's save moves), and a ref whose block, or a
      gallery whose objects, were edited or added since;
    * a ref whose image or video would have to be made, once the conversion
      is more than 30 days old: the trash is emptied after 30 days, which
      nils the refs to what it deletes and leaves no trace (the activity log
      does not record media), so an image an editor deleted since can't be
      told from one the conversion lost; and one whose path names an image
      put in the trash since;
    * a picture whose `path` and `sizes` name different images when the one
      `sizes` names, which 0.53 displayed, has no row, or several.

  The conversion's time is when brando_133 ran, or brando_175 when that ran
  later: brando_175 starts recording `edited_at`, from `updated_at` for rows
  that predate it. Both are read from `schema_migrations`, through the copies
  in the migrations directory; `converted_at:` gives the time instead. When
  it cannot be told, nothing is written.

  Writing locks each ref, and writes only while it is still empty, so media
  an editor picks while the repair runs stays. A second run finds nothing to
  do.
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
          converted_at: NaiveDateTime.t() | nil,
          repairs: [{LegacyConversion.finding(), action()}]
        }

  # brando_133 and brando_175 running further apart than this may leave
  # edits between them without an `edited_at` after the conversion
  @window 3600

  # `Brando.SoftDelete.Query.clean_up_soft_deletions/0` deletes what has been
  # in the trash this long
  @purge_days 30

  @doc """
  Plans the repairs in `schema` and, unless `dry_run: true`, makes them in
  one transaction. Returns what was (or would be) done for each finding.

  `converted_at:` (a `NaiveDateTime` in UTC) is the time after which a
  change counts as an editor's; by default it is read from
  `schema_migrations`.
  """
  @spec run(String.t(), keyword()) :: {:ok, result()} | {:error, String.t()}
  def run(schema \\ "public", opts \\ []) do
    with {:ok, report} <- LegacyConversion.check(schema) do
      findings = Enum.filter(report.findings, & &1.repair)
      context = context(schema, findings, opts)
      repairs = Enum.map(findings, &{&1, plan(context, &1)})

      repairs =
        if Keyword.get(opts, :dry_run, false) or Enum.all?(repairs, &skip?/1),
          do: repairs,
          else: write(context, repairs, opts)

      {:ok,
       %{
         schema: schema,
         sources: report.sources,
         dropped: report.dropped,
         converted_at: ok_value(context.converted_at),
         repairs: repairs
       }}
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
      images: actions |> Enum.flat_map(&made_value(&1, :make_image)) |> Enum.uniq() |> length(),
      videos: actions |> Enum.flat_map(&made_value(&1, :make_video)) |> Enum.uniq() |> length()
    }
  end

  defp made_value({kind, value}, kind), do: [value]
  defp made_value(_action, _kind), do: []

  defp ok_value({:ok, value}), do: value
  defp ok_value(_error), do: nil

  defp skip?({_finding, {:skip, _}}), do: true
  defp skip?(_repair), do: false

  ## Context

  defp context(schema, findings, opts) do
    converted_at =
      case Keyword.get(opts, :converted_at) do
        %NaiveDateTime{} = time -> {:ok, time}
        nil -> conversion_time()
      end

    # Rows the migrations wrote got the database's local time from `NOW()`;
    # the application writes UTC. Later than this in local time is later
    # than the conversion whatever wrote it.
    [[offset]] = rows("SELECT extract(epoch FROM now()::timestamp - (now() AT TIME ZONE 'utc'))::integer", [])
    columns = columns(schema)

    {local_cutoff, entries} =
      case converted_at do
        {:ok, time} -> {NaiveDateTime.add(time, max(offset, 0)), entry_edits(schema, findings, time, columns)}
        {:error, _} -> {nil, %{}}
      end

    %{
      schema: schema,
      converted_at: converted_at,
      local_cutoff: local_cutoff,
      columns: columns,
      entries: entries,
      deletions: deletions(converted_at),
      images: image_index(schema)
    }
  end

  # When brando_133, and brando_175 after it, ran, from the copies of them in
  # the migrations directory and their rows in `schema_migrations`
  defp conversion_time do
    times =
      Map.new(["brando_133_transfer_ref_media_data", "brando_175_add_updated_by"], fn name ->
        {name, migration_time(name)}
      end)

    case {times["brando_133_transfer_ref_media_data"], times["brando_175_add_updated_by"]} do
      {nil, _} ->
        {:error,
         "can't tell when brando_133 ran: no copy of it with a time in schema_migrations. Give the time with --converted-at"}

      {_t133, nil} ->
        {:error, "brando_175, which records edits, has not run, so edits since the conversion can't be told"}

      {t133, t175} ->
        cond do
          NaiveDateTime.compare(t175, t133) == :lt ->
            {:ok, t133}

          NaiveDateTime.diff(t175, t133) > @window ->
            {:error,
             "brando_133 ran #{t133} and brando_175, which starts recording edits, #{t175}: " <>
               "edits between them can't be told. Give the time after which changes are editors' with --converted-at"}

          true ->
            {:ok, t175}
        end
    end
  end

  defp migration_time(name) do
    versions =
      migrations_paths()
      |> List.wrap()
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*_#{name}.exs")))
      |> Enum.flat_map(fn file ->
        case Integer.parse(Path.basename(file)) do
          {version, "_" <> _} -> [version]
          _ -> []
        end
      end)

    if versions == [] do
      nil
    else
      source = Brando.repo().config()[:migration_source] || "schema_migrations"

      case rows("SELECT max(inserted_at) FROM #{name("public", source)} WHERE version = ANY($1)", [versions]) do
        [[%NaiveDateTime{} = time]] -> time
        _ -> nil
      end
    end
  end

  defp migrations_paths,
    do: Brando.config(:public_migrations_path) || Ecto.Migrator.migrations_path(Brando.repo())

  defp columns(schema) do
    "SELECT table_name FROM information_schema.columns WHERE table_schema = $1 AND column_name = 'edited_at'"
    |> rows([schema])
    |> MapSet.new(&hd/1)
  end

  # Each entry with findings: nil, or why its refs can't be repaired
  defp entry_edits(schema, findings, converted_at, tables) do
    findings
    |> Enum.uniq_by(&{&1.table, &1.entry_id})
    |> Map.new(fn %{table: table, entry_id: id} ->
      reason =
        if MapSet.member?(tables, table),
          do: entry_edited(schema, table, id, converted_at),
          else: "#{table} has no edited_at, so edits since the conversion can't be told"

      {{table, id}, reason}
    end)
  end

  defp entry_edited(schema, table, id, converted_at) do
    case rows("SELECT edited_at FROM #{name(schema, table)} WHERE id = $1", [id]) do
      [[%NaiveDateTime{} = edited]] -> if later?(edited, converted_at), do: "edited #{edited} UTC, after the conversion"
      _ -> nil
    end
  end

  # Whether an image or video linked by the conversion may have been deleted
  # for good since, leaving its ref empty without a trace: the activity log
  # does not record media, and the trash is emptied of what has been in it
  # for 30 days, which nils the refs to it. Before that a trashed
  # row is still there to see.
  defp deletions({:error, _} = error), do: error

  defp deletions({:ok, converted_at}) do
    if NaiveDateTime.diff(NaiveDateTime.utc_now(), converted_at) >= @purge_days * 86_400,
      do:
        {:error,
         "the conversion is more than #{@purge_days} days old, and the trash is emptied after #{@purge_days} days: " <>
           "media an editor deleted since may be gone without a trace, and this could bring it back"},
      else: :ok
  end

  # The live images, by path and by extensionless path
  defp image_index(schema) do
    "SELECT id, path FROM #{name(schema, "images")} WHERE deleted_at IS NULL AND path IS NOT NULL ORDER BY id"
    |> rows([])
    |> Enum.map(&List.to_tuple/1)
    |> index_images()
  end

  @doc """
  The live images, `[{id, path}]` in id order, as `resolve_image/2` reads
  them.
  """
  @spec index_images([{integer(), String.t()}]) :: map()
  def index_images(images) do
    Enum.reduce(images, %{by_path: %{}, by_stem: %{}, paths: %{}}, fn {id, path}, index ->
      index_image(index, id, path)
    end)
  end

  defp index_image(index, id, path) do
    %{
      by_path: Map.put_new(index.by_path, path, id),
      by_stem: Map.update(index.by_stem, stem(path), [id], &(&1 ++ [id])),
      paths: Map.put(index.paths, id, path)
    }
  end

  ## Planning

  defp plan(%{converted_at: {:error, reason}}, _finding), do: {:skip, reason}
  defp plan(_context, %{repair: {:unpaired, reason}}), do: {:skip, reason}

  defp plan(context, finding) do
    with nil <- Map.get(context.entries, {finding.table, finding.entry_id}),
         nil <- ref_edited(context, ref_id(finding.repair)) do
      plan_one(context, finding.repair)
    else
      reason -> {:skip, reason}
    end
  end

  defp ref_id({_kind, ref_id, _data}), do: ref_id
  defp ref_id({:gallery, ref_id, _gallery_id, _images}), do: ref_id

  # The ref's block, or the ref itself where it records edits, changed since
  defp ref_edited(context, ref_id) do
    checks =
      [{"content_blocks", "b"}, {"content_refs", "r"}]
      |> Enum.filter(fn {table, _} -> MapSet.member?(context.columns, table) end)
      |> Enum.map(fn {_, alias} -> "#{alias}.edited_at > $2" end)

    if checks == [] do
      nil
    else
      sql = """
      SELECT 1 FROM #{name(context.schema, "content_refs")} r
      LEFT JOIN #{name(context.schema, "content_blocks")} b ON b.id = r.block_id
      WHERE r.id = $1 AND (#{Enum.join(checks, " OR ")})
      """

      if query!(sql, [ref_id, context.local_cutoff]).rows != [], do: "its block was edited since the conversion"
    end
  end

  defp plan_one(context, {:picture, _ref_id, data}), do: image_target(context, context.images, data)

  defp plan_one(context, {:video, _ref_id, data}) do
    url = video_source(data)

    case find_video(context.schema, url) do
      nil -> doubt_or(deleted_since(context), {:make_video, url})
      id -> {:link_video, id, url}
    end
  end

  defp plan_one(context, {:gallery, _ref_id, gallery_id, images}) do
    case placements(context, context.images, gallery_id, images) do
      {:ok, %{add: add}} -> {:gallery, %{gallery_id: gallery_id, add: Enum.map(add, &elem(&1, 1))}}
      {:error, reason} -> {:skip, reason}
    end
  end

  defp image_target(context, index, data) do
    case resolve_image(index, data) do
      {:make_image, path} = make -> doubt_or(make_doubt(context, path), make)
      other -> other
    end
  end

  defp doubt_or(nil, action), do: action
  defp doubt_or(reason, _action), do: {:skip, reason}

  # Why an image made for `path` may bring back one an editor removed
  defp make_doubt(context, path) do
    trashed =
      query!(
        "SELECT max(deleted_at) FROM #{name(context.schema, "images")} WHERE path = $1 AND deleted_at IS NOT NULL",
        [path]
      ).rows

    case trashed do
      [[%NaiveDateTime{} = at]] ->
        if later?(at, elem(context.converted_at, 1)), do: "its image went to the trash #{at} UTC"

      _ ->
        nil
    end || deleted_since(context)
  end

  defp deleted_since(%{deletions: {:error, reason}}), do: reason
  defp deleted_since(%{deletions: :ok}), do: nil

  @doc """
  The live image in `index` (from `index_images/1`) that a legacy picture's
  data shows, by the same rules as brando_133: when its `path` and `sizes`
  name one image, the row with that exact path, or one to make; when they
  name different images, the one the sizes name (which 0.53 displayed), if
  exactly one row has its stem.
  """
  @spec resolve_image(map(), map()) :: image_action() | {:skip, String.t()}
  def resolve_image(index, data) do
    raw = LegacyConversion.legacy_path(data)
    path = canonical_path(raw)
    size_stems = data |> first_size() |> canonical_path() |> size_stems()

    if path != nil and (size_stems == [] or stem(path) in size_stems),
      do: by_path(index, [raw, path], path),
      else: by_size(index, size_stems, path)
  end

  # A size file is `<dir>/<size>/<name>`, or the file itself for an SVG
  defp size_stems(nil), do: []
  defp size_stems(size), do: Enum.uniq([stem(size), stem(String.replace(size, ~r{/[^/]+/([^/]+)$}, "/\\1"))])

  defp by_path(index, candidates, path) do
    case Enum.find_value(candidates, &Map.get(index.by_path, &1)) do
      nil -> {:make_image, path}
      id -> {:link_image, id, index.paths[id]}
    end
  end

  defp by_size(index, size_stems, path) do
    case size_stems |> Enum.flat_map(&Map.get(index.by_stem, &1, [])) |> Enum.uniq() do
      [id] -> {:link_image, id, index.paths[id]}
      [] when path == nil -> {:skip, "the legacy data has no path to make an image of"}
      [] -> {:skip, "its path names #{path} and its sizes another image, which has no row"}
      _several -> {:skip, "several images have the name its sizes give"}
    end
  end

  # Where each legacy image goes: the gallery's objects must be legacy
  # images it still has, in their legacy order (what brando_133 linked), and
  # the others are added at their legacy places. Returns the objects kept
  # and the images to add, each with its legacy index.
  defp placements(context, index, gallery_id, images) do
    case gallery_edited(context, gallery_id) do
      nil -> place(context, index, gallery_id, images)
      reason -> {:error, reason}
    end
  end

  defp place(context, index, gallery_id, images) do
    targets = Enum.map(images, &image_target(context, index, &1))

    current =
      if gallery_id,
        do:
          rows(
            "SELECT id, image_id FROM #{name(context.schema, "galleries_gallery_objects")} WHERE gallery_id = $1 ORDER BY sequence, id",
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
        {:error, "its gallery is not the legacy images in their order now"}

      skip = Enum.find_value(add, fn {_, target} -> match?({:skip, _}, target) and elem(target, 1) end) ->
        {:error, "a legacy image can't be placed: #{skip}"}

      true ->
        {:ok, %{kept: Enum.reverse(kept), add: Enum.reverse(add)}}
    end
  end

  defp gallery_edited(_context, nil), do: nil

  defp gallery_edited(context, gallery_id) do
    edited = if MapSet.member?(context.columns, "galleries_gallery_objects"), do: " OR edited_at > $2", else: ""

    sql =
      "SELECT 1 FROM #{name(context.schema, "galleries_gallery_objects")} WHERE gallery_id = $1 AND (inserted_at > $2#{edited})"

    if query!(sql, [gallery_id, context.local_cutoff]).rows != [], do: "its gallery was edited since the conversion"
  end

  ## Writing

  # One transaction. Each ref is locked and written only while it is still
  # empty, so media an editor picks during the run stays; what changed since
  # planning is skipped instead.
  defp write(context, repairs, opts) do
    if hook = Keyword.get(opts, :before_write), do: hook.()

    {:ok, repairs} =
      Brando.repo().transaction(fn ->
        repairs
        |> Enum.map_reduce(context.images, &write_one(context, &1, &2))
        |> elem(0)
      end)

    repairs
  end

  defp write_one(_context, {_finding, {:skip, _}} = skipped, index), do: {skipped, index}

  defp write_one(context, {finding, action}, index) do
    case repair(context, index, finding.repair, action) do
      {:ok, index} -> {{finding, action}, index}
      {:skip, reason} -> {{finding, {:skip, reason}}, index}
    end
  end

  defp repair(context, index, {:picture, ref_id, data}, _action) do
    with :ok <- lock_empty(context, ref_id, "image_id", "picture"),
         {:ok, image_id, index} <- find_or_make(context, index, ref_id, data) do
      update_empty(context, ref_id, "image_id", image_id)
      {:ok, index}
    end
  end

  defp repair(context, index, {:video, ref_id, data}, _action) do
    with :ok <- lock_empty(context, ref_id, "video_id", "video") do
      id = find_video(context.schema, video_source(data)) || make_video(context.schema, ref_id, data)
      update_empty(context, ref_id, "video_id", id)
      {:ok, index}
    end
  end

  defp repair(context, index, {:gallery, ref_id, gallery_id, images}, _action) do
    with :ok <- lock_gallery_ref(context, ref_id, gallery_id),
         {:ok, %{kept: kept, add: add}} <- placements(context, index, gallery_id, images) do
      gallery_id = gallery_id || make_gallery(context.schema, ref_id)
      creator_id = creator_id(context.schema, ref_id) || 1

      {added, index} =
        Enum.map_reduce(add, index, fn {position, _target}, index ->
          data = Enum.at(images, position)
          {:ok, image_id, index} = find_or_make(context, index, ref_id, data)

          [[object_id]] =
            rows(
              """
              INSERT INTO #{name(context.schema, "galleries_gallery_objects")}
                (gallery_id, image_id, sequence, creator_id, config, inserted_at, updated_at)
              VALUES ($1, $2, $3, $4, $5, now(), now()) RETURNING id
              """,
              [gallery_id, image_id, position, creator_id, object_config(data)]
            )

          {{object_id, position}, index}
        end)

      (kept ++ added)
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.with_index()
      |> Enum.each(fn {{object_id, _position}, sequence} ->
        query!("UPDATE #{name(context.schema, "galleries_gallery_objects")} SET sequence = $1 WHERE id = $2", [
          sequence,
          object_id
        ])
      end)

      {:ok, index}
    else
      {:error, reason} -> {:skip, reason}
      {:skip, _reason} = skip -> skip
    end
  end

  defp lock_empty(context, ref_id, column, type) do
    case rows(
           "SELECT #{column} IS NULL, data->>'type' FROM #{name(context.schema, "content_refs")} WHERE id = $1 FOR UPDATE",
           [ref_id]
         ) do
      [[true, ^type]] -> :ok
      [[false, _]] -> {:skip, "media was picked for it while the repair ran"}
      _ -> {:skip, "the ref changed while the repair ran"}
    end
  end

  defp lock_gallery_ref(context, ref_id, gallery_id) do
    case rows(
           "SELECT gallery_id, data->>'type' FROM #{name(context.schema, "content_refs")} WHERE id = $1 FOR UPDATE",
           [ref_id]
         ) do
      [[^gallery_id, "gallery"]] ->
        if gallery_id,
          do: rows("SELECT id FROM #{name(context.schema, "galleries")} WHERE id = $1 FOR UPDATE", [gallery_id])

        :ok

      _ ->
        {:skip, "the ref changed while the repair ran"}
    end
  end

  defp update_empty(context, ref_id, column, id) do
    query!(
      "UPDATE #{name(context.schema, "content_refs")} SET #{column} = $1 WHERE id = $2 AND #{column} IS NULL",
      [id, ref_id]
    )
  end

  defp find_or_make(context, index, ref_id, data) do
    case resolve_image(index, data) do
      {:link_image, id, _path} ->
        {:ok, id, index}

      {:make_image, path} ->
        id = make_image(context.schema, ref_id, path, data)
        {:ok, id, index_image(index, id, path)}

      {:skip, reason} ->
        {:skip, reason}
    end
  end

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

    query!("UPDATE #{name(schema, "content_refs")} SET gallery_id = $1 WHERE id = $2 AND gallery_id IS NULL", [id, ref_id])

    id
  end

  # As brando_133 makes it: the legacy path and sizes without the media
  # prefix, dimensions, formats (from the extension when the data has none),
  # dominant color and focal point
  defp make_image(schema, ref_id, path, data) do
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

    id
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

  ## Matching

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
    sizes
    |> Enum.sort()
    |> Enum.find_value(fn {_key, value} -> if is_binary(value) and String.trim(value) != "", do: value end)
  end

  defp first_size(_data), do: nil

  defp stem(path), do: String.replace(path, ~r/\.[^.]+$/, "")

  # How a legacy path is stored in `images.path`: without the media prefix
  # or a leading slash
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

  defp later?(time, converted_at), do: NaiveDateTime.compare(time, converted_at) == :gt

  ## SQL

  defp rows(sql, params), do: query!(sql, params).rows

  defp query!(sql, params), do: Brando.repo().query!(sql, params, log: false)

  defp name(schema, table), do: quote_name(schema) <> "." <> quote_name(table)

  defp quote_name(name), do: ~s(") <> String.replace(name, ~s("), ~s("")) <> ~s(")
end
