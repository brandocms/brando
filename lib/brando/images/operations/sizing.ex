defmodule Brando.Images.Operations.Sizing do
  @moduledoc """
  Sizing operations
  """
  import Brando.Gettext
  alias Brando.Images
  alias Brando.Images.Focal
  alias BrandoAdmin.Progress

  @doc """
  Get processor module from config and call process function
  """
  def delegate_processor(conversion_parameters) do
    # grab processor module
    module = Brando.config(Brando.Images)[:processor_module] || Brando.Images.Processor.Sharp
    apply(module, :process_image, [conversion_parameters])
  end

  @doc """
  Create a sized version of image
  """
  def create_image_size(%Images.Operation{
        id: id,
        type: :gif,
        image_struct: %{path: image_src, width: width, height: height},
        sized_image_path: image_dest,
        sized_image_dir: image_dest_dir,
        size_key: size_key,
        size_cfg: size_cfg
      }) do
    image_src_path = Images.Utils.media_path(image_src)
    image_dest_path = Images.Utils.media_path(image_dest)
    image_dest_dir = Images.Utils.media_path(image_dest_dir)

    File.mkdir_p!(image_dest_dir)

    size_cfg = get_size_cfg_orientation(size_cfg, height, width)

    # This is slightly dumb, but should be enough. If we crop, we always pass WxH.
    # If we don't, we always pass W or xH.
    {crop, modifier, size} =
      if size_cfg["crop"] do
        size_coords = String.replace(size_cfg["size"], "x", ",")
        {"--crop 0,0-#{size_coords}", "--resize", size_cfg["size"]}
      else
        modifier =
          (String.contains?(size_cfg["size"], "x") && "--resize-fit-height") ||
            "--resize-fit-width"

        size = String.replace(size_cfg["size"], ~r/x|\^|\!|\>|\<|\%/, "")
        {"", modifier, size}
      end

    params = ~w(#{crop} #{modifier} #{size} --output #{image_dest_path} -i #{image_src_path})

    Images.Processor.Commands.delegate("gifsicle", params, stderr_to_stdout: true)

    {:ok,
     %Images.TransformResult{
       id: id,
       size_key: size_key,
       image_path: image_dest,
       cmd_params: Enum.join(params, " ")
     }}
  end

  def create_image_size(%Images.Operation{
        type: type,
        id: id,
        total_operations: total_operations,
        operation_index: operation_index,
        image_struct: %{
          path: image_src,
          focal: focal,
          width: width,
          height: height
        },
        filename: filename,
        sized_image_path: image_dest,
        sized_image_dir: image_dest_dir,
        size_key: size_key,
        size_cfg: size_cfg,
        user: user
      }) do
    format = maybe_change_format(type)
    image_src_path = Images.Utils.media_path(image_src)
    image_dest_path = Images.Utils.media_path(image_dest)
    image_dest_dir = Images.Utils.media_path(image_dest_dir)

    File.mkdir_p!(image_dest_dir)

    {width, height} = ensure_dims(width, height, image_src_path)

    conversion_parameters = %Images.ConversionParameters{
      id: id,
      size_key: size_key,
      image_src_path: image_src_path,
      image_dest_path: image_dest_path,
      image_dest_rel_path: image_dest,
      original_width: width,
      original_height: height,
      format: format
    }

    case image_src_exists(conversion_parameters) do
      {:ok, {:image, :exists}} ->
        if operation_index == 1, do: set_progress(conversion_parameters, 0, filename, user)

        result =
          conversion_parameters
          |> add_size_cfg(size_cfg)
          |> add_quality()
          |> add_focal_point(focal)
          |> add_crop_flag()
          |> add_crop_dimensions()
          |> add_resize_dimensions()
          |> add_anchor()
          |> add_values()
          |> delegate_processor()

        progress_percent = operation_index / total_operations * 100
        set_progress(conversion_parameters, progress_percent, filename, user)

        result

      {:error, {:image, :not_found}} ->
        {:error, {:create_image_size, {:file_not_found, conversion_parameters.image_src_path}}}
    end
  end

  defp ensure_dims(width, height, img_path) when is_nil(width) or is_nil(height) do
    case Fastimage.size(img_path) do
      {:ok, %{width: width, height: height}} ->
        {width, height}

      {:error, _} ->
        {0, 0}
    end
  end

  defp ensure_dims(w, h, _), do: {w, h}

  @doc """
  Check if `image_src_path` exists
  """
  def image_src_exists(%Images.ConversionParameters{image_src_path: src}) do
    case File.exists?(src) do
      true -> {:ok, {:image, :exists}}
      false -> {:error, {:image, :not_found}}
    end
  end

  @doc """
  Convert and add focal point to conversion parameters
  """
  def add_focal_point(conversion_parameters, nil) do
    Map.put(conversion_parameters, :focal_point, %Focal{})
  end

  def add_focal_point(conversion_parameters, focal) do
    focal =
      focal
      |> Map.put(:x, (is_binary(focal.x) && String.to_integer(focal.x)) || focal.x)
      |> Map.put(:y, (is_binary(focal.y) && String.to_integer(focal.y)) || focal.y)

    Map.put(conversion_parameters, :focal_point, focal)
  end

  @doc """
  Add size cfg to conversion parameters
  """
  def add_size_cfg(
        %{original_width: width, original_height: height} = conversion_parameters,
        size_cfg
      ) do
    Map.put(conversion_parameters, :size_cfg, get_size_cfg_orientation(size_cfg, height, width))
  end

  @doc """
  Add crop flag to conversion parameters
  """
  def add_crop_flag(%{size_cfg: %{"crop" => crop}} = conversion_parameters) do
    Map.put(conversion_parameters, :crop, crop)
  end

  def add_crop_flag(%{size_cfg: _} = conversion_parameters) do
    Map.put(conversion_parameters, :crop, false)
  end

  @doc """
  Add quality setting to conversion parameters. Falls back to 100 (max quality)
  """
  def add_quality(%{size_cfg: size_cfg} = conversion_parameters) do
    quality = Map.get(size_cfg, "quality", "100")
    Map.put(conversion_parameters, :quality, quality)
  end

  @doc """
  Add extracted crop dimensions to conversion parameters
  """
  def add_crop_dimensions(%{crop: true, size_cfg: size_cfg} = conversion_parameters) do
    {crop_width, crop_height} = get_crop_dimensions_from_cfg(size_cfg)

    conversion_parameters
    |> Map.put(:crop_width, crop_width)
    |> Map.put(:crop_height, crop_height)
  end

  def add_crop_dimensions(%{crop: false} = conversion_parameters) do
    conversion_parameters
  end

  @doc """
  Calculate resize dimension while keeping aspect ratio and add to conversion parameters
  """
  def add_resize_dimensions(
        %{
          crop: true,
          crop_width: crop_width,
          crop_height: crop_height,
          original_width: original_width,
          original_height: original_height
        } = conversion_parameters
      ) do
    {resize_width, resize_height} =
      if crop_width > crop_height do
        resize_width = crop_width
        resize_height = round(crop_width * original_height / original_width)

        if resize_height < crop_height do
          resize_width = round(crop_height * resize_width / resize_height)
          resize_height = crop_height

          {resize_width, resize_height}
        else
          {resize_width, resize_height}
        end
      else
        resize_width = round(crop_height * original_width / original_height)
        resize_height = crop_height

        if resize_width < crop_width do
          resize_height = round(crop_width * resize_height / resize_width)
          resize_width = crop_width

          {resize_width, resize_height}
        else
          {resize_width, resize_height}
        end
      end

    conversion_parameters
    |> Map.put(:resize_width, round(resize_width / 1))
    |> Map.put(:resize_height, round(resize_height / 1))
  end

  def add_resize_dimensions(%{crop: false} = params), do: params

  @doc """
  Add size values to parameters

  Add resize and crop values to conversion parameters if `crop` is true
  Add resize geometry from size config to conversion parameters if `crop` is false
  """
  def add_values(
        %{
          crop: true,
          anchor: anchor,
          resize_width: resize_width,
          resize_height: resize_height,
          crop_width: crop_width,
          crop_height: crop_height
        } = conversion_parameters
      ) do
    crop_values = %{
      width: crop_width,
      height: crop_height,
      top: anchor.y,
      left: anchor.x
    }

    resize_values = %{
      width: resize_width,
      height: resize_height
    }

    conversion_parameters
    |> Map.put(:resize_values, resize_values)
    |> Map.put(:crop_values, crop_values)
  end

  def add_values(%{crop: false, size_cfg: %{"size" => resize_geography}} = conversion_parameters) do
    resize_values =
      resize_geography
      |> String.replace(~r/\^|\!|\>|\<|\%/, "")
      |> String.split("x")
      |> case do
        ["", target_height] ->
          %{height: String.to_integer(target_height)}

        [target_width, ""] ->
          %{width: String.to_integer(target_width)}

        [target_width, target_height] ->
          %{
            width: String.to_integer(target_width),
            height: String.to_integer(target_height)
          }

        [target_width] ->
          %{width: String.to_integer(target_width)}
      end

    Map.put(conversion_parameters, :resize_values, resize_values)
  end

  @doc """
  Add anchor for cropping by focal point to conversion parameters
  """
  def add_anchor(
        %{
          crop: true
        } = conversion_parameters
      ) do
    conversion_parameters
    |> get_original_focal_point()
    |> transform_focal_point()
    |> calculate_anchor()
  end

  def add_anchor(%{crop: false} = conversion_parameters), do: conversion_parameters

  @doc """
  Calculate anchor
  """
  def calculate_anchor(
        %{
          transformed_focal_point: transformed_focal_point,
          resize_width: resize_width,
          resize_height: resize_height,
          crop_width: crop_width,
          crop_height: crop_height
        } = conversion_parameters
      ) do
    anchor = %{
      x: round(transformed_focal_point.x - crop_width / 2),
      y: round(transformed_focal_point.y - crop_height / 2)
    }

    anchor = %{
      x: (anchor.x + crop_width <= resize_width && anchor.x) || resize_width - crop_width,
      y: (anchor.y + crop_height <= resize_height && anchor.y) || resize_height - crop_height
    }

    # Ensure that the crop area doesn't fall off the top left of the image.
    anchor = %{
      x: max(0, anchor.x),
      y: max(0, anchor.y)
    }

    Map.put(conversion_parameters, :anchor, anchor)
  end

  @doc """
  Get pixel X and Y of focal point and add to conversion parameters
  """
  def get_original_focal_point(
        %{
          focal_point: focal,
          original_width: original_width,
          original_height: original_height
        } = conversion_parameters
      ) do
    original_focal_point = %{
      x: round(focal.x / 1 / 100 * original_width / 1),
      y: round(focal.y / 1 / 100 * original_height / 1)
    }

    Map.put(conversion_parameters, :original_focal_point, original_focal_point)
  end

  @doc """
  Transform original focal point to a scaled version fitting the resized image dimensions,
  then add to conversion parameters
  """
  def transform_focal_point(
        %{
          original_focal_point: original_focal_point,
          original_width: original_width,
          original_height: original_height,
          resize_width: resize_width,
          resize_height: resize_height
        } = conversion_parameters
      ) do
    transformed_focal_point = %{
      x: round(original_focal_point.x / 1 / (original_width / 1) * resize_width / 1),
      y: round(original_focal_point.y / 1 / (original_height / 1) * resize_height / 1)
    }

    Map.put(conversion_parameters, :transformed_focal_point, transformed_focal_point)
  end

  @doc """
  Get correct size config according to the image's orientation
  """
  def get_size_cfg_orientation(size_cfg, width, height) do
    if Map.has_key?(size_cfg, "portrait") do
      if height > width do
        size_cfg["portrait"]
      else
        size_cfg["landscape"]
      end
    else
      size_cfg
    end
  end

  @doc """
  Extract crop dimensions from image config as a tuple of integers

  If one of the dimensions is missing, look for `ratio` key and calculate
  missing dimension.
  """
  def get_crop_dimensions_from_cfg(cfg) do
    cleaned_size_string = String.replace(cfg["size"], ~r/\^|\!|\>|\<|\%/, "")

    case String.split(cleaned_size_string, "x") do
      [target_width] ->
        ratio = parse_ratio_string(cfg["ratio"])
        {String.to_integer(target_width), round(String.to_integer(target_width) / ratio)}

      ["", target_height] ->
        ratio = parse_ratio_string(cfg["ratio"])
        {round(String.to_integer(target_height) * ratio), String.to_integer(target_height)}

      [target_width, ""] ->
        ratio = parse_ratio_string(cfg["ratio"])
        {String.to_integer(target_width), round(String.to_integer(target_width) / ratio)}

      [target_width, target_height] ->
        {String.to_integer(target_width), String.to_integer(target_height)}
    end
  end

  def parse_ratio_string(ratio_string) do
    [r1, r2] = String.split(ratio_string, "/")
    String.to_integer(r1) / String.to_integer(r2)
  end

  @doc """
  Set progress for user
  """
  def set_progress(
        %{size_key: size_key, id: id, format: format} = conversion_parameters,
        progress,
        filename,
        user
      ) do
    progress_string =
      gettext(
        "%{filename} &rarr; Creating image size: <strong>%{size_key}</strong>/%{format}",
        filename: filename,
        size_key: size_key,
        format: format
      )

    Progress.update(user, progress_string,
      key: to_string(id),
      percent: progress
    )

    conversion_parameters
  end

  defp maybe_change_format(type) when type in [:jpg, :png, :gif, :webp], do: Atom.to_string(type)
  defp maybe_change_format(_), do: "jpg"
end
