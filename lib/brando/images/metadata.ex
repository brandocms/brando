defmodule Brando.Images.Metadata do
  @moduledoc """
  Pure image metadata helpers shared by schemas, processors, and rendering.
  """

  @doc "Returns an orientation label for image dimensions or an image-like map."
  @spec orientation(number(), number()) :: String.t()
  def orientation(width, height) when width > height, do: "landscape"
  def orientation(width, height) when width == height, do: "square"
  def orientation(_width, _height), do: "portrait"

  @doc "Returns an orientation label for an image-like map."
  @spec orientation(map() | term()) :: String.t()
  def orientation(%{width: width, height: height}), do: orientation(width, height)
  def orientation(_image), do: "unknown"

  @doc "Returns the normalized image type for a filename."
  @spec type(String.t()) :: atom() | {:error, String.t()}
  def type(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> type_from_extension()
  end

  defp type_from_extension(".jpg"), do: :jpg
  defp type_from_extension(".jpeg"), do: :jpg
  defp type_from_extension(".png"), do: :png
  defp type_from_extension(".gif"), do: :gif
  defp type_from_extension(".bmp"), do: :bmp
  defp type_from_extension(".tif"), do: :tiff
  defp type_from_extension(".tiff"), do: :tiff
  defp type_from_extension(".psd"), do: :psd
  defp type_from_extension(".svg"), do: :svg
  defp type_from_extension(".crw"), do: :crw
  defp type_from_extension(".webp"), do: :webp
  defp type_from_extension(".avif"), do: :avif
  defp type_from_extension(extension), do: {:error, extension}
end
