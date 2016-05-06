defmodule Brando.Images.Utils do
  @moduledoc """
  General utilities pertaining to the Images module
  """

  import Brando.Utils
  import Brando.Gettext
  import Ecto.Query, only: [from: 2]

  alias Brando.{Image, ImageSeries}

  @doc """
  Goes through `image`, which is a model with a :sizes field
  then passing to `delete_media/2` for removal

  ## Example:

      delete_original_and_sized_images(record.cover)

  """
  def delete_original_and_sized_images(nil) do
    nil
  end
  def delete_original_and_sized_images(_) do
    # DEPRECATE
    raise "delete_original_and_sized_images/1 is deprecated, " <>
          "use delete_original_and_sized_images/2 instead"
  end
  def delete_original_and_sized_images(image, key) do
    img = Map.get(image, key)
    if img do
      delete_sized_images(img)
      delete_media(Map.get(img, :path))
    end
    image
  end

  @doc """
  Delete sizes associated with `image`, but keep original.
  """
  def delete_sized_images(nil) do
    nil
  end
  def delete_sized_images(image) do
    sizes = Map.get(image, :sizes)
    for {_size, file} <- sizes do
      delete_media(file)
    end
  end

  @doc """
  Deletes `file` after joining it with `media_path`
  """
  def delete_media(nil), do: nil
  def delete_media(""), do: nil
  def delete_media(file) do
    file = Path.join([Brando.config(:media_path), file])
    File.rm(file)
  end

  @doc """
  Splits `file` with `split_path/1`, adds `size` to the path before
  concatenating it with the filename.

  ## Example

      iex> size_dir("test/dir/filename.jpg", :thumb)
      "test/dir/thumb/filename.jpg"

  """
  def size_dir(file, size) when is_binary(size) do
    {path, filename} = split_path(file)
    Path.join([path, size, filename])
  end

  def size_dir(file, size) when is_atom(size) do
    {path, filename} = split_path(file)
    Path.join([path, Atom.to_string(size), filename])
  end

  @doc """
  Returns image type atom.
  """
  def image_type(%Brando.Type.Image{path: filename}) do
    case String.downcase(Path.extname(filename)) do
      ".jpg" -> :jpeg
      ".jpeg" -> :jpeg
      ".png" -> :png
      ".gif" -> :gif
    end
  end

  @doc """
  Return joined path of `file` and the :media_path config option
  as set in your app's config.exs.
  """
  def media_path do
    Brando.config(:media_path)
  end
  def media_path(nil) do
    Brando.config(:media_path)
  end
  def media_path(file) do
    Path.join([Brando.config(:media_path), file])
  end

  @doc """
  Add `-optimized` between basename and ext of `file`.
  """
  def optimized_filename(file) do
    {path, filename} = split_path(file)
    {basename, ext} = split_filename(filename)
    Path.join([path, "#{basename}-optimized#{ext}"])
  end

  @doc """
  Creates sized images.
  """
  def create_image_sizes({%{uploaded_file: file}, cfg}) do
    {file_path, filename} = split_path(file)
    upload_path = Map.get(cfg, :upload_path)

    sizes = for {size_name, size_cfg} <- Map.get(cfg, :sizes) do
      postfixed_size_dir = Path.join([file_path, to_string(size_name)])
      sized_image = Path.join([postfixed_size_dir, filename])
      sized_path = Path.join([upload_path, to_string(size_name), filename])

      File.mkdir_p(postfixed_size_dir)
      create_image_size(file, sized_image, size_cfg)
      {size_name, sized_path}
    end

    size_struct =
      %Brando.Type.Image{}
      |> Map.put(:sizes, Enum.into(sizes, %{}))
      |> Map.put(:path, Path.join([upload_path, filename]))

    {:ok, size_struct}
  end

  @doc """
  Creates a sized version of `image_src`.
  """
  def create_image_size(image_src, image_dest, size_cfg) do
    image = Mogrify.open(image_src)

    size_cfg =
      if Map.has_key?(size_cfg, "portrait") do
        image_info = Mogrify.verbose(image)
        if String.to_integer(image_info.height) > String.to_integer(image_info.width) do
          size_cfg["portrait"]
        else
          size_cfg["landscape"]
        end
      else
        size_cfg
      end

    modifier = String.ends_with?(size_cfg["size"], ~w(< > ^ % ! @)) && "" || "^"
    fill = size_cfg["fill"] && "-background #{size_cfg["fill"]} " || ""
    crop_string = "#{size_cfg["size"]}#{modifier} #{fill}-gravity center -extent #{size_cfg["size"]}"

    if size_cfg["crop"] do
      image
      |> Mogrify.copy
      |> Mogrify.resize(crop_string)
      |> Mogrify.save(image_dest)
    else
      image
      |> Mogrify.copy
      |> Mogrify.resize(size_cfg["size"])
      |> Mogrify.save(image_dest)
    end
  end

  @doc """
  Deletes all image's sizes and recreates them.
  """
  def recreate_sizes_for(image: img) do
    img = Brando.repo.preload(img, :image_series)
    delete_sized_images(img.image)

    full_path = media_path(img.image.path)

    {:ok, new_image} =
      create_image_sizes({%{uploaded_file: full_path}, img.image_series.cfg})

    image = Map.put(img.image, :sizes, new_image.sizes)

    img
    |> Brando.Image.changeset(:update, %{image: image})
    |> Brando.repo.update!
  end

  @doc """
  Recreates all image sizes in imageseries.
  """
  def recreate_sizes_for(series_id: image_series_id) do
    model = Image

    q =
      from is in ImageSeries,
        preload: :images,
        where: is.id == ^image_series_id

    image_series = Brando.repo.one!(q)
    check_image_paths(model, image_series)

    # reload the series in case we changed the images!
    image_series = Brando.repo.one!(q)

    for image <- image_series.images do
      recreate_sizes_for(image: image)
    end
  end

  @doc """
  Put `size_cfg` as ̀size_key` in `image_series`
  """
  def put_size_cfg(image_series, size_key, size_cfg) do
    image_series = put_in(image_series.cfg.sizes[size_key]["size"], size_cfg)
    Brando.repo.update!(image_series)
    recreate_sizes_for(series_id: image_series.id)
  end

  @doc """
  Delete all images depending on imageserie `series_id`
  """
  def delete_images_for(series_id: series_id) do
    images = Brando.repo.all(
      from i in Image, where: i.image_series_id == ^series_id
    )

    for img <- images do
      delete_original_and_sized_images(img, :image)
      Brando.repo.delete!(img)
    end
  end

  @doc """
  Delete all imageseries dependant on `category_id`
  """
  def delete_series_for(category_id: category_id) do
    image_series = Brando.repo.all(
      from m in ImageSeries,
        where: m.image_category_id == ^category_id
    )

    for is <- image_series do
      delete_images_for(series_id: is.id)
      Brando.repo.delete!(is)
    end
  end

  @doc """
  Create a form from given image configuration `cfg`
  """
  def make_form_from_image_config(cfg) do
    size_rows =
      for {name, cfg} <- cfg.sizes do
        make_row_for_size(name, cfg)
      end

    csrf_token = Phoenix.Controller.get_csrf_token()
    allowed_mimetypes = Map.get(cfg, :allowed_mimetypes) |> Enum.join(", ")
    """
    <form accept-charset="UTF-8" class="grid-form" method="post" role="form">
      <input name="_method" type="hidden" value="patch">
      <input name="_csrf_token" type="hidden" value="#{csrf_token}">
      <input name="_utf8" type="hidden" value="✓">
      <div class="form-row">
        <div class="form-group required no-height">
          <label for="config[cfg]">#{gettext("Allowed mimetypes")}</label>
          <input type="text" name="config[allowed_mimetypes]"
                 value="#{allowed_mimetypes}">
        </div>
        <div class="form-group required no-height">
          <label for="config[cfg]">#{gettext("Default size")}</label>
          <input type="text" name="config[default_size]" value="#{Map.get(cfg, :default_size)}">
        </div>
        <div class="form-group required no-height">
          <label for="config[cfg]">#{gettext("Random filename")}</label>
          <input type="checkbox" name="config[random_filename]" value="#{Map.get(cfg, :random_filename)}">
        </div>
        <div class="form-group required no-height">
          <label for="config[cfg]">#{gettext("Size limit")}</label>
          <input type="text" name="config[size_limit]" value="#{Map.get(cfg, :size_limit)}">
        </div>
      </div>
      <div class="form-row">
        <div class="form-group required no-height">
          <label for="config[cfg]">#{gettext("Upload path")}</label>
          <input type="text" name="config[upload_path]" value="#{Map.get(cfg, :upload_path)}">
        </div>
      </div>
      #{size_rows}
      <div class="form-row">
        <button class="m-t-sm m-b-sm btn btn-default add-masterkey-standard">
          #{gettext("Add master key (standard)")}
        </button>
        <button class="m-t-sm m-b-sm m-l-sm btn btn-default add-masterkey-pl">
          #{gettext("Add master key (portrait/landscape)")}
        </button>
      </div>
      <div class="form-row">
        <div class="form-group required">
          <input class="btn btn-success"
                 name="config[submit]"
                 type="submit"
                 value="#{gettext("Save")}">
        </div>
      </div>
    </form>
    """ |> Phoenix.HTML.raw
  end

  defp make_row_for_size(name, cfg) do
    {type, inputs} =
      if Map.has_key?(cfg, "landscape") do
        i = for {k, v} <- cfg do
          make_recursive_input_for(k, v, name, cfg)
        end
        {:recursive, i}
      else
        i = for {k, v} <- cfg do
          make_input_for({k, v}, name, cfg, :standard)
        end
        {:standard, i}
      end

    masterkey_type = "#{type}-masterkey-input"

    add_button =
      if type == :standard do
        """
        <div class="form-row">
          <span class="m-t-sm m-b-sm btn btn-xs btn-block add-key-standard">
            <i class="fa fa-plus-circle"></i>
          </span>
        </div>
        """
      else
        ""
      end

    """
    <fieldset>
      <legend>
        <br />
        #{gettext("key")}
        <span class="btn btn-xs delete-key">
          <i class="fa fa-fw fa-ban"></i>
        </span>
      </legend>
      <div class="form-row">
        <div class="form-group required no-height">
          <label>#{gettext("masterkey")}</label>
          <input type="text" class="#{masterkey_type}" value="#{name}">
        </div>
      </div>

      #{inputs}
      #{add_button}

    </fieldset>
    """
  end

  defp make_recursive_input_for(orientation, cfg_map, name, _) do
    inputs =
      for {k, v} <- cfg_map do
        make_input_for({k, v}, name, cfg_map, orientation)
      end

    """
    <fieldset>
      <legend>
      <br />
        #{gettext("Orientation")}: #{orientation}
      </legend>

      #{inputs}

      <div class="form-row">
        <span data-orientation="#{orientation}"
              class="m-t-sm m-b-sm btn btn-xs btn-block add-key-recursive">
          <i class="fa fa-plus-circle"></i>
        </span>
      </div>
    </fieldset>
    """
  end

  defp make_input_for({k, v}, name, _, modifier) do
    actual_value =
      if modifier == :standard do
        """
        <input type="hidden"
               class="actual-value"
               name="sizes[#{name}][#{k}]"
               value="#{v}">
        """
      else
        """
        <input type="hidden"
               class="actual-value orientation-value"
               name="sizes[#{name}][#{modifier}][#{k}]"
               value="#{v}">
        """
      end

    class_modifier =
      if modifier == :standard do
        "standard"
      else
        "recursive"
      end

    """
    <div class="form-row">
      <div class="form-group required no-height">
        <label>
          Key
          <span class="btn btn-xs delete-subkey">
            <i class="fa fa-fw fa-ban"></i>
          </span>
        </label>
        <input type="text" class="#{class_modifier}-key-input" value="#{k}">
      </div>
      <div class="form-group required no-height">
        <label>Value</label>
        <input type="text" class="#{class_modifier}-val-input" value="#{v}">
      </div>
      #{actual_value}
    </div>
    """
  end

  @doc """
  Converts some of the values to proper types.
  Textual representation of boolean -> bool, etc.
  """
  def fix_size_cfg_vals(sizes) do
    Enum.reduce(sizes, %{}, fn({key, val}, acc) ->
      {key, val} = convert_value(key, val)
      Map.put(acc, key, val)
    end)
  end

  defp convert_value(key, val) when is_map(val) do
    {key, fix_size_cfg_vals(val)}
  end

  defp convert_value(key, val) do
    val = case key do
      "crop"    -> val == "true" && true || false
      "quality" -> String.to_integer(val)
      _         -> val
    end
    {key, val}
  end

  @doc """
  Checks that the existing images' path matches the config. these may differ
  when series has been renamed!
  """
  def check_image_paths(model, image_series) do
    upload_path = image_series.cfg.upload_path

    for image <- image_series.images do
      check_image_path(model, image, upload_path)
    end
  end

  defp check_image_path(model, image, upload_dirname) do
    image_path = image.image.path
    image_dirname = Path.dirname(image.image.path)
    image_basename = Path.basename(image.image.path)

    img_struct =
      do_check_image_path(image, image_path, image_dirname, image_basename, upload_dirname)

    if img_struct != nil do
      # store new image
      image
      |> model.changeset(:update, %{image: img_struct})
      |> Brando.repo.update!
    end
  end

  defp do_check_image_path(_, _, ".", _, _) do
    # something is wrong, just return nil and don't move anything
    nil
  end

  defp do_check_image_path(image, image_path, image_dirname, image_basename, upload_dirname) do
    media_path = Path.expand(Brando.config(:media_path))
    if image_dirname != upload_dirname do
      File.mkdir_p(Path.join(media_path, upload_dirname))
      File.cp(Path.join(media_path, image_path),
              Path.join([media_path, upload_dirname, image_basename]))

      Map.put(image.image, :path, Path.join(upload_dirname, image_basename))
    else
      nil
    end
  end

  @doc """
  Gets orphaned image_series.
  """
  def get_orphaned_series(categories, series, opts) do
    starts_with = Keyword.fetch!(opts, :starts_with)
    ignored_paths = Keyword.get(opts, :ignored_paths, [])
    media_path = Path.expand(Brando.config(:media_path))

    series_paths = Enum.map(series, &Path.join(media_path, &1.cfg.upload_path))
    category_paths = Enum.map(categories, &Path.join(media_path, &1.cfg.upload_path))

    upload_paths = series_paths ++ category_paths

    if upload_paths != [] do
      path_to_check = Path.join(media_path, starts_with)
      full_ignored_paths = Enum.map(ignored_paths, &(Path.join(path_to_check, &1)))

      existing_category_paths =
        path_to_check
        |> Path.join("*")
        |> Path.wildcard
        |> Enum.filter(&(!&1 in full_ignored_paths))

      existing_series_paths =
        existing_category_paths
        |> Enum.map(&Path.wildcard(Path.join(&1, "*")))
        |> List.flatten

      existing_paths = existing_series_paths ++ existing_category_paths

      existing_paths -- upload_paths
    else
      []
    end
  end
end
