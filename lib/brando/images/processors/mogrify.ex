defmodule Brando.Images.Processor.Mogrify do
  @moduledoc """
  Process image with Mogrify
  """
  @behaviour Brando.Images.Processor

  alias Brando.Images

  @doc """
  Process image conversion when crop is false
  """
  def process_image(%Images.ConversionParameters{
        id: id,
        size_key: size_key,
        crop: false,
        quality: quality,
        format: format,
        image_src_path: image_src_path,
        image_dest_path: image_dest_path,
        image_dest_rel_path: image_dest_rel_path,
        resize_values: resize_values
      }) do
    resize_geo = "#{resize_values.width}x#{resize_values.height}"

    image_src_path
    |> Mogrify.open()
    |> Mogrify.format(format)
    |> Mogrify.custom("quality", quality)
    |> Mogrify.resize_to_limit(resize_geo)
    |> Mogrify.save(path: image_dest_path)

    {:ok,
     %Images.TransformResult{
       id: id,
       size_key: size_key,
       image_path: image_dest_rel_path
     }}
  end

  @doc """
  Process image conversion when crop is true
  """
  def process_image(%Images.ConversionParameters{
        id: id,
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
    resize_geo = "#{resize_values.width}x#{resize_values.height}"

    crop_geo =
      "#{crop_values.width}x" <>
        "#{crop_values.height}+" <>
        "#{crop_values.top}+" <>
        "#{crop_values.left}"

    image_src_path
    |> Mogrify.open()
    |> Mogrify.format(format)
    |> Mogrify.custom("quality", quality)
    |> Mogrify.custom("resize", resize_geo)
    |> Mogrify.custom("crop", crop_geo)
    |> Mogrify.save(path: image_dest_path)

    {:ok,
     %Images.TransformResult{
       id: id,
       size_key: size_key,
       image_path: image_dest_rel_path
     }}
  end

  @spec confirm_executable_exists ::
          {:ok, {:executable, :exists}} | {:error, {:executable, :missing}}
  def confirm_executable_exists do
    case System.find_executable("mogrify") do
      nil ->
        {:error, {:executable, :missing, "mogrify"}}

      _ ->
        {:ok, {:executable, :exists}}
    end
  end
end
