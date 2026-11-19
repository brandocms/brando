defmodule Brando.Figma.Import do
  @moduledoc """
  Imports the image fills of a Figma frame into the media library, as the
  person whose tool asked, for a proposal to use.

  The images go into the library folder `figma/<frame name as a slug>` under the
  default image config's upload path, as an editor's upload there would.
  They are the originals placed in Figma, not renders. Each is stored the
  way an editor's upload is (`Brando.Uploads.store_upload/4`: the name,
  type, contents and pixel count checked against the config) and its sizes
  are made in the background. An image the library already has (the same
  file, by content hash, for the same config, that the person may read) is
  reused, not stored again, so importing a frame twice adds nothing.

  Only the images that show are imported (`Brando.Figma.Frame.images/1`):
  image fills hidden under a layer's top fill are not. An image Figma shows
  turned a quarter, half or three quarters is stored as a turned copy, a
  file of its own; other angles, a crop's mirroring and the turn of an
  animated GIF or WebP (which would keep one frame) are not applied, and
  the result says so for each layer it concerns. A cropped image is not cut:
  when the image is new to the library, its focal point is set so the site
  shows the crop Figma shows (exactly in a box of the layer's proportions).
  One the library already has keeps its focal point.

  Figma's download URLs are fetched through `Brando.Webhooks.URLGuard`
  (public `https` addresses only, no redirects) and written to a temporary
  file, at most the config's size limit. A few download at once; they are
  stored one after the other, in the caller's site environment and
  authorization scope.

  At most `max_per_call/0` distinct images are imported per call; the result
  says where the next call starts.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Transfer.Catalog
  alias Brando.Figma
  alias Brando.Figma.Frame
  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Uploads
  alias Brando.Uploads.ContentType
  alias Brando.Webhooks.Client
  alias Brando.Webhooks.URLGuard
  alias BrandoAdmin.Images.FolderBrowser
  alias Elixir.Image, as: Vimage

  require Logger

  @max_per_call 8
  # Layers listed per image: a placeholder used all over a frame stays one entry
  @max_layers 10
  @concurrency 3
  @download_timeout 60_000

  @doc "The most distinct images one call imports."
  @spec max_per_call() :: pos_integer()
  def max_per_call, do: @max_per_call

  @doc """
  Imports the images of the frame `link` names, with `token`, as `actor`.

  Options: `:node_ids`, only the images of these layers (as the frame's
  outline names them); `:offset`, where in the frame's distinct images to
  start.
  """
  @spec run(Figma.link(), String.t(), term(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(link, token, actor, opts \\ []) do
    with :ok <- Brando.Authorization.Media.authorize(actor, :image),
         {:ok, node} <- Figma.node(token, link),
         {:ok, images} <- selected(Frame.images(node), opts[:node_ids]) do
      refs = images |> Enum.map(&key/1) |> Enum.uniq()
      offset = max(opts[:offset] || 0, 0)
      page = Enum.slice(refs, offset, @max_per_call)

      folder = folder_path(node.document["name"])
      results = import_page(page, images, link, token, %{actor: actor, folder: folder})

      with %{} <- results do
        next = offset + length(page)

        {:ok,
         %{
           file_name: node.file_name,
           frame: %{node_id: node.document["id"], name: node.document["name"]},
           folder: folder,
           images: describe(page, images, results),
           distinct_images: length(refs),
           next_offset: if(next < length(refs), do: next)
         }}
      end
    end
  end

  # One asset per image and quarter turn: a picture shown turned is a copy of
  # its own, turned as Figma shows it. Other angles are not applied.
  defp key(image), do: {image.image_ref, quarter(image[:rotation])}

  defp quarter(rotation) when rotation in [90, 180, 270], do: rotation
  defp quarter(_rotation), do: 0

  # Nothing is fetched when the page is empty (an offset past the end)
  defp import_page([], _images, _link, _token, _ctx), do: %{}

  defp import_page(page, images, link, token, %{actor: actor, folder: folder}) do
    {cfg, config_target} = Uploads.resolve_image_config(nil)
    root = FolderBrowser.upload_root(config_target)
    absolute = FolderBrowser.absolute_folder(folder, root)

    with {:ok, urls} <- Figma.image_urls(token, link.file_key) do
      folder_id = FolderBrowser.folder_id_for(absolute, root, actor, Image)
      # Never over a file already stored, whatever the config says: an image
      # changed in Figma is a new file next to the old one
      cfg = cfg |> Map.put(:upload_path, absolute) |> Map.put(:overwrite, false)
      ctx = %{cfg: cfg, config_target: config_target, folder_id: folder_id, actor: actor}
      import_all(page, urls, images, ctx)
    end
  end

  defp selected(images, nil), do: {:ok, images}
  defp selected(images, []), do: {:ok, images}

  defp selected(images, node_ids) when is_list(node_ids) do
    wanted = MapSet.new(node_ids, &to_string/1)

    case Enum.filter(images, &MapSet.member?(wanted, &1.node_id)) do
      [] -> {:error, "None of those layers has an image. Use the node_id of an image in read_frame's outline."}
      found -> {:ok, found}
    end
  end

  defp selected(_images, _node_ids), do: {:error, "node_ids is a list of layer ids."}

  # One folder per frame, named after it as a slug: the name is part of
  # every image's address, and a frame name may hold "/", ">" or spaces.
  defp folder_path(name) do
    # `slugify/1` gives nil for a name with nothing a slug keeps ("→", "🎉")
    slug = ((name && Brando.Utils.slugify(name)) || "") |> String.slice(0, 100) |> String.trim("-")

    "figma/" <> if(slug == "", do: "untitled", else: slug)
  end

  # The first layer showing an asset names its file and gives its crop: one
  # image shown with two crops keeps the first (the result says so)
  defp import_all(keys, urls, images, ctx) do
    dir = Path.join(System.tmp_dir!(), "brando-figma-" <> Base.url_encode64(:crypto.strong_rand_bytes(9)))
    File.mkdir_p!(dir)
    firsts = Map.new(Enum.reverse(images), &{key(&1), &1})
    limit = size_limit(ctx.cfg)

    try do
      keys
      |> Enum.with_index()
      |> Task.async_stream(
        fn {{ref, _turn} = key, index} -> {key, download(urls[ref], Path.join(dir, "#{index}"), limit)} end,
        max_concurrency: @concurrency,
        timeout: @download_timeout + 5_000,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(keys)
      |> Map.new(fn
        {{:ok, {key, {:ok, path}}}, key} -> {key, store(path, key, firsts[key], ctx)}
        {{:ok, {key, {:error, message}}}, key} -> {key, {:error, message}}
        {{:exit, _reason}, key} -> {key, {:error, "The download took too long."}}
      end)
    after
      File.rm_rf(dir)
    end
  end

  defp size_limit(cfg) do
    case Map.get(cfg, :size_limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      _ -> Uploads.max_file_size()
    end
  end

  defp download(nil, _path, _limit), do: {:error, "Figma gave no download for this image."}

  defp download(url, path, limit) do
    case Keyword.get(Brando.config(Figma) || [], :downloader) do
      {module, function} -> apply(module, function, [url, path, limit])
      nil -> guarded_download(url, path, limit)
    end
  end

  defp guarded_download(url, path, limit) do
    with {:ok, target} <- URLGuard.resolve(url),
         %{status: 200, error: nil} <-
           Client.request(target, "GET", [{"user-agent", "Brando"}], "",
             into: path,
             body_limit: limit,
             timeout: @download_timeout
           ) do
      {:ok, path}
    else
      %{error: :body_too_large} -> {:error, "The image is larger than #{div(limit, 1_000_000)} MB."}
      %{error: :timeout} -> {:error, "The download took too long."}
      %{error: :unwritable} -> {:error, "The download could not be written to a temporary file."}
      %{status: 200} -> {:error, "The download was cut off. Try again."}
      %{status: status} when is_integer(status) -> {:error, "Figma's download answered #{status}."}
      _ -> {:error, "The image could not be downloaded."}
    end
  end

  # One store of a file for the config at a time (`Images.with_file_lock/3`):
  # two imports of the same picture at once find each other's image. Its
  # sizes are queued once the row is committed. A turned copy is a file of
  # its own, so it is reused only for the same picture turned the same way.
  # An animated image is stored as it is, upright: turning it would keep
  # only its first frame.
  defp store(path, {_ref, turn}, first, ctx) do
    with {:ok, head} <- ContentType.head(path),
         {:ok, type, ext} <- image_type(head),
         {:ok, path, turned} <- turn(path, turn, ext) do
      hash = hash(path)
      name = if turned == 0, do: first.name, else: "#{first.name} #{turned}"
      crop = if turned == turn, do: first[:crop], else: unturn(first[:crop], turn)
      store = fn -> reuse_or_store(hash, path, filename(name, ext), type, crop, ctx) end

      hash
      |> Images.with_file_lock(ctx.config_target, store)
      |> queue_sizes(ctx.actor)
      |> upright(turned == turn)
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, "Not a JPEG, PNG, GIF or WebP image."}
    end
  end

  # The file to store and the turn it has: 0 for an animated image (a GIF or
  # WebP of more than one frame), which is not turned
  defp turn(path, 0, _ext), do: {:ok, path, 0}

  # Upright by its EXIF orientation first, as Figma and browsers show it. A
  # lossy format is written near its original quality, not the encoder's
  # default (75).
  defp turn(path, degrees, ext) do
    turned = "#{path}-turned.#{ext}"

    with {:ok, img} <- Vimage.open(path),
         :ok <- Images.PixelLimit.check(img),
         false <- Vimage.pages(img) > 1,
         {:ok, {img, _flags}} <- Vimage.autorotate(img),
         {:ok, img} <- Vimage.rotate(img, degrees),
         {:ok, _img} <- Vimage.write(img, turned, write_options(ext)) do
      {:ok, turned, degrees}
    else
      true -> {:ok, path, 0}
      {:error, :too_many_pixels} -> {:error, Images.PixelLimit.error_message()}
      _ -> {:error, "The image could not be turned #{degrees}°."}
    end
  end

  # A crop given in the image as Figma turns it, in the image as stored
  defp unturn(%{x: x, y: y, width: width, height: height}, 90),
    do: %{x: y, y: 1 - x - width, width: height, height: width}

  defp unturn(%{x: x, y: y, width: width, height: height}, 180),
    do: %{x: 1 - x - width, y: 1 - y - height, width: width, height: height}

  defp unturn(%{x: x, y: y, width: width, height: height}, 270),
    do: %{x: 1 - y - height, y: x, width: height, height: width}

  defp unturn(crop, _turn), do: crop

  defp write_options(ext) when ext in ["jpg", "webp"], do: [quality: 95]
  defp write_options(_ext), do: []

  # An image the library has keeps its focal point: an editor may have set it
  defp reuse_or_store(hash, path, filename, type, crop, ctx) do
    case existing(hash, ctx) do
      %Image{} = image -> {:reused, image}
      nil -> path |> store_new(filename, type, ctx) |> put_focal(crop, ctx.actor)
    end
  end

  defp put_focal({:stored, image}, crop, actor) when is_map(crop) do
    case Images.update_image(image, %{focal: focal(crop)}, actor) do
      {:ok, image} ->
        {:stored, image, :focal}

      error ->
        Logger.warning("[Brando.Figma] Could not set the focal point of image #{image.id}: #{inspect(error)}")
        {:stored, image, :focal_failed}
    end
  end

  defp put_focal(result, _crop, _actor), do: result

  # The focal point is rendered as CSS `object-position: x% y%`, which lines
  # up the point p% across the image with the point p% across the box: the
  # hidden part of an axis is split p : (100 - p). The crop hides `offset`
  # before it and `1 - offset - size` after it, so p = offset / (1 - size).
  # A box with the Figma layer's aspect ratio then shows exactly the crop;
  # another keeps the same end of the image. An axis the crop spans hides
  # nothing: 50. The crop is in the image as stored, as is the focal point.
  @doc false
  def focal(%{x: x, y: y, width: width, height: height}), do: %{x: position(x, width), y: position(y, height)}

  defp position(_offset, size) when size >= 1 - 1.0e-3, do: 50
  defp position(offset, size), do: percent(offset / (1 - size))

  defp percent(fraction), do: fraction |> Kernel.*(100) |> round() |> max(0) |> min(100)

  # A queueing that fails leaves the image unprocessed; importing it again
  # finds it and queues it then
  defp queue_sizes({:stored, image, _focal} = result, actor) do
    queue_sizes({:stored, image}, actor)
    result
  end

  defp queue_sizes({:stored, image} = result, actor) do
    case Images.Processing.queue_processing(image, actor, [], silent: true) do
      {:ok, _job} -> :ok
      error -> Logger.warning("[Brando.Figma] Could not queue image #{image.id}: #{inspect(error)}")
    end

    result
  end

  defp queue_sizes({:reused, image} = result, actor) do
    Images.ensure_processing_queued(image, actor)
    result
  end

  defp queue_sizes(result, _actor), do: result

  defp image_type(head) do
    case ContentType.image(head) do
      "image/jpeg" -> {:ok, "image/jpeg", "jpg"}
      "image/png" -> {:ok, "image/png", "png"}
      "image/gif" -> {:ok, "image/gif", "gif"}
      "image/webp" -> {:ok, "image/webp", "webp"}
      _ -> :error
    end
  end

  defp store_new(path, filename, type, ctx) do
    meta = %{path: path, config_target: ctx.config_target, folder_id: ctx.folder_id}
    entry = %{client_name: filename, client_type: type, client_size: File.stat!(path).size}

    case Uploads.store_upload(meta, entry, ctx.cfg, ctx.actor) do
      {:ok, %Image{} = image} -> {:stored, image}
      {:error, message} -> {:error, message}
    end
  end

  defp existing(hash, ctx) do
    query =
      from(i in Image,
        where: i.content_hash == ^hash and i.config_target == ^ctx.config_target and is_nil(i.deleted_at),
        order_by: [asc: i.id],
        limit: 1
      )

    query |> Catalog.scoped_query(Image, ctx.actor, :read) |> Brando.Repo.one()
  end

  defp hash(path) do
    path
    |> File.stream!(1_048_576)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  # Layer names such as "Rectangle 12" or "hero"; the store makes it unique
  defp filename(name, ext) do
    base =
      (name || "")
      |> Brando.Utils.slugify()
      |> Kernel.||("")
      |> String.slice(0, 80)

    if(base == "", do: "figma", else: base) <> "." <> ext
  end

  # One entry per asset of the page, in the frame's order, with the layers
  # that show it (each once) and what of Figma's crop, rotation and mirroring
  # was applied, for every layer that shows it
  defp describe(page, images, results) do
    shown_by = Enum.group_by(images, &key/1)

    Enum.map(page, fn key ->
      shown = Map.get(shown_by, key, [])
      layers = shown |> Enum.uniq_by(& &1.node_id) |> Enum.map(&Map.take(&1, [:node_id, :name, :section]))
      entry = %{layers: Enum.take(layers, @max_layers)}

      entry =
        if length(layers) > @max_layers, do: Map.put(entry, :layers_left_out, length(layers) - @max_layers), else: entry

      case results[key] do
        {:error, message} -> Map.put(entry, :error, message)
        result -> Map.merge(entry, asset(result, shown, length(layers) > 1))
      end
    end)
  end

  defp asset(result, [first | _] = shown, several?) do
    {result, upright?} =
      case result do
        {:upright, result} -> {result, true}
        result -> {result, false}
      end

    {asset, reused, focal} =
      case result do
        {:stored, asset, focal} -> {asset, false, focal}
        {:stored, asset} -> {asset, false, nil}
        {:reused, asset} -> {asset, true, :reused}
      end

    {applied, not_applied} =
      shown
      |> Enum.flat_map(&applied(&1, first, %{focal: focal, upright?: upright?, several?: several?}))
      |> Enum.uniq()
      |> Enum.split_with(&(elem(&1, 0) == :applied))

    %{asset: %{kind: "image", id: asset.id}, reused: reused, rotation: first[:rotation]}
    |> Map.merge(%{
      applied: Enum.map(applied, &elem(&1, 1)),
      not_applied: not_applied |> Enum.map(&elem(&1, 1)) |> capped()
    })
    |> Map.reject(fn {_key, value} -> value in [nil, []] end)
  end

  # Marks an image stored without the turn its layer shows.
  defp upright({:error, _message} = error, _turned?), do: error
  defp upright(result, true), do: result
  defp upright(result, false), do: {:upright, result}

  # One line per layer adds up when a cropped image repeats down a page.
  defp capped(lines) do
    case Enum.split(lines, @max_layers) do
      {lines, []} -> lines
      {lines, rest} -> lines ++ ["and #{length(rest)} more of the same kind on other layers"]
    end
  end

  # What of one layer's image was applied. The asset is the first layer's
  # file: its turn and its crop's focal point; another layer's crop sets
  # nothing. When several layers show the asset, what one of them alone
  # missed names it.
  defp applied(image, first, ctx) do
    rotation = image[:rotation]
    layer = if ctx.several?, do: ~s[layer "#{image.name}" (#{image.node_id}): ], else: ""

    turn =
      cond do
        image[:mirrored] -> [{:not_applied, layer <> "mirrored in Figma: the image is imported unmirrored"}]
        is_nil(rotation) -> []
        quarter(rotation) == 0 -> [{:not_applied, layer <> "rotation #{rotation}°: only quarter turns are applied"}]
        ctx.upright? -> [{:not_applied, "rotated #{rotation}°: the image is animated, so it is imported upright"}]
        true -> [{:applied, "rotated #{rotation}°"}]
      end

    turn ++ crop_applied(image, first, layer, ctx.focal)
  end

  defp crop_applied(%{crop: _crop} = image, first, _layer, focal) when image == first do
    case focal do
      :focal ->
        [{:applied, "focal point from the Figma crop"}]

      :reused ->
        [
          {:not_applied,
           "focal point from the Figma crop: the library already had this image, so it keeps its own focal point"}
        ]

      _failed ->
        [{:not_applied, "focal point from the Figma crop: it could not be saved"}]
    end
  end

  defp crop_applied(%{crop: _crop}, first, layer, _focal) do
    [
      {:not_applied,
       layer <>
         ~s[focal point from the Figma crop: this crop is not used; only the first place the image shows, "#{first.name}" (#{first.node_id}), can set it]}
    ]
  end

  defp crop_applied(_image, _first, _layer, _focal), do: []
end
