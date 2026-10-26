defmodule Brando.Images.Adoption do
  @moduledoc """
  Records the config of images that were processed before Brando stored one,
  when their files already match it.

  Since 0.55 each processed image stores `config_fingerprint`, a fingerprint
  of the `sizes` and `formats` it was made with (see
  `Brando.Type.ImageConfig.fingerprint/1`), so only the images whose config
  changed need recreating. Images processed earlier have none and count as
  changed. Most of them were made with the config they have today, and
  recreating a whole library to find that out is wasted work. Adopting an
  image checks its stored files against its current config instead, and when
  they match writes the current fingerprint and nothing else.

  An image matches when, with nothing decoded or rewritten:

    * its `formats` are the formats the config produces for it (`:original`
      is the original's own type, and a GIF's is WebP);
    * its `sizes` have exactly the config's size keys;
    * each size exists in each format in the media folder;
    * each size's pixel dimensions, read from the file's header, are what one
      of Brando's processors made of the original with its spec, within a
      pixel for rounding:
      * today's: scaled to the width, the height or to fit the box, or
        cropped to the geometry, and never enlarged (see
        `Brando.Images.Size`);
      * the first libvips processor, on the 0.55 line from March to October
        2026 before its release: fitted a width alone inside a square of that
        width, and enlarged smaller originals, cropped or not;
      * the sharp-based processor of 0.54 and earlier: fitted to the width
        and never enlarged an uncropped size.

      Originals rotated by their EXIF orientation match too.

  Quality and other encoder settings are not in a file's header, so a size
  whose `"quality"` changed while its geometry didn't is adopted with the
  new config. Nor is the crop's position: a focal point moved since is not
  seen. Recreate those images (Utilities → Recreate image sizes) when that
  matters.

  An image that doesn't match keeps no fingerprint and stays among the images
  to recreate. One whose files can't be read here is skipped and stays there
  too: its target no longer resolves to a config, or it is on the CDN without
  a local copy (`keep_local_copy: false`).

  `mix brando.images.adopt` adopts the images of every environment, and
  Utilities → Recreate changed images adopts before it recreates.
  """

  import Ecto.Query

  alias Brando.Images
  alias Brando.Images.Operations.Sizing
  alias Brando.Images.Processing
  alias Brando.Images.Size
  alias Brando.Tenant.Storage

  @typedoc """
  What `check/3` found. A difference names what differs:

    * `{:formats, has, config}` - the image's formats and the config's;
    * `{:size_keys, missing, extra}` - the config's size keys the image lacks,
      and the image's keys the config no longer has;
    * `{:missing, key, file}` - a size's file is missing: `file` is its path
      in the media folder;
    * `{:dimensions, key, actual, config}` - a size's `{width, height}` and
      what processing makes of the original with today's spec; either is
      `nil` when it can't be read or worked out;
    * `{:error, message}` - the check raised.
  """
  @type verdict :: :match | {:differ, reason :: term} | {:skipped, reason :: term}
  @type counts :: %{adopted: non_neg_integer, differ: non_neg_integer, skipped: non_neg_integer}

  @type difference :: :formats | :sizes | :missing_file | :dimensions | :error | :cdn | :no_config

  @batch_size 500
  # Images whose files `media_status/0` looks for.
  @media_sample 20
  # Resizing rounds each side, so a size may be a pixel off its spec.
  @tolerance 1
  # Header reads are cheapest for these; AVIF goes through libheif.
  @format_preference [:jpg, :png, :webp, :gif, :avif, :svg]

  @doc """
  Adopts the images in the current environment that were processed before
  Brando recorded configs, when their files match their current config.

  Walks the images in batches and is safe to run again. Returns how many were
  adopted, how many differ from their config (to recreate) and how many
  couldn't be checked.

  ## Options

    * `:dry_run` - count only, and write nothing. `adopted` is then the number
      that would be adopted.
    * `:check` - `:files` (the default) checks the files as described in the
      moduledoc. `:records` compares formats and size keys only, which reads
      no files; a match is then only likely.
    * `:batch_size` - images per batch (default #{@batch_size}).
    * `:on_differ` - called with `image` and the verdict of each image that
      differs or is skipped.
  """
  @spec adopt_unrecorded(keyword) :: counts
  def adopt_unrecorded(opts \\ []) do
    opts
    |> by_target()
    |> Map.values()
    |> Enum.reduce(empty_counts(), &sum_counts/2)
  end

  @doc """
  `adopt_unrecorded/1`, by config target: `%{config_target => counts}`.
  """
  @spec by_target(keyword) :: %{String.t() => counts}
  def by_target(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)

    0
    |> Stream.unfold(fn
      nil ->
        nil

      after_id ->
        case unrecorded_batch(after_id, batch_size) do
          [] -> nil
          images -> {images, next_cursor(images, batch_size)}
        end
    end)
    |> Enum.reduce(%{}, fn images, acc ->
      images
      |> run_batch(opts)
      |> Map.merge(acc, fn _target, a, b -> sum_counts(a, b) end)
    end)
  end

  @doc """
  Sorts `images` by their current config: those that match are adopted
  (unless `dry_run: true`), and the rest returned for recreating.

  Takes the same `:check`, `:dry_run` and `:on_differ` options as
  `adopt_unrecorded/1`, and returns `{adopted, rest}`. Images that already
  have a fingerprint are left alone and returned in `rest`.
  """
  @spec adopt([Images.Image.t()], keyword) :: {adopted :: [Images.Image.t()], rest :: [Images.Image.t()]}
  def adopt(images, opts \\ []) do
    {unrecorded, recorded} = Enum.split_with(images, &is_nil(&1.config_fingerprint))
    verdicts = verdicts(unrecorded, opts)
    {matching, rest} = Enum.split_with(verdicts, fn {_image, _fingerprint, verdict} -> verdict == :match end)

    if !Keyword.get(opts, :dry_run, false), do: write_fingerprints(matching)

    {Enum.map(matching, &elem(&1, 0)), Enum.map(rest, &elem(&1, 0)) ++ recorded}
  end

  @doc """
  Does `image`'s processed output match `config`? See the moduledoc for what
  is compared. `check: :records` compares formats and size keys only.
  """
  @spec check(Images.Image.t(), Brando.Type.ImageConfig.t(), keyword) :: verdict
  def check(image, config, opts \\ []) do
    with :ok <- same_formats(image, config),
         :ok <- same_size_keys(image, config) do
      if Keyword.get(opts, :check, :files) == :records,
        do: :match,
        else: check_files(image, config)
    end
  end

  @doc """
  What kind of difference a verdict from `check/3` (or `adopt_unrecorded/1`'s
  `:on_differ`) names, for counting them: `:formats` and `:sizes` (the size
  keys) are differences in the config, `:missing_file` and `:dimensions` in
  the files. Skipped images give their reason, `:cdn` or `:no_config`.
  """
  @spec difference(verdict) :: difference | nil
  def difference({:differ, {:formats, _has, _config}}), do: :formats
  def difference({:differ, {:size_keys, _missing, _extra}}), do: :sizes
  def difference({:differ, {:missing, _key, _file}}), do: :missing_file
  def difference({:differ, {:dimensions, _key, _actual, _config}}), do: :dimensions
  def difference({:differ, {:error, _message}}), do: :error
  def difference({:skipped, reason}) when reason in [:cdn, :no_config], do: reason
  def difference(_verdict), do: nil

  @doc "Whether the current environment has images `adopt_unrecorded/1` would check."
  @spec unrecorded?() :: boolean
  def unrecorded? do
    query =
      from i in Images.Image,
        where: is_nil(i.config_fingerprint) and is_nil(i.deleted_at) and not is_nil(i.config_target),
        select: true,
        limit: 1

    Brando.Repo.one(query) == true
  end

  @doc """
  Whether the current environment's media folder holds its images' files.

  Looks for the files, original or size, of #{@media_sample} images picked at
  random among those kept locally (not on the CDN without a local copy), and
  when none of them has one, for any file in the folders the images live in.
  `{:empty, media_root}` when there is none either: the folder is empty or
  not mounted, or the media was never synced to this machine. Every image
  then differs for want of its files, and recreating them needs the
  originals, so neither the counts nor a recreate mean anything until the
  media is in place. `:ok` otherwise, and when there are no such images.
  """
  @spec media_status() :: :ok | {:empty, String.t()}
  def media_status do
    local =
      from i in Images.Image, where: is_nil(i.deleted_at) and not is_nil(i.path) and (is_nil(i.cdn) or i.cdn == false)

    sample =
      Brando.Repo.all(from i in local, order_by: fragment("random()"), limit: @media_sample, select: {i.path, i.sizes})

    cond do
      sample == [] -> :ok
      Enum.any?(sample, &any_file?/1) -> :ok
      local |> image_folders() |> Enum.any?(&files_in?/1) -> :ok
      true -> {:empty, Images.Utils.media_path()}
    end
  end

  defp any_file?({path, sizes}) do
    size_paths = if is_map(sizes), do: Enum.filter(Map.values(sizes), &is_binary/1), else: []
    Enum.any?([path | size_paths], &local_exists?/1)
  end

  # The folders the originals are in: a sample can miss the few images whose
  # files are there.
  defp image_folders(query) do
    Brando.Repo.all(
      from i in query,
        distinct: true,
        limit: 1_000,
        select: fragment("substring(? from '^(.*)/[^/]*$')", i.path)
    )
  end

  defp files_in?(nil), do: false

  defp files_in?(folder) do
    with {:ok, dir} <- Storage.media_file(folder),
         {:ok, [_ | _]} <- File.ls(dir) do
      true
    else
      _ -> false
    end
  end

  # A path that leaves the media root counts as missing
  defp local_exists?(path) do
    case Storage.media_file(path) do
      {:ok, file} -> File.exists?(file)
      :error -> false
    end
  end

  defp unrecorded_batch(after_id, batch_size) do
    Brando.Repo.all(
      from i in Images.Image,
        where:
          i.id > ^after_id and is_nil(i.config_fingerprint) and is_nil(i.deleted_at) and
            not is_nil(i.config_target),
        order_by: [asc: i.id],
        limit: ^batch_size,
        select: struct(i, [:id, :path, :width, :height, :sizes, :formats, :config_target, :config_fingerprint, :cdn])
    )
  end

  # Only a full batch may have more after it.
  defp next_cursor(images, batch_size) do
    case Enum.at(images, batch_size - 1) do
      nil -> nil
      last -> last.id
    end
  end

  defp run_batch(images, opts) do
    verdicts = verdicts(images, opts)
    if !Keyword.get(opts, :dry_run, false), do: write_fingerprints(Enum.filter(verdicts, &(elem(&1, 2) == :match)))

    Enum.reduce(verdicts, %{}, fn {image, _fingerprint, verdict}, acc ->
      key =
        case verdict do
          :match -> :adopted
          {:differ, _reason} -> :differ
          {:skipped, _reason} -> :skipped
        end

      Map.update(acc, image.config_target, Map.put(empty_counts(), key, 1), &Map.update!(&1, key, fn n -> n + 1 end))
    end)
  end

  # `[{image, current_fingerprint, verdict}]`, resolving each target's config once.
  defp verdicts(images, opts) do
    on_differ = Keyword.get(opts, :on_differ)

    configs =
      images
      |> Enum.map(& &1.config_target)
      |> Enum.uniq()
      |> Map.new(&{&1, Processing.current_config(&1)})

    check = fn image ->
      case configs[image.config_target] do
        {:ok, config, fingerprint} -> {image, fingerprint, safe_check(image, config, opts)}
        :error -> {image, nil, {:skipped, :no_config}}
      end
    end

    # Reading headers waits on the disk more than the CPU, so a few run at
    # once: about three times faster than one by one.
    images
    |> Task.async_stream(Brando.Tenant.capture_context(check),
      max_concurrency: min(System.schedulers_online(), 8),
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, {image, _fingerprint, verdict} = result} ->
      if on_differ && verdict != :match, do: on_differ.(image, verdict)
      result
    end)
  end

  # One image's odd record (a size that isn't a path, an unreadable file)
  # must not stop the rest: it differs, and is recreated.
  defp safe_check(image, config, opts) do
    check(image, config, opts)
  rescue
    error -> {:differ, {:error, Exception.message(error)}}
  end

  # Only images still without a fingerprint: one processed meanwhile keeps
  # the fingerprint processing gave it.
  defp write_fingerprints(matching) do
    matching
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0).id)
    |> Enum.each(fn {fingerprint, ids} ->
      Brando.Repo.update_all(
        from(i in Images.Image, where: i.id in ^ids and is_nil(i.config_fingerprint)),
        set: [config_fingerprint: fingerprint]
      )
    end)
  end

  defp same_formats(%{path: path, formats: formats}, config) when is_binary(path) and is_list(formats) do
    expected = Images.get_processed_formats(path, config.formats)
    if Enum.sort(formats) == Enum.sort(expected), do: :ok, else: {:differ, {:formats, formats, expected}}
  end

  defp same_formats(image, config), do: {:differ, {:formats, image.formats, config.formats}}

  defp same_size_keys(%{sizes: sizes}, %{sizes: config_sizes}) when is_map(sizes) and is_map(config_sizes) do
    keys = fn map -> map |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort() end
    {has, expected} = {keys.(sizes), keys.(config_sizes)}

    if has == expected,
      do: :ok,
      else: {:differ, {:size_keys, expected -- has, has -- expected}}
  end

  defp same_size_keys(image, config) do
    keys = fn map -> if is_map(map), do: map |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(), else: [] end
    {:differ, {:size_keys, keys.(config.sizes) -- keys.(image.sizes), keys.(image.sizes) -- keys.(config.sizes)}}
  end

  defp check_files(image, config) do
    header_format = Enum.min_by(image.formats, &(Enum.find_index(@format_preference, fn f -> f == &1 end) || 99))

    image.sizes
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn {key, path}, :ok ->
      case check_size(image, key, path, config.sizes[key], header_format) do
        :ok -> {:cont, :ok}
        other -> {:halt, other}
      end
    end)
    |> case do
      :ok -> :match
      other -> other
    end
  end

  defp check_size(image, key, path, size_cfg, header_format) when is_binary(path) do
    files = Map.new(image.formats, &{&1, Brando.Utils.change_extension(path, to_string(&1))})
    missing = Enum.find(image.formats, &(not File.exists?(Images.Utils.media_path(files[&1]))))

    cond do
      is_nil(missing) ->
        check_dimensions(image, key, Images.Utils.media_path(files[header_format]), size_cfg, header_format)

      image.cdn ->
        {:skipped, :cdn}

      true ->
        {:differ, {:missing, key, files[missing]}}
    end
  end

  defp check_size(_image, key, _path, _size_cfg, _header_format), do: {:differ, {:missing, key, nil}}

  # An SVG's sizes are the original itself.
  defp check_dimensions(_image, _key, _file, _size_cfg, :svg), do: :ok

  defp check_dimensions(image, key, file, size_cfg, _format) do
    with {:ok, original} <- original_dimensions(image),
         {:ok, actual} <- header_dimensions(file) do
      dimensions_verdict(key, size_cfg, original, actual)
    else
      _ -> {:differ, {:dimensions, key, nil, nil}}
    end
  end

  defp dimensions_verdict(key, size_cfg, original, actual) do
    if Enum.any?(candidates(size_cfg, original), fn {spec, dimensions} -> fits?(spec, dimensions, actual) end),
      do: :ok,
      else: {:differ, {:dimensions, key, actual, processed_dimensions(size_cfg, original)}}
  end

  # What processing makes of the original today, for saying what was expected.
  defp processed_dimensions(size_cfg, original) do
    Sizing.processed_dimensions(size_cfg, original)
  rescue
    _error -> nil
  end

  defp original_dimensions(%{width: width, height: height})
       when is_integer(width) and is_integer(height) and width > 0 and height > 0,
       do: {:ok, {width, height}}

  defp original_dimensions(%{path: path}), do: header_dimensions(Images.Utils.media_path(path))

  # Opens lazily: libvips reads the header, not the pixels.
  defp header_dimensions(file) do
    case Image.open(file, access: :sequential) do
      {:ok, image} -> {:ok, {Image.width(image), Image.height(image)}}
      {:error, _reason} -> :error
    end
  end

  defp swap({width, height}), do: {height, width}

  # The spec and the dimensions processing may have worked from. Every
  # processor makes the image upright by its EXIF orientation; processing
  # today also picks a portrait or landscape spec, and crops, by the upright
  # dimensions, where the older ones went by the stored ones.
  defp candidates(size_cfg, original) do
    upright = swap(original)

    Enum.uniq([
      {spec(size_cfg, original), original},
      {spec(size_cfg, original), upright},
      {spec(size_cfg, upright), upright}
    ])
  end

  defp spec(size_cfg, {width, height}), do: Sizing.get_size_cfg_orientation(size_cfg, width, height)

  defp fits?(%{"size" => geometry} = spec, original, actual) do
    case Size.dimensions(geometry) do
      {:ok, box} -> if spec["crop"] == true, do: cropped?(spec, original, actual), else: scaled?(box, original, actual)
      :error -> false
    end
  rescue
    _error -> false
  end

  defp fits?(_spec, _original, _actual), do: false

  # Resized to cover the crop, then cut to it. Processing cuts the largest
  # crop a smaller original holds, at the crop's proportions; the first
  # libvips processor enlarged the original to cover the crop instead. A
  # crop cut down to a smaller original's size is accepted as before.
  defp cropped?(spec, {width, height} = original, actual) do
    {crop_width, crop_height} = crop = Sizing.get_crop_dimensions_from_cfg(spec)

    close?(actual, Sizing.fit_crop(crop, original)) or close?(actual, crop) or
      close?(actual, {min(crop_width, width), min(crop_height, height)})
  end

  # Scaled to the geometry, keeping the aspect ratio. Processing scales to a
  # width or a height alone, or fits a box, and never enlarges, as sharp did;
  # the first libvips processor fitted a width alone into a square and
  # enlarged smaller originals.
  defp scaled?({box_width, box_height}, {width, height} = original, actual) do
    scales =
      Enum.reject(
        [
          box_width && min(box_width / width, (box_height || box_width) / height),
          box_width && box_height && min(box_width / width, box_height / height),
          box_width && is_nil(box_height) && box_width / width,
          is_nil(box_width) && box_height && box_height / height
        ],
        &(&1 in [nil, false])
      )

    Enum.any?(scales ++ Enum.map(scales, &min(&1, 1.0)), &close?(actual, scaled(original, &1)))
  end

  defp scaled({width, height}, scale), do: {round(width * scale), round(height * scale)}

  defp close?({width, height}, {expected_width, expected_height}),
    do: abs(width - expected_width) <= @tolerance and abs(height - expected_height) <= @tolerance

  defp empty_counts, do: %{adopted: 0, differ: 0, skipped: 0}

  defp sum_counts(a, b), do: Map.merge(a, b, fn _key, x, y -> x + y end)
end
