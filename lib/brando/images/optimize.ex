defmodule Brando.Images.Optimize do
  @moduledoc """
  Optimization helpers for Brando images.
  """

  @doc """
  Optimize `img`
  """
  def optimize({:ok, %Brando.Type.Image{optimized: false} = img}) do
    type = Brando.Images.Utils.image_type(img)
    case type do
      :jpeg -> do_optimize(:jpeg, img)
      :png  -> do_optimize(:png, img)
      _     -> {:ok, img}
    end
  end
  def optimize({:ok, %Brando.Type.Image{optimized: true} = img}) do
    {:ok, img}
  end

  defp do_optimize(type, img) do
    img
    |> run_optimization(type)
    |> set_optimized_flag
  end

  defp set_optimized_flag(input, value \\ true)
  defp set_optimized_flag({:ok, img}, value) do
    img = img |> Map.put(:optimized, value)
    {:ok, img}
  end

  defp set_optimized_flag({:error, img}, _) do
    {:ok, img}
  end

  defp run_optimization(%Brando.Type.Image{} = img, type) do
    cfg =
      Brando.Images
      |> Brando.config
      |> Keyword.get(:optimize, [])
      |> Keyword.get(type)

    if cfg do
      for file <- Enum.map(img.sizes, &elem(&1, 1)) do
        args = interpolate_and_split_args(file, cfg[:args])
        System.cmd cfg[:bin], args
      end
      {:ok, img}
    else
      {:error, img}
    end
  end

  defp interpolate_and_split_args(file, args) do
    filename =
      file
      |> Brando.Images.Utils.media_path
      |> String.replace(" ", "\\ ")

    newfile =
      file
      |> Brando.Images.Utils.optimized_filename
      |> Brando.Images.Utils.media_path
      |> String.replace(" ", "\\ ")

    args
    |> String.replace("%{filename}", filename)
    |> String.replace("%{new_filename}", newfile)
    |> String.split(" ")
  end
end
