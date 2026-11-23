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

  Each image stored or reused is recorded as the Figma picture's, by its
  `imageRef` and the turn of the layers it was imported for
  (`Brando.Images.Source`), so that `read_frame` names it without importing
  again (`put_assets/2`). A record that cannot be written leaves the image
  and the result as they are.

  Only the images that show are imported (`Brando.Figma.Frame.images/1`):
  image fills hidden under a layer's top fill are not. An image Figma shows
  turned a quarter, half or three quarters is stored as a turned copy, a
  file of its own; other angles, a crop's mirroring and the turn of an
  animated GIF or WebP (which would keep one frame) are not applied, and
  the result says so for each layer it concerns. A cropped image is not cut:
  when the image is new to the library, its focal point is set so the site
  shows the crop Figma shows, in `:position` mode (`Brando.Images.Focal`),
  so the sizes Brando cuts and the share cards follow the crop too. A crop
  that spans the image's whole width or height shows exactly in a box of the
  layer's proportions; one that zooms in on both axes shows with more of the
  image around it, as the site always shows the whole width or height of the
  image. One the library already has keeps its focal point.

  Figma's download URLs are fetched through `Brando.Webhooks.URLGuard`
  (public `https` addresses only, no redirects) and written to a temporary
  file, at most the config's size limit. A few download at once; they are
  stored one after the other, in the caller's site environment and
  authorization scope. An image over the size limit is refused with the
  limit, its size when Figma's answer gives it, and what to do.

  With `fit: true`, an image over the size limit is downloaded up to
  `fit_download_limit/0` and stored as a copy scaled down to fit the limit:
  as large as fits, never enlarged and never smaller than twice its largest
  use in the frame (by the layer's box, and for a crop, what the whole image
  needs for the part shown to be twice the box), counting the layers the
  call does not import. A turned copy that comes out over the limit is
  scaled down the same way. A JPEG, PNG or single-frame GIF or WebP that
  cannot get under the limit at that size in its own format is stored as a
  JPEG, or as a WebP when it has transparent pixels, of the types the site
  takes; one still over the limit is refused, as is an animated image (a GIF
  or WebP of more than one frame) and one over the pixel limit
  (`Brando.Images.PixelLimit`, checked before it is decoded). The images
  within the limit are stored as they are.

  At most `max_per_call/0` distinct images are imported per call; the result
  says where the next call starts.
  """

  alias Brando.Figma
  alias Brando.Figma.Frame
  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Images.Intake
  alias Brando.Images.Source
  alias Brando.Uploads
  alias Brando.Uploads.ContentType
  alias Elixir.Image, as: Vimage

  @max_per_call 8
  @source "figma"
  # Layers listed per image: a placeholder used all over a frame stays one entry
  @max_layers 10
  @concurrency 3
  @download_timeout 60_000
  @fit_download_limit 50_000_000
  # Scale-downs tried per format before the floor
  @fit_tries 6

  @doc "The most distinct images one call imports."
  @spec max_per_call() :: pos_integer()
  def max_per_call, do: @max_per_call

  @doc """
  The most bytes `fit: true` downloads of an image to scale it down:
  `:fit_download_limit` in the `Brando.Figma` config, 50 MB by default. The
  site's size limit applies when it is larger.
  """
  @spec fit_download_limit() :: pos_integer()
  def fit_download_limit do
    case Keyword.get(Brando.config(Figma) || [], :fit_download_limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      _ -> @fit_download_limit
    end
  end

  @doc """
  Imports the images of the frame `link` names, as `actor`, calling Figma
  with `credential` (`Brando.Figma.credential/1`), which each request
  resolves again.

  Options: `:node_ids`, only the images of these layers (as the frame's
  outline names them); `:offset`, where in the frame's distinct images to
  start; `:fit`, true to store a scaled-down copy of an image over the size
  limit.
  """
  @spec run(Figma.link(), Figma.credential(), term(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(link, credential, actor, opts \\ []) do
    with :ok <- Brando.Authorization.Media.authorize(actor, :image),
         {:ok, node} <- Figma.node(credential, link),
         frame_images = Frame.images(node),
         {:ok, images} <- selected(frame_images, opts[:node_ids]) do
      refs = images |> Enum.map(&key/1) |> Enum.uniq()
      offset = max(opts[:offset] || 0, 0)
      page = Enum.slice(refs, offset, @max_per_call)

      folder = folder_path(node.document["name"])
      ctx = %{actor: actor, folder: folder, fit: opts[:fit] == true, frame_images: frame_images}
      results = import_page(page, images, link, credential, ctx)

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

  @doc """
  Gives each image of `sections` (`Brando.Figma.Frame.outline/1`) the
  `asset` of the library image an import of it stored or reused, for its
  picture and turn, that `actor` may read and is not in the trash: the
  lowest id when several are. One query for the frame; an image no import
  gave one has none.
  """
  @spec put_assets([map()], term()) :: [map()]
  def put_assets(sections, actor) do
    keys = for section <- sections, image <- section.images, uniq: true, do: source_key(image)
    {_cfg, config_target} = Uploads.resolve_image_config(nil)
    ids = Source.images(@source, keys, config_target, actor)

    Enum.map(sections, fn section -> %{section | images: Enum.map(section.images, &put_asset(&1, ids))} end)
  end

  defp put_asset(image, ids) do
    case ids[source_key(image)] do
      nil -> image
      id -> Map.put(image, :asset, %{kind: "image", id: id})
    end
  end

  defp source_key(image) do
    {ref, turn} = key(image)
    {ref, variant(turn)}
  end

  # One asset per image and quarter turn: a picture shown turned is a copy of
  # its own, turned as Figma shows it. Other angles are not applied.
  defp key(image), do: {image.image_ref, quarter(image[:rotation])}

  defp quarter(rotation) when rotation in [90, 180, 270], do: rotation
  defp quarter(_rotation), do: 0

  # Nothing is fetched when the page is empty (an offset past the end)
  defp import_page([], _images, _link, _credential, _ctx), do: %{}

  # Never over a file already stored, whatever the config says: an image
  # changed in Figma is a new file next to the old one (`Intake.context/2`)
  defp import_page(page, images, link, credential, %{actor: actor, folder: folder} = ctx) do
    with {:ok, urls} <- Figma.image_urls(credential, link.file_key) do
      import_all(page, urls, {images, ctx.frame_images}, Intake.context(actor, folder), ctx.fit)
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
  # image shown with two crops keeps the first (the result says so). The
  # size a copy is scaled down to counts every layer of the frame showing it,
  # imported or not.
  defp import_all(keys, urls, {images, frame_images}, ctx, fit?) do
    dir = Path.join(System.tmp_dir!(), "brando-figma-" <> Base.url_encode64(:crypto.strong_rand_bytes(9)))
    File.mkdir_p!(dir)
    uses = Enum.group_by(images, &key/1)
    frame_uses = Enum.group_by(frame_images, &key/1)

    limits = %{
      site: Intake.size_limit(ctx.cfg),
      fit: fit? && max(Intake.size_limit(ctx.cfg), fit_download_limit()),
      types: Intake.allowed_types(ctx.cfg)
    }

    limit = limits.fit || limits.site

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
      |> Stream.zip(Enum.with_index(keys))
      |> Map.new(fn {downloaded, {key, index}} ->
        result =
          case downloaded do
            {:ok, {^key, {:ok, path}}} ->
              path |> store(key, {uses[key], frame_uses[key]}, ctx, limits) |> recorded(key, ctx)

            {:ok, {^key, {:error, {:too_large, size}}}} ->
              {:error, too_large(key, uses[key], size, limits)}

            {:ok, {^key, {:error, message}}} ->
              {:error, message}

            {:exit, _reason} ->
              {:error, "The download took too long."}
          end

        discard(Path.join(dir, "#{index}"))
        {key, result}
      end)
    after
      File.rm_rf(dir)
    end
  end

  # The picture each stored or reused image holds, for read_frame to name it
  # (`put_assets/2`)
  defp recorded(result, {ref, turn}, ctx) do
    with %Image{} = image <- image(result) do
      Source.record(image, @source, ref, variant(turn), ctx.config_target)
    end

    result
  end

  defp image({:fitted, _fitted, result}), do: image(result)
  defp image({:upright, result}), do: image(result)
  defp image({:stored, image}), do: image
  defp image({:stored, image, _tag}), do: image
  defp image({:reused, image}), do: image
  defp image({:error, _message}), do: nil

  # The turn of the layers an image was imported for, whether or not it was
  # applied: an animated image is stored upright, and it is still what an
  # import gives those layers
  defp variant(0), do: nil
  defp variant(turn), do: Integer.to_string(turn)

  # A download and the copies made of it, once its image is stored or refused
  defp discard(path), do: Enum.each([path | Path.wildcard(path <> "-*")], &File.rm/1)

  defp download(nil, _path, _limit), do: {:error, "Figma gave no download for this image."}

  defp download(url, path, limit) do
    case Keyword.get(Brando.config(Figma) || [], :downloader) do
      {module, function} -> apply(module, function, [url, path, limit])
      nil -> Intake.download(url, path, limit, timeout: @download_timeout, who: "Figma's download", too_large: :size)
    end
  end

  # An image over what was downloaded: the site's limit, or with `fit` the
  # import's own
  defp too_large(key, uses, size, %{site: site, fit: false}) do
    advice =
      if is_integer(size) and size > fit_download_limit(),
        do:
          " It is also over the #{bytes(fit_download_limit())} the import downloads to scale an image down, so ask an administrator to raise the site's limit.",
        else:
          " Call again with fit: true to import a copy scaled down to fit the limit, or ask an administrator to raise it."

    subject(key, uses) <> " is " <> over(size, "the site's upload limit of #{bytes(site)}") <> "." <> advice
  end

  defp too_large(key, uses, size, %{fit: fit}) do
    subject(key, uses) <>
      " is " <>
      over(size, "the #{bytes(fit)} the import downloads to scale an image down") <>
      ". Ask an administrator to raise the site's upload limit or the import's."
  end

  defp over(nil, limit), do: "over " <> limit
  defp over(size, limit), do: "#{bytes(size)}, over " <> limit

  # The image a message is about: the first layer showing it, and its ref
  defp subject({ref, _turn}, [first | _]), do: ~s[The image "#{first.name}" (#{first.node_id}, image ref #{ref})]

  # Bytes as a person reads them, in powers of 1000 as a file manager shows them
  defp bytes(bytes) when bytes < 1_000, do: "#{bytes} bytes"
  defp bytes(bytes) when bytes < 1_000_000, do: "#{Float.round(bytes / 1_000, 1)} kB"
  defp bytes(bytes), do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  # Stored or reused by `Intake.store/5`. A turned copy is a file of its
  # own, so it is reused only for the same picture turned the same way.
  # An animated image is stored as it is, upright: turning it would keep
  # only its first frame.
  defp store(path, {_ref, turn} = key, {[first | _], _frame_uses} = uses, ctx, limits) do
    with {:ok, head} <- ContentType.head(path),
         {:ok, type, ext} <- image_type(head),
         {:ok, %{path: path, type: type, ext: ext, turned: turned, fitted: fitted}} <-
           prepare(path, type, ext, key, uses, limits) do
      name = if turned == 0, do: first.name, else: "#{first.name} #{turned}"
      crop = if turned == turn, do: first[:crop], else: unturn(first[:crop], turn)

      # A new image is created with its focal point, under the permission to
      # create it; an image the library has keeps its own: an editor may have set it
      {on_new, attrs} = crop_focal(crop)

      path
      |> Intake.store(Intake.filename(name, ext, "figma"), type, ctx, on_new, attrs)
      |> upright(turned == turn)
      |> fitted(fitted)
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, "Not a JPEG, PNG, GIF or WebP image."}
    end
  end

  # The file to store, its type and the turn it has, and how it was scaled
  # down: only with `fit`, and only an image over the site's limit, as
  # downloaded or as turned
  defp prepare(path, type, ext, key, uses, limits) do
    size = File.stat!(path).size

    if limits.fit && size > limits.site,
      do: fit(path, type, ext, key, uses, limits, size),
      else: turned(path, type, ext, key, uses, limits)
  end

  defp turned(path, type, ext, {_ref, turn} = key, uses, limits) do
    with {:ok, turned_path, turned} <- turn(path, turn, ext) do
      turned_size = File.stat!(turned_path).size

      if limits.fit && turned_size > limits.site,
        do: fit(path, type, ext, key, uses, limits, turned_size),
        else: {:ok, %{path: turned_path, type: type, ext: ext, turned: turned, fitted: nil}}
    end
  end

  @fit_formats %{"jpg" => "image/jpeg", "png" => "image/png", "gif" => "image/gif", "webp" => "image/webp"}

  # A copy within the site's limit, turned as Figma shows it, in the image's
  # own format, else as a JPEG (or a WebP when it has transparent pixels),
  # of the formats the site takes. The header is read first: the pixel limit
  # and the frames are checked before anything is decoded. `over` is the
  # bytes of the file known to be over the limit, which sets the scale the
  # own format is first tried at.
  defp fit(path, type, ext, {_ref, turn} = key, {uses, frame_uses}, limits, over) do
    limit = limits.site

    with :ok <- Images.PixelLimit.check(path, Images.PixelLimit.open_options(type)),
         {:ok, img} <- Vimage.open(path),
         false <- Vimage.pages(img) > 1,
         {:ok, {upright, _flags}} <- Vimage.autorotate(img) do
      size = {Vimage.width(upright), Vimage.height(upright)}
      shown = turned_size(size, turn)
      floor = floor_scale(frame_uses, shown)
      fallback = if transparent?(img), do: "webp", else: "jpg"
      tries = Enum.uniq_by([{ext, start_scale(over, limit, floor)}, {fallback, 1.0}], &elem(&1, 0))
      copy = %{path: path, ext: ext, turn: turn, size: size, shown: shown, floor: floor, limit: limit}
      fit_copy(tries, key, uses, copy, limits.types)
    else
      true ->
        {:error,
         subject(key, uses) <>
           " is over the site's upload limit of #{bytes(limit)}, and it is animated: an animated GIF or WebP is not scaled down, " <>
           "as the copy would keep one frame. Ask an administrator to raise the limit."}

      {:error, :too_many_pixels} ->
        {:error, Images.PixelLimit.error_message()}

      _ ->
        {:error, subject(key, uses) <> " could not be read to scale it down."}
    end
  end

  # The first of `tries` the site takes that fits, written next to the download
  defp fit_copy(tries, key, uses, copy, types) do
    case Enum.filter(tries, fn {format, _scale} -> Map.fetch!(@fit_formats, format) in types end) do
      [] ->
        {:error,
         subject(key, uses) <>
           " is over the site's upload limit of #{bytes(copy.limit)}, and a copy scaled down would be " <>
           Enum.map_join(tries, " or ", &("a " <> format_name(elem(&1, 0)))) <>
           ", which the site does not take: it takes #{Intake.describe_types(types)}. Ask an administrator to raise the limit."}

      tries ->
        tries
        |> first_fit(copy.path, copy.turn, copy.size, copy.floor, copy.limit)
        |> fitted_copy(key, uses, copy)
    end
  end

  defp fitted_copy({:ok, data, format, {width, height}}, key, uses, copy) do
    fitted = "#{copy.path}-fitted.#{format}"

    case File.write(fitted, data) do
      :ok ->
        {:ok,
         %{
           path: fitted,
           type: Map.fetch!(@fit_formats, format),
           ext: format,
           turned: copy.turn,
           fitted:
             %{
               original: dimensions(copy.shown),
               stored: %{width: width, height: height},
               format: if(format != copy.ext, do: format_name(format))
             }
             |> Map.reject(fn {_key, value} -> is_nil(value) end)
         }}

      {:error, _reason} ->
        {:error, subject(key, uses) <> " was scaled down, but the copy could not be written to a temporary file."}
    end
  end

  defp fitted_copy({:over, format, dimensions}, key, uses, copy),
    do: {:error, still_over(key, uses, copy, dimensions, format)}

  defp fitted_copy(:error, key, uses, _copy),
    do: {:error, subject(key, uses) <> " could not be scaled down: the copy could not be encoded."}

  defp still_over(key, uses, copy, {width, height}, format) do
    subject(key, uses) <>
      " is still over the site's upload limit of #{bytes(copy.limit)} scaled down to #{width}×#{height}" <>
      if(copy.floor >= 1, do: ", its full size", else: ", twice its largest use in the frame") <>
      if(format != copy.ext, do: ", as #{format_name(format)}", else: "") <>
      ". Ask an administrator to raise the limit."
  end

  # Vix reads a GIF with an alpha band even when no pixel is transparent
  defp transparent?(img) do
    case Vimage.split_alpha(img) do
      {_img, nil} ->
        false

      {_img, alpha} ->
        # A 16-bit image counts its alpha to 65535
        opaque = if Vix.Vips.Image.format(alpha) == :VIPS_FORMAT_USHORT, do: 65_535, else: 255

        case Vix.Vips.Operation.min(alpha) do
          {:ok, {min, _extra}} -> min < opaque
          _ -> true
        end
    end
  end

  # The own format starts where its bytes say a copy fits (bytes grow with
  # the pixels, so with the square of the scale), never under `floor`
  defp start_scale(over, limit, floor), do: :math.sqrt(limit / over) |> Kernel.*(0.95) |> min(1.0) |> max(floor)

  # The first format a copy fits in, else the last that was over, else
  # :error when none could be encoded
  defp first_fit(tries, path, turn, size, floor, limit) do
    Enum.reduce_while(tries, :error, fn {format, scale}, last ->
      case shrink(format, path, turn, size, floor, limit, scale) do
        {:ok, _data, _format, _dimensions} = fitted -> {:halt, fitted}
        {:over, _format, _dimensions} = over -> {:cont, over}
        :error -> {:cont, last}
      end
    end)
  end

  # From `scale` down, each try scaled by how far the last was over, never
  # under `floor`; the last try is the floor. A first try that fits with
  # room to spare is tried once larger (`larger_scale/3`).
  defp shrink(format, path, turn, size, floor, limit, scale, tries \\ @fit_tries) do
    case encode(path, format, turn, size, scale) do
      {:ok, data, dimensions} when byte_size(data) <= limit ->
        larger = if tries == @fit_tries, do: larger_scale(scale, limit, data)

        with true <- is_float(larger),
             {:ok, more, more_dimensions} when byte_size(more) <= limit <- encode(path, format, turn, size, larger) do
          {:ok, more, format, more_dimensions}
        else
          _ -> {:ok, data, format, dimensions}
        end

      {:ok, data, dimensions} ->
        cond do
          scale <= floor -> {:over, format, dimensions}
          tries <= 2 -> shrink(format, path, turn, size, floor, limit, floor, 1)
          true -> shrink(format, path, turn, size, floor, limit, next_scale(scale, floor, limit, data), tries - 1)
        end

      :error ->
        :error
    end
  end

  # A first try under full size that fits in less than half the limit was
  # started too low: the download packed worse than the copy does (a PNG
  # saved without compression, a JPEG at full quality). It is tried once
  # more at the scale its own bytes say fits, and the larger copy is kept
  # when it does.
  defp larger_scale(scale, limit, data) when scale < 1.0 and byte_size(data) * 2 < limit,
    do: min(1.0, scale * :math.sqrt(limit / byte_size(data)) * 0.95)

  defp larger_scale(_scale, _limit, _data), do: nil

  defp next_scale(scale, floor, limit, data), do: max(floor, scale * :math.sqrt(limit / byte_size(data)) * 0.95)

  # Thumbnailed from the file: upright by its EXIF orientation, read at a
  # reduced size where the format allows it, never enlarged
  defp encode(path, format, turn, size, scale) do
    {width, height} = scaled(size, scale)

    with {:ok, img} <- Vimage.thumbnail(path, "#{width}x#{height}", resize: :down),
         {:ok, img} <- rotated(img, turn),
         {:ok, data} <- Vimage.write(img, :memory, [suffix: "." <> format] ++ write_options(format)) do
      {:ok, data, {Vimage.width(img), Vimage.height(img)}}
    else
      _ -> :error
    end
  end

  defp rotated(img, 0), do: {:ok, img}
  defp rotated(img, degrees), do: Vimage.rotate(img, degrees)

  defp scaled({width, height}, scale), do: {ceil(width * scale), ceil(height * scale)}

  defp turned_size({width, height}, turn) when turn in [90, 270], do: {height, width}
  defp turned_size(size, _turn), do: size

  defp dimensions({width, height}), do: %{width: width, height: height}

  defp format_name("jpg"), do: "JPEG"
  defp format_name("webp"), do: "WebP"
  defp format_name(format), do: String.upcase(format)

  # The smallest scale of the image, as Figma shows it (`{width, height}`),
  # that shows every layer using it at twice the layer's box, at most 1. A
  # crop shows part of the image across the box, so the whole image needs
  # that much more; a fit image fits the box, a filled or tiled one covers
  # it. A layer without a box needs the whole image.
  defp floor_scale(uses, size), do: uses |> Enum.map(&needed_scale(&1, size)) |> Enum.max(fn -> 1.0 end) |> min(1.0)

  defp needed_scale(%{width: box_width, height: box_height} = use, {width, height})
       when box_width > 0 and box_height > 0 do
    {crop_width, crop_height} =
      case use[:crop] do
        %{width: crop_width, height: crop_height} when crop_width > 0 and crop_height > 0 -> {crop_width, crop_height}
        _ -> {1, 1}
      end

    across = 2 * box_width / (crop_width * width)
    down = 2 * box_height / (crop_height * height)

    if use.scale_mode == "fit" and is_nil(use[:crop]), do: min(across, down), else: max(across, down)
  end

  defp needed_scale(_use, _size), do: 1.0

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

  defp crop_focal(crop) when is_map(crop),
    do: {&{:stored, &1, :focal}, %{focal: Map.put(focal(crop), :mode, :position)}}

  defp crop_focal(_crop), do: {&{:stored, &1}, %{}}

  # The focal point is rendered as CSS `object-position: x% y%`, which lines
  # up the point p% across the image with the point p% across the box: the
  # hidden part of an axis is split p : (100 - p). The crop hides `offset`
  # before it and `1 - offset - size` after it, so p = offset / (1 - size).
  # A box that shows the whole of one axis and the crop's share of the other
  # then shows exactly the crop; one that shows more keeps the crop in view.
  # An axis the crop spans hides nothing: 50. The crop is in the image as
  # stored, as is the focal point. Stored in `:position` mode, the server cuts
  # its sizes the same way.
  @doc false
  def focal(%{x: x, y: y, width: width, height: height}), do: %{x: position(x, width), y: position(y, height)}

  defp position(_offset, size) when size >= 1 - 1.0e-3, do: 50
  defp position(offset, size), do: percent(offset / (1 - size))

  defp percent(fraction), do: fraction |> Kernel.*(100) |> round() |> max(0) |> min(100)

  defp image_type(head) do
    case ContentType.image(head) do
      "image/jpeg" -> {:ok, "image/jpeg", "jpg"}
      "image/png" -> {:ok, "image/png", "png"}
      "image/gif" -> {:ok, "image/gif", "gif"}
      "image/webp" -> {:ok, "image/webp", "webp"}
      _ -> :error
    end
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
    {result, fitted} =
      case result do
        {:fitted, fitted, result} -> {result, fitted}
        result -> {result, nil}
      end

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

    %{asset: %{kind: "image", id: asset.id}, reused: reused, rotation: first[:rotation], fitted: fitted}
    |> Map.merge(%{
      applied: fitted_applied(fitted) ++ Enum.map(applied, &elem(&1, 1)),
      not_applied: not_applied |> Enum.map(&elem(&1, 1)) |> capped()
    })
    |> Map.reject(fn {_key, value} -> value in [nil, []] end)
  end

  defp fitted_applied(nil), do: []

  defp fitted_applied(%{original: original, stored: stored} = fitted) do
    as = if fitted[:format], do: ", as #{fitted.format}", else: ""

    [
      "scaled down from #{original.width}×#{original.height} to #{stored.width}×#{stored.height}#{as} to fit the site's upload limit"
    ]
  end

  # Marks an image stored as a scaled-down copy.
  defp fitted({:error, _message} = error, _fitted), do: error
  defp fitted(result, nil), do: result
  defp fitted(result, fitted), do: {:fitted, fitted, result}

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
