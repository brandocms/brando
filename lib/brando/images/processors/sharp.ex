defmodule Brando.Images.Processor.Sharp do
  @moduledoc """
  Process image with Sharp
  """

  require Logger
  alias Brando.Images
  alias Brando.Images.Processor

  @behaviour Brando.Images.Processor

  @doc """
  Wrapper for System.cmd
  """
  def command(cmd, params, opts), do: System.cmd(cmd, params, opts)

  @doc """
  Process image conversion
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
        optimize: optimize?,
        resize_values: resize_values
      }) do
    image_dest_dir = Path.dirname(image_dest_path)
    image_dest_path = Path.join(image_dest_dir, "{name}.#{format}")

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
      "rotate",
      "--",
      "--quality",
      to_string(quality),
      "--palette",
      "true",
      "--format",
      format,
      (optimize? && ["--optimize", "true"]) || []
    ]

    params = List.flatten(file_params ++ extra_params ++ resize_params)

    case Processor.Commands.delegate("sharp", params, stderr_to_stdout: true) do
      {error_msg, 1} ->
        Logger.error("""
        ==> process_image/ERROR

        Error msg:
        #{inspect(error_msg)}

        Resize values:
        #{inspect(resize_values)}

        Params:
        #{inspect(Enum.join(params, " "), pretty: true)}
        """)

      {"", 139} ->
        Logger.error("""
        ==> process_image/ERROR -- SEGMENT FAULT!

        Resize values:
        #{inspect(resize_values)}

        Params:
        #{inspect(Enum.join(params, " "), pretty: true)}

        NOTE:

        This usually means there is something wrong with either your libvips installation or sharp-cli installation. Try reinstalling

        """)

      {_, 0} ->
        :ok
    end

    {:ok,
     %Images.TransformResult{
       id: id,
       size_key: size_key,
       image_path: image_dest_rel_path,
       cmd_params: Enum.join(params, " ")
     }}
  end

  def process_image(%Images.ConversionParameters{
        id: id,
        size_key: size_key,
        crop: true,
        quality: quality,
        format: format,
        image_src_path: image_src_path,
        image_dest_path: image_dest_path,
        image_dest_rel_path: image_dest_rel_path,
        optimize: optimize?,
        resize_values: resize_values,
        crop_values: crop_values
      }) do
    image_dest_dir = Path.dirname(image_dest_path)
    image_dest_path = Path.join(image_dest_dir, "{name}.#{format}")

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
         ]) || []
    ]

    extract_params = [
      "extract",
      crop_values.top |> round_to_string,
      crop_values.left |> round_to_string,
      crop_values.width |> round_to_string,
      crop_values.height |> round_to_string
    ]

    extra_params = [
      "rotate",
      "--",
      "--quality",
      to_string(quality),
      "--format",
      format,
      (optimize? && ["--optimize", "true"]) || []
    ]

    params =
      List.flatten(file_params ++ extra_params ++ resize_params ++ ["--"] ++ extract_params)

    case Processor.Commands.delegate("sharp", params, stderr_to_stdout: true) do
      {error_msg, 1} ->
        Logger.error("""
        ==> process_image/ERROR

        Error msg:
        #{inspect(error_msg)}

        Resize values:
        #{inspect(resize_values)}

        Crop values:
        #{inspect(crop_values)}

        Params:
        #{inspect(Enum.join(params, " "), pretty: true)}
        """)

      {"", 139} ->
        Logger.error("""
        ==> process_image/ERROR -- SEGMENT FAULT!

        Resize values:
        #{inspect(resize_values)}

        Params:
        #{inspect(Enum.join(params, " "), pretty: true)}

        NOTE:

        This usually means there is something wrong with either your libvips installation or sharp-cli installation. Try reinstalling

        """)

      {_, 0} ->
        :ok
    end

    {:ok,
     %Images.TransformResult{
       id: id,
       size_key: size_key,
       image_path: image_dest_rel_path,
       cmd_params: Enum.join(params, " ")
     }}
  end

  def confirm_executable_exists do
    case Processor.Commands.delegate("sharp", ["--version"], []) do
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
