defmodule Brando.Images.Processor.Mogrify do
  @moduledoc """
  Process image with Mogrify
  """
  @behaviour Brando.Images.Processor

  alias Brando.Images

  @doc """
  Wrapper for System.cmd
  """
  def command(cmd, params, opts), do: System.cmd(cmd, params, opts)

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
    resize_geo = build_resize_geo(resize_values)

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
    resize_geo = build_resize_geo(resize_values)

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

  defp build_resize_geo(resize_values) do
    case {Map.get(resize_values, :width), Map.get(resize_values, :height)} do
      {nil, nil} ->
        raise """
        MOGRIFY: No resize values..
        #{inspect(resize_values, pretty: true)}
        """

      {width, nil} ->
        "#{width}"

      {nil, height} ->
        "x#{height}"

      {width, height} ->
        "#{width}x#{height}"
    end
  end
end
