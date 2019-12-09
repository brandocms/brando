defmodule Brando.Images.Processor.Sharp do
  @moduledoc """
  Process image with Sharp
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
    image_dest_dir = Path.dirname(image_dest_path)
    image_dest_path = Path.join(image_dest_dir, "{name}{ext}")

    file_params = [
      "-i",
      image_src_path,
      "-o",
      image_dest_path
    ]

    resize_params = [
      "resize",
      (Map.has_key?(resize_values, :width) &&
         round_to_string(resize_values.width)) || "0",
      (Map.has_key?(resize_values, :height) &&
         [
           "--height",
           round_to_string(resize_values.height)
         ]) || [],
      "--withoutEnlargement",
      "--fit",
      "inside"
    ]

    extra_params = [
      "--quality",
      to_string(quality),
      "--palette",
      "true",
      "--format",
      format
    ]

    params = List.flatten(file_params ++ extra_params ++ resize_params)

    System.cmd("sharp", params, stderr_to_stdout: true)

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
    image_dest_dir = Path.dirname(image_dest_path)
    image_dest_path = Path.join(image_dest_dir, "{name}{ext}")

    file_params = [
      "-i",
      image_src_path,
      "-o",
      image_dest_path
    ]

    resize_params = [
      "resize",
      (Map.has_key?(resize_values, :width) &&
         round_to_string(resize_values.width)) || "0",
      (Map.has_key?(resize_values, :height) &&
         [
           "--height",
           round_to_string(resize_values.height)
         ]) || [],
      "--fit",
      "inside"
    ]

    extract_params = [
      "extract",
      crop_values.left |> round_to_string,
      crop_values.top |> round_to_string,
      crop_values.width |> round_to_string,
      crop_values.height |> round_to_string
    ]

    extra_params = [
      "--quality",
      to_string(quality),
      "--format",
      format
    ]

    params =
      List.flatten(file_params ++ extra_params ++ resize_params ++ ["--"] ++ extract_params)

    System.cmd("sharp", params, stderr_to_stdout: true)

    {:ok,
     %Images.TransformResult{
       id: id,
       size_key: size_key,
       image_path: image_dest_rel_path
     }}
  end

  def confirm_executable_exists do
    case System.cmd("sharp", ["--version"]) do
      {_, 0} ->
        {:ok, {:executable, :exists}}

      _ ->
        {:error, {:executable, :missing, "sharp-cli"}}
    end
  rescue
    _ ->
      {:error, {:executable, :missing, "sharp-cli"}}
  end

  defp round_to_string(0), do: "0"
  defp round_to_string(val) when is_float(val), do: val |> Float.round() |> Float.to_string()
  defp round_to_string(val), do: val |> to_string()
end
