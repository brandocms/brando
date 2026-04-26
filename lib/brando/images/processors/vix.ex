defmodule Brando.Images.Processor.Vix do
  @moduledoc """
  Process images using the Image library (kipcole9/image) backed by libvips via Vix NIFs.

  Replaces the sharp-cli processor, eliminating the need for Node.js and external
  CLI tools (sharp-cli, dominant-color, gifsicle) on production servers.
  """

  @behaviour Brando.Images.Processor

  alias Brando.Images

  require Logger

  @doc """
  Process image conversion without cropping.

  Resizes the source image to fit within the given dimensions while preserving
  aspect ratio. Output format and quality are applied according to the conversion parameters.
  """
  def process_image(%Images.ConversionParameters{
        image_id: image_id,
        size_key: size_key,
        crop: false,
        quality: quality,
        format: format,
        image_src_path: image_src_path,
        image_dest_path: image_dest_path,
        image_dest_rel_path: image_dest_rel_path,
        resize_values: resize_values
      }) do
    image_dest_dir = Path.dirname(image_dest_path)
    image_dest_path = Path.join(image_dest_dir, Path.basename(image_dest_path))

    quality = parse_quality(quality)
    {width, height} = extract_dimensions(resize_values)

    thumbnail_opts =
      [crop: :none]
      |> maybe_add_height(height)

    debug_desc = "vix:thumbnail(#{width || 0}x#{height || 0})"

    with {:ok, img} <- open_image(image_src_path),
         {:ok, resized} <- Image.thumbnail(img, width || 0, thumbnail_opts),
         :ok <- write_image(resized, image_dest_path, format, quality) do
      {:ok,
       %Images.TransformResult{
         image_id: image_id,
         size_key: size_key,
         image_path: image_dest_rel_path,
         format: format,
         cmd_params: debug_desc
       }}
    else
      {:error, reason} ->
        Logger.error("""
        ==> process_image/ERROR (no crop)

        Error: #{inspect(reason)}
        Source: #{image_src_path}
        Dest: #{image_dest_path}
        Resize values: #{inspect(resize_values)}
        """)

        {:ok,
         %Images.TransformResult{
           image_id: image_id,
           size_key: size_key,
           image_path: image_dest_rel_path,
           format: format,
           cmd_params: debug_desc
         }}
    end
  end

  def process_image(%Images.ConversionParameters{
        image_id: image_id,
        size_key: size_key,
        crop: true,
        quality: quality,
        format: format,
        image_src_path: image_src_path,
        image_dest_path: image_dest_path,
        image_dest_rel_path: image_dest_rel_path,
        resize_values: resize_values,
        crop_values: crop_values
      }) do
    image_dest_dir = Path.dirname(image_dest_path)
    image_dest_path = Path.join(image_dest_dir, Path.basename(image_dest_path))

    quality = parse_quality(quality)
    {resize_w, resize_h} = extract_dimensions(resize_values)

    debug_desc =
      "vix:thumbnail(#{resize_w || 0}x#{resize_h || 0})+crop(#{crop_values.left},#{crop_values.top},#{crop_values.width}x#{crop_values.height})"

    thumbnail_opts =
      []
      |> maybe_add_height(resize_h)

    with {:ok, img} <- open_image(image_src_path),
         {:ok, resized} <- Image.thumbnail(img, resize_w || 0, thumbnail_opts),
         {:ok, cropped} <- crop_image(resized, crop_values) do
      write_image(cropped, image_dest_path, format, quality)

      {:ok,
       %Images.TransformResult{
         image_id: image_id,
         size_key: size_key,
         image_path: image_dest_rel_path,
         format: format,
         cmd_params: debug_desc
       }}
    else
      {:error, reason} ->
        Logger.error("""
        ==> process_image/ERROR (crop)

        Error: #{inspect(reason)}
        Source: #{image_src_path}
        Dest: #{image_dest_path}
        Resize values: #{inspect(resize_values)}
        Crop values: #{inspect(crop_values)}
        """)

        {:ok,
         %Images.TransformResult{
           image_id: image_id,
           size_key: size_key,
           image_path: image_dest_rel_path,
           format: format,
           cmd_params: debug_desc
         }}
    end
  end

  @doc """
  Extract the dominant color from an image as a hex string.

  Returns a `"#RRGGBB"` string or `nil` on failure.
  """
  def get_dominant_color(image_path) do
    prefixed_image_path = Images.Utils.media_path(image_path)

    with {:ok, img} <- Image.open(prefixed_image_path),
         {:ok, [{r, g, b} | _]} <- Image.dominant_color(img, method: :imagequant, effort: 3) do
      r = round(r) |> min(255) |> max(0)
      g = round(g) |> min(255) |> max(0)
      b = round(b) |> min(255) |> max(0)

      "#" <>
        String.pad_leading(Integer.to_string(r, 16), 2, "0") <>
        String.pad_leading(Integer.to_string(g, 16), 2, "0") <>
        String.pad_leading(Integer.to_string(b, 16), 2, "0")
    else
      _ -> nil
    end
  rescue
    err ->
      Logger.error("==> get_dominant_color errored: #{inspect(err, pretty: true)}")
      nil
  end

  @doc """
  Verify that the Vix NIF is available by checking that the module is loaded.
  """
  def confirm_executable_exists do
    if Code.ensure_loaded?(Vix.Vips) do
      {:ok, {:executable, :exists}}
    else
      {:error, {:executable, :missing, "vix/libvips"}}
    end
  end

  # -- Private helpers --

  defp open_image(path) do
    if gif?(path) do
      Image.open(path, pages: :all)
    else
      Image.open(path)
    end
  end

  defp gif?(path), do: Path.extname(path) |> String.downcase() == ".gif"

  defp crop_image(img, %{left: left, top: top, width: width, height: height}) do
    # Clamp crop area to image dimensions
    img_width = Image.width(img)
    img_height = Image.height(img)

    left = min(left, max(0, img_width - width))
    top = min(top, max(0, img_height - height))
    width = min(width, img_width - left)
    height = min(height, img_height - top)

    Image.crop(img, left, top, width, height)
  end

  defp write_image(img, dest_path, "jpg", quality) do
    # Flatten alpha channel to white background for JPEGs
    img =
      case Vix.Vips.Operation.flatten(img, background: [255.0, 255.0, 255.0]) do
        {:ok, flattened} -> flattened
        {:error, _} -> img
      end

    case Image.write(img, dest_path, quality: quality) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp write_image(img, dest_path, "png", quality) do
    Vix.Vips.Operation.pngsave(img, dest_path,
      palette: true,
      Q: quality,
      dither: 1.0,
      effort: 7,
      compression: 6
    )
  end

  defp write_image(img, dest_path, _format, quality) do
    case Image.write(img, dest_path, quality: quality) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp extract_dimensions(resize_values) do
    width = Map.get(resize_values, :width)
    height = Map.get(resize_values, :height)
    {width, height}
  end

  defp maybe_add_height(opts, nil), do: opts
  defp maybe_add_height(opts, height), do: Keyword.put(opts, :height, height)

  defp parse_quality(q) when is_binary(q), do: String.to_integer(q)
  defp parse_quality(q) when is_integer(q), do: q
  defp parse_quality(_), do: 80
end
