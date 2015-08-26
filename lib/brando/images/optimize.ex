defmodule Brando.Images.Optimize do
  @moduledoc """
  Optimization helpers for Brando images.
  """
  require Logger

  import Brando.Images.Utils, only: [media_path: 1, optimized_filename: 1]

  @doc """
  Optimize `img`
  """
  def optimize(%Brando.Type.Image{optimized: false} = img) do
    type = Brando.Images.Utils.image_type(img)
    case type do
      :jpeg -> do_optimize(:jpeg, img)
      :png  -> do_optimize(:png, img)
      _     -> img
    end
  end
  def optimize(%Brando.Type.Image{optimized: true} = img) do
    img
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
      Brando.config(Brando.Images)
      |> Keyword.get(:optimize)
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
    filename = String.replace(media_path(file), " ", "\\ ")
    newfile = String.replace(media_path(optimized_filename(file)), " ", "\\ ")

    args
    |> String.replace("%{filename}", filename)
    |> String.replace("%{new_filename}", newfile)
    |> String.split(" ")
  end
end