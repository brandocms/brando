defmodule Brando.Images.PixelLimit do
  @moduledoc """
  The largest raster image Brando decodes, counted in pixels over all pages.

  libvips holds a decoded image at about 9 bytes a pixel, and a small, highly
  compressible file can declare dimensions far beyond its weight: a 300 KB PNG
  can ask for 100,000 × 100,000 pixels. Uploads, direct-to-S3 finalizing,
  processing and the content importer read the image's header first and
  refuse anything above the limit before decoding it.

  The default is 100 megapixels. Raise or lower it with:

      config :brando, Brando.Images, max_pixels: 150_000_000
  """
  use Gettext, backend: Brando.Gettext

  @default_max_pixels 100_000_000

  @doc "The configured limit, in pixels."
  @spec max_pixels() :: pos_integer()
  def max_pixels, do: Brando.RuntimeConfig.images(:max_pixels) || @default_max_pixels

  @doc """
  The pixels decoding `image` takes: width × page height × pages. Counts the
  same whether the image was opened with one page or all of them.
  """
  @spec pixels(Vix.Vips.Image.t()) :: non_neg_integer()
  def pixels(%Vix.Vips.Image{} = image) do
    page_height =
      case Vix.Vips.Image.header_value(image, "page-height") do
        {:ok, height} when is_integer(height) and height > 0 -> height
        _ -> Image.height(image)
      end

    Image.width(image) * page_height * Image.pages(image)
  end

  @doc """
  `:ok` when `image` (an opened image or a file path) is within the limit.

  A path is opened for its header only, so nothing is decoded.
  """
  @spec check(Vix.Vips.Image.t() | Path.t()) :: :ok | {:error, :too_many_pixels | term}
  def check(%Vix.Vips.Image{} = image) do
    if pixels(image) > max_pixels(), do: {:error, :too_many_pixels}, else: :ok
  end

  def check(path) when is_binary(path) do
    with {:ok, image} <- Image.open(path), do: check(image)
  end

  @doc "The message an editor sees for an image over the limit."
  @spec error_message() :: String.t()
  def error_message do
    gettext("The image is larger than %{megapixels} megapixels.", megapixels: div(max_pixels(), 1_000_000))
  end
end
