defmodule Brando.Content.Proposals.ImageReplacement do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  The `replace_image_file` proposal operation
  (`Brando.Content.Proposals.ReplaceImageFile`): library image OLD takes the
  file of library image NEW, a better copy of the same picture a connected
  tool uploaded.

  ## When the proposal is prepared, approved and applied

  Both are images the person may read, out of the trash, and not the same
  image or the same file. NEW's file passes OLD's image config (its types and
  size limit), and is an SVG only when OLD's is: an SVG has no sizes, and
  OLD's crops and focal point carry over. Nothing uses NEW yet
  (`Brando.Content.Usage.used?/2`), and no other operation of the proposal
  places it or replaces with it, since its record goes. The person may update
  both images and every entry that uses OLD (`Brando.Content.Usage.owners/3`),
  in the trash too;
  a refusal names the entries they may read and counts the others.

  The files as they were when the proposal was prepared are frozen with it
  (`snapshot/2`), and a proposal whose OLD or NEW has another file since is
  refused: another proposal replaced it first, or someone did by hand.

  ## On approval

  Inside the proposal's transaction, with both rows locked and checked again,
  OLD takes NEW's file: its path, dimensions, formats, `content_hash`,
  dominant colour, CDN flag and, until its own are made, NEW's sizes, or its
  own of a size NEW lacks. An approval while NEW's sizes are still being made
  is refused, to be tried again (`ready!/1`). It
  keeps its id, focal point, title, alt text, credits, folder, config and
  every reference. NEW's record is deleted, with its jobs that have not
  started, and OLD's sizes are queued to be made again, as for an upload. A
  run of Image sizes that was waiting to recreate NEW counts OLD's job in
  its place (`Brando.Images.SizeRun.carry_over/2`).
  Only rows change: no file is moved or written, so an approval that fails
  anywhere rolls back to OLD as it was, with its files.

  OLD's previous original and sizes are left where they are, unreferenced.
  The file browser's replacement (`Brando.Files.Replacement`) writes the new
  bytes over the old ones, so they are gone once it succeeds; an image's
  cannot be written over, since its type may differ and every environment of
  a site shares the media folder (an environment copied from this one still
  shows OLD's previous file). `Brando.Media.OrphanCleanup` removes them once
  no environment refers to them, and not before its grace period has passed
  from the replacement (`Brando.Media.OrphanCleanup.hold_image_files/1`): the
  entries that show OLD link them until they are rendered again, and a
  visitor's cached page longer. The cleanup only removes files from the media
  folder, never from a CDN. A replacement has no undo.

  It queues no renders: the entries that show OLD are rendered again when
  its new sizes are made.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.Proposals.CreateEntry
  alias Brando.Content.Proposals.ReplaceImageFile
  alias Brando.Content.Proposals.SetFields
  alias Brando.Content.Transfer.Catalog
  alias Brando.Content.Transfer.Error
  alias Brando.Content.Usage
  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Images.Intake
  alias Brando.Repo
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Uploads.ContentType

  require Logger

  @svg "image/svg+xml"
  # Proportions within 1% of each other are the same picture's
  @ratio_tolerance 0.01
  @unstarted ~w(available scheduled retryable)

  ## Prepare

  @doc """
  `op` with the two files as they are now, read as `actor`. An image that
  cannot be read is left without one; `problems/3` reports it.
  """
  @spec snapshot(ReplaceImageFile.t(), term()) :: ReplaceImageFile.t()
  def snapshot(%ReplaceImageFile{asset: {:image, old_id}, with: {:image, new_id}} = op, actor) do
    %{op | old: image_snapshot(readable(old_id, actor)), new: image_snapshot(readable(new_id, actor), :file)}
  end

  defp image_snapshot(image, read \\ nil)
  defp image_snapshot(nil, _read), do: nil

  defp image_snapshot(%Image{} = image, read) do
    file = if read == :file, do: file_facts(image), else: %{}

    %{
      "path" => image.path,
      "width" => image.width,
      "height" => image.height,
      "content_hash" => image.content_hash,
      "type" => file[:type] || type_from_path(image.path),
      "bytes" => file[:bytes],
      "sizes" => image.sizes || %{},
      "formats" => Enum.map(image.formats || [], &to_string/1),
      "cdn" => image.cdn == true
    }
  end

  defp readable(id, actor) do
    from(i in Image, where: i.id == ^id)
    |> Catalog.scoped_query(Image, actor, :read)
    |> Repo.one()
    |> then(fn
      %Image{} = image -> if Boundary.authorize(actor, :read, image) == :ok, do: image
      nil -> nil
    end)
  end

  @doc """
  The blocking problems of `op`, checked as `actor`. `operations` are the
  proposal's, to see what else it places and replaces.
  """
  @spec problems(ReplaceImageFile.t(), [struct()], term()) :: [map()]
  def problems(%ReplaceImageFile{asset: {:image, old_id}, with: {:image, new_id}} = op, operations, actor) do
    old = readable(old_id, actor)
    new = readable(new_id, actor)

    cond do
      old_id == new_id ->
        [problem(:same_image, dgettext("content_proposals", "An image cannot be replaced with itself."))]

      is_nil(old) ->
        [missing(old_id)]

      is_nil(new) ->
        [missing(new_id)]

      true ->
        with [] <- trashed(old) ++ trashed(new),
             [] <- changed(op.old, old) ++ changed(op.new, new),
             [] <- in_proposal(op, operations),
             [] <- file_problems(old, new, op.new),
             [] <- in_use(new) do
          permissions(old, new, actor)
        end
    end
  end

  defp missing(id),
    do:
      problem(
        :missing_asset,
        dgettext("content_proposals", "There is no image %{id} you may read in the media library.", id: id)
      )

  defp trashed(%Image{deleted_at: nil}), do: []

  defp trashed(%Image{id: id}),
    do: [problem(:missing_asset, dgettext("content_proposals", "Image %{id} is in the trash.", id: id))]

  # Its file is another than the one reviewed: replaced by another proposal,
  # or by hand, since this one was prepared.
  defp changed(nil, _image), do: []

  defp changed(snapshot, %Image{} = image) do
    if snapshot["path"] == image.path and snapshot["content_hash"] == image.content_hash,
      do: [],
      else: [
        problem(
          :changed_asset,
          dgettext(
            "content_proposals",
            "Image %{id} has another file than when this proposal was prepared. Prepare it again.",
            id: image.id
          )
        )
      ]
  end

  # NEW's record goes on approval, so nothing else in the proposal may place
  # it, and an image is replaced, or replaces another, once.
  defp in_proposal(%ReplaceImageFile{asset: {:image, old_id}, with: {:image, new_id}} = op, operations) do
    # By position: the same replacement twice is a duplicate of itself
    others = List.delete(operations, op)
    replacements = for %ReplaceImageFile{} = other <- others, do: other

    cond do
      Enum.any?(replacements, &(&1.asset == {:image, old_id} or &1.with == {:image, old_id})) ->
        [
          problem(
            :duplicate_replacement,
            dgettext("content_proposals", "Image %{id} is replaced in another operation of this proposal too.",
              id: old_id
            )
          )
        ]

      Enum.any?(replacements, &(&1.asset == {:image, new_id} or &1.with == {:image, new_id})) ->
        [
          problem(
            :duplicate_replacement,
            dgettext("content_proposals", "Image %{id} is used in another replacement of this proposal too.", id: new_id)
          )
        ]

      Enum.any?(others, &places?(&1, {:image, new_id})) ->
        [
          problem(
            :asset_in_use,
            dgettext(
              "content_proposals",
              "This proposal also places image %{id}, whose record goes when its file replaces image %{old}. Place image %{old} instead, or swap the references instead of replacing the file.",
              id: new_id,
              old: old_id
            )
          )
        ]

      true ->
        []
    end
  end

  defp places?(%ReplaceImageFile{}, _asset), do: false

  defp places?(op, asset) do
    op
    |> Map.from_struct()
    |> Map.values()
    |> mentions?(asset) or sets_image_id?(op, asset)
  end

  # An entry's image field set to the bare id, as `"cover_id": 87`
  defp sets_image_id?(%CreateEntry{schema: schema, fields: fields}, asset), do: image_id?(schema, fields, asset)
  defp sets_image_id?(%SetFields{target: {schema, _id}, fields: fields}, asset), do: image_id?(schema, fields, asset)
  defp sets_image_id?(_op, _asset), do: false

  defp image_id?(schema, fields, {:image, id}) when is_atom(schema) and is_map(fields) do
    image_fields =
      for %{name: name, type: :image} <- Brando.Blueprint.Assets.__assets__(schema), do: "#{name}_id"

    Enum.any?(fields, fn {key, value} -> value == id and to_string(key) in image_fields end)
  rescue
    _ -> false
  end

  defp image_id?(_schema, _fields, _asset), do: false

  defp mentions?(asset, asset), do: true
  defp mentions?(list, asset) when is_list(list), do: Enum.any?(list, &mentions?(&1, asset))
  defp mentions?(tuple, asset) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> mentions?(asset)

  defp mentions?(map, asset) when is_map(map) and not is_struct(map),
    do: map |> Map.values() |> mentions?(asset)

  defp mentions?(_value, _asset), do: false

  # The first thing about NEW's file that OLD's config does not take.
  defp file_problems(old, new, snapshot) do
    {:ok, cfg} = Images.get_config_for(old)
    facts = known_facts(snapshot) || file_facts(new)

    cond do
      old.content_hash && old.content_hash == new.content_hash ->
        [
          problem(
            :same_file,
            dgettext("content_proposals", "Image %{new} is the same file as image %{old}.", new: new.id, old: old.id)
          )
        ]

      delivery(cfg) != delivery(new) ->
        [
          problem(
            :different_delivery,
            dgettext(
              "content_proposals",
              "Image %{new}'s file is delivered through another CDN than image %{old}'s field uses, so image %{old} would not find it. Upload the file again to image %{old}'s field.",
              new: new.id,
              old: old.id
            )
          )
        ]

      is_nil(facts[:type]) ->
        [
          problem(
            :unreadable_file,
            dgettext("content_proposals", "The file of image %{id} could not be read.", id: new.id)
          )
        ]

      true ->
        kind_problems(facts[:type], type_from_path(old.path)) ++ config_problems(facts, cfg, old, new)
    end
  end

  # The CDN an image config delivers through, if any: its own or, as the
  # uploader falls back to it, the one for all images. OLD takes NEW's file
  # where NEW's config put it, and reads and links it through its own.
  defp delivery(%Image{} = image) do
    {:ok, cfg} = Images.get_config_for(image)
    delivery(cfg)
  end

  defp delivery(cfg) do
    case Images.effective_cdn(cfg) do
      %{enabled: true} = cdn -> {Map.get(cdn, :bucket), Map.get(cdn, :media_url)}
      _ -> nil
    end
  end

  # An SVG has no sizes, and a raster image's crops mean nothing to one.
  defp kind_problems(@svg, @svg), do: []

  defp kind_problems(@svg, _old_type),
    do: [problem(:wrong_media_type, dgettext("content_proposals", "An SVG can only replace an SVG."))]

  defp kind_problems(_type, @svg),
    do: [problem(:wrong_media_type, dgettext("content_proposals", "An SVG can only be replaced with an SVG."))]

  defp kind_problems(_type, _old_type), do: []

  defp config_problems(%{type: type, bytes: bytes}, cfg, old, new) do
    allowed = Intake.allowed_types(cfg)
    limit = Intake.size_limit(cfg)

    cond do
      type not in allowed ->
        [
          problem(
            :wrong_media_type,
            dgettext(
              "content_proposals",
              "Image %{old}'s field takes %{types}; the file of image %{new} is %{type}.",
              old: old.id,
              new: new.id,
              types: types(allowed),
              type: Intake.describe_types([type])
            )
          )
        ]

      bytes > limit ->
        [
          problem(
            :too_large,
            dgettext(
              "content_proposals",
              "The file of image %{new} is larger than image %{old}'s field takes (%{limit}).",
              new: new.id,
              old: old.id,
              limit: Brando.Utils.human_size(limit)
            )
          )
        ]

      true ->
        []
    end
  end

  defp types([]), do: dgettext("content_proposals", "no images")
  defp types(allowed), do: Intake.describe_types(allowed)

  # What the snapshot read of NEW's bytes when the proposal was prepared.
  # `changed/2` has found the row on the same path and `content_hash` since,
  # so the same bytes: they are not read again at approval, inside the
  # apply's transaction, or for a preview.
  defp known_facts(%{"type" => type, "bytes" => bytes}) when is_binary(type) and is_integer(bytes),
    do: %{type: type, bytes: bytes}

  defp known_facts(_snapshot), do: nil

  # What NEW's bytes are and how many. A file kept only on the CDN is fetched
  # for this, and removed again.
  defp file_facts(%Image{} = image) do
    case Images.restore_original(image) do
      {:ok, restored} ->
        try do
          read_facts(image.path)
        after
          Images.discard_restored_original(image, restored)
        end

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp read_facts(media_path) do
    with {:ok, path} <- Brando.Tenant.Storage.media_file(media_path),
         {:ok, %File.Stat{size: bytes}} <- File.stat(path),
         {:ok, head} <- ContentType.head(path) do
      %{type: ContentType.image(head), bytes: bytes}
    else
      _ -> %{}
    end
  end

  defp type_from_path(path) when is_binary(path) do
    case path |> Path.extname() |> String.downcase() do
      ".svg" -> @svg
      "" -> nil
      ext -> MIME.from_path("file" <> ext)
    end
  end

  defp type_from_path(_path), do: nil

  defp in_use(%Image{id: id}) do
    if Usage.used?(:image, id),
      do: [
        problem(
          :asset_in_use,
          dgettext(
            "content_proposals",
            "Image %{id} is already used, and its record goes when its file replaces another image's. Swap the references to it instead (set_block_media, set_fields), or upload the file again as a new image.",
            id: id
          )
        )
      ],
      else: []
  end

  defp permissions(old, new, actor) do
    images =
      for image <- Enum.uniq_by([old, new], & &1.id), Boundary.authorize(actor, :update, image) != :ok, do: image.id

    if images != [] do
      [
        problem(
          :forbidden,
          dngettext(
            "content_proposals",
            "You may not change image %{ids}.",
            "You may not change images %{ids}.",
            length(images),
            ids: Enum.join(images, ", ")
          )
        )
      ]
    else
      entry_permissions(old, actor)
    end
  end

  # Every entry that shows OLD changes with it, and one in the trash once it
  # is restored.
  defp entry_permissions(%Image{id: id} = old, actor) do
    forbidden =
      :image
      |> Usage.owners([id], include_deleted: true)
      |> Map.get(id, [])
      |> Enum.reject(&updatable?(&1, actor))

    if forbidden == [] do
      []
    else
      {named, hidden} = named(forbidden, actor)

      [
        problem(
          :forbidden,
          dgettext(
            "content_proposals",
            "Replacing the file of image %{id} changes every entry that shows it, and you may not change %{entries}.",
            id: old.id,
            entries: entries_phrase(named, hidden)
          )
        )
      ]
    end
  end

  defp updatable?({schema, id}, actor) do
    case Repo.get(schema, id) do
      nil -> true
      entry -> Boundary.authorize(actor, :update, entry) == :ok
    end
  end

  defp entries_phrase(named, 0), do: Enum.join(named, ", ")

  defp entries_phrase([], hidden),
    do: dngettext("content_proposals", "%{count} entry you cannot see", "%{count} entries you cannot see", hidden)

  defp entries_phrase(named, hidden) do
    dngettext(
      "content_proposals",
      "%{entries} and %{count} entry you cannot see",
      "%{entries} and %{count} entries you cannot see",
      hidden,
      entries: Enum.join(named, ", ")
    )
  end

  # The entries `actor` may read, by name, and how many others.
  defp named(entries, actor) do
    readable = Boundary.with_scope(Boundary.actor_scope(actor), fn -> Boundary.readable_entries(entries) end)
    labels = entries |> Enum.filter(&MapSet.member?(readable, &1)) |> Usage.labels()

    named =
      for entry <- entries, %{label: label, type: type} <- [labels[entry]], do: "#{type} “#{label}”"

    {Enum.sort(named), length(entries) - map_size(labels)}
  end

  @doc "The entries that use image `id`, as `{schema, id}`."
  @spec owners(Image.t() | integer()) :: [{module(), integer()}]
  def owners(%Image{id: id}), do: owners(id)
  def owners(id) when is_integer(id), do: :image |> Usage.owners([id]) |> Map.get(id, [])

  ## Review

  @doc """
  Fails unless `viewer` may read the images `operations` replace and the
  ones whose files replace them, for a review shared with them: the review
  shows both files. Once applied, NEW's record is gone and OLD decides.
  """
  @spec readable!([struct()], term(), boolean()) :: :ok
  def readable!(operations, viewer, applied?) do
    ids =
      for %ReplaceImageFile{asset: {:image, old_id}, with: {:image, new_id}} <- operations,
          id <- if(applied?, do: [old_id], else: [old_id, new_id]),
          uniq: true,
          do: id

    if Enum.all?(ids, &readable(&1, viewer)),
      do: :ok,
      else: Error.fail!(dgettext("content_proposals", "You may not see the images this proposal replaces."))
  end

  @doc """
  What the reviewer sees of each `replace_image_file` of `proposal`: the two
  files as they were prepared, whether their proportions differ, and the
  entries that use OLD (those the viewer may read, with their admin links,
  and how many others).
  """
  @spec review(struct()) :: [map()]
  def review(%{operations: operations, problems: problems}) do
    for {%ReplaceImageFile{asset: {:image, old_id}, with: {:image, new_id}} = op, index} <-
          Enum.with_index(operations) do
      owners = owners(old_id)
      readable = Boundary.readable_entries(owners)
      labels = owners |> Enum.filter(&MapSet.member?(readable, &1)) |> Usage.labels()

      %{
        operations: [index],
        old: view(old_id, op.old),
        new: view(new_id, op.new),
        proportions_differ?: proportions_differ?(op.old, op.new),
        entries: labels |> Map.values() |> Enum.sort_by(&String.downcase(&1.label)),
        hidden: length(owners) - map_size(labels),
        problems: for(%{operation: ^index} = problem <- problems || [], do: problem)
      }
    end
  end

  defp view(id, nil), do: %{id: id, image: nil, name: nil, width: nil, height: nil, type: nil}

  defp view(id, snapshot) do
    %{
      id: id,
      image: %Image{
        id: id,
        path: snapshot["path"],
        width: snapshot["width"],
        height: snapshot["height"],
        sizes: snapshot["sizes"] || %{},
        cdn: snapshot["cdn"] == true,
        formats: formats(snapshot["formats"])
      },
      name: snapshot["path"] && Path.basename(snapshot["path"]),
      width: snapshot["width"],
      height: snapshot["height"],
      type: snapshot["type"] && Intake.describe_types([snapshot["type"]])
    }
  rescue
    _ -> %{id: id, image: nil, name: nil, width: nil, height: nil, type: nil}
  end

  defp formats(formats) when is_list(formats) do
    Enum.flat_map(formats, fn format ->
      case Enum.find(~w(original jpg png gif webp avif svg)a, &(to_string(&1) == format)) do
        nil -> []
        format -> [format]
      end
    end)
  end

  defp formats(_formats), do: []

  @doc """
  Whether two files' proportions differ, from their `"width"` and
  `"height"`: OLD's crops and focal point would frame NEW differently.
  """
  @spec proportions_differ?(map() | nil, map() | nil) :: boolean()
  def proportions_differ?(%{"width" => w1, "height" => h1}, %{"width" => w2, "height" => h2})
      when is_integer(w1) and is_integer(h1) and is_integer(w2) and is_integer(h2) and h1 > 0 and h2 > 0 and w1 > 0 do
    abs(w1 / h1 - w2 / h2) / (w1 / h1) > @ratio_tolerance
  end

  def proportions_differ?(_old, _new), do: false

  ## Apply

  @doc """
  Fails the approval of `operations` while the sizes of an image whose file
  replaces another are still being made: OLD shows NEW's sizes until its own
  are. Not a problem of the proposal, which a tool prepares right after
  uploading: the approval is tried again in a moment.
  """
  @spec ready!([struct()]) :: :ok
  def ready!(operations) when is_list(operations) do
    ids = for %ReplaceImageFile{with: {:image, id}} <- operations, do: id

    Repo.all(from(i in Image, where: i.id in ^ids and i.status != :processed))
    |> Enum.each(&ready!/1)
  end

  def ready!(%Image{status: :processed}), do: :ok

  def ready!(%Image{id: id}),
    do:
      Error.fail!(
        dgettext(
          "content_proposals",
          "The sizes of image %{id} are still being made. Approve the proposal again in a moment.",
          id: id
        )
      )

  @doc """
  Replace OLD's file with NEW's, inside the proposal's transaction, as
  `actor` (`user` is who the sizes are made for). Both rows are locked and
  checked again; a problem fails the whole proposal. Returns what the
  receipt keeps of it.
  """
  @spec apply!(ReplaceImageFile.t(), [struct()], term(), term()) :: map()
  def apply!(%ReplaceImageFile{asset: {:image, old_id}, with: {:image, new_id}} = op, operations, actor, user) do
    Repo.all(from(i in Image, where: i.id in ^[old_id, new_id], order_by: i.id, lock: "FOR UPDATE"))

    case problems(op, operations, actor) do
      [] -> :ok
      [%{message: message} | _] -> Error.fail!(message)
    end

    old = Repo.get!(Image, old_id)
    new = Repo.get!(Image, new_id)
    ready!(new)

    replaced =
      old
      |> Ecto.Changeset.change(
        path: new.path,
        width: new.width,
        height: new.height,
        formats: new.formats,
        content_hash: new.content_hash,
        dominant_color: new.dominant_color,
        cdn: new.cdn,
        # A size NEW lacks stays OLD's own until OLD's sizes are made
        sizes: Map.merge(old.sizes || %{}, new.sizes || %{}),
        status: :unprocessed,
        config_fingerprint: nil
      )
      |> Repo.update!()

    discarded = discard_jobs(new_id)
    Repo.delete!(new)

    # The entries that show OLD link its previous files until they are
    # rendered again, and a cached page longer
    Brando.Media.OrphanCleanup.hold_image_files(old)

    # A run of Image sizes waiting to recreate NEW counts OLD's job instead
    prepare = &Images.SizeRun.carry_over(&1, discarded)

    case Images.Processing.queue_processing(replaced, user, [], silent: true, prepare: prepare) do
      {:ok, _job} ->
        :ok

      error ->
        Error.fail!(dgettext("content_proposals", "Could not queue the image's sizes: %{error}", error: inspect(error)))
    end

    Brando.Activity.setting_changed(:updated, replaced, Path.basename(replaced.path), user,
      fields: ["file"],
      details: %{"replaced_file" => %{"from" => Path.basename(old.path), "with" => new_id}}
    )

    %{"image" => old_id, "with" => new_id, "from" => old.path, "to" => new.path}
  end

  # NEW's jobs that have not started would find no image. One already running
  # writes what OLD's own run writes again. Returns the deleted jobs' state
  # and meta, for `Brando.Images.SizeRun.carry_over/2`.
  defp discard_jobs(image_id) do
    workers = Enum.map([Brando.Worker.ImageProcessor, Brando.Worker.ImageUploader], &Oban.Worker.to_string/1)
    args = TenantJob.attach(%{image_id: image_id})

    {_count, deleted} =
      Repo.delete_all(
        from(j in Oban.Job,
          where: j.worker in ^workers and j.state in ^@unstarted and fragment("? @> ?", j.args, ^args),
          select: %{state: j.state, meta: j.meta}
        )
      )

    deleted
  end

  @doc "Once the proposal is committed: what reads the images afresh."
  @spec after_commit([map()]) :: :ok
  def after_commit(replaced) do
    for %{"image" => id} <- replaced do
      Brando.Cache.Query.evict_entry(Image, id)
    end

    :ok
  rescue
    error ->
      Logger.warning("[Brando.Content.Proposals.ImageReplacement] " <> Exception.message(error))
      :ok
  end

  defp problem(code, message), do: %{code: code, message: message}
end
