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
  The pixels decoding `image` takes, as it was opened: every page of an image
  opened with `pages: :all`, otherwise the first.
  """
  @spec pixels(Vix.Vips.Image.t()) :: non_neg_integer()
  def pixels(%Vix.Vips.Image{} = image), do: Image.width(image) * Image.height(image)

  @doc """
  `:ok` when `image` is within the limit: an opened image, or a file path,
  which is opened for its header only, the way processing will decode it
  (`open_options/1`), so nothing is decoded.
  """
  @spec check(Vix.Vips.Image.t() | Path.t(), keyword) :: :ok | {:error, :too_many_pixels | term}
  def check(image, open_options \\ [])

  def check(%Vix.Vips.Image{} = image, _open_options) do
    if pixels(image) > max_pixels(), do: {:error, :too_many_pixels}, else: :ok
  end

  def check(path, open_options) when is_binary(path) do
    with {:ok, image} <- Image.open(path, open_options), do: check(image)
  end

  @doc """
  How processing opens an image, from its file name or MIME type: every
  frame of a GIF, the first page of anything else.
  """
  @spec open_options(String.t() | [String.t() | nil] | nil) :: keyword
  def open_options("image/gif"), do: [pages: :all]

  def open_options(name) when is_binary(name) do
    if name |> Path.extname() |> String.downcase() == ".gif", do: [pages: :all], else: []
  end

  # A GIF by any of the names, a MIME type that says otherwise included
  def open_options(names) when is_list(names) do
    if Enum.any?(names, &(open_options(&1) != [])), do: [pages: :all], else: []
  end

  def open_options(_name), do: []

  @doc """
  `check/1` for a stored image's original, before it is processed. Only an
  image over the limit fails: an SVG is not decoded to pixels, and an
  original that can't be read is left to processing to report.
  """
  @spec check_image(%{path: String.t()}) :: :ok | {:error, :too_many_pixels}
  def check_image(%{path: path}) when is_binary(path) do
    with false <- Brando.Images.Utils.image_type(path) == :svg,
         {:error, :too_many_pixels} = error <-
           path |> Brando.Images.Utils.media_path() |> check(open_options(path)) do
      error
    else
      _ -> :ok
    end
  end

  @doc "The message an editor sees for an image over the limit."
  @spec error_message() :: String.t()
  def error_message do
    gettext("The image is larger than %{megapixels} megapixels.", megapixels: div(max_pixels(), 1_000_000))
  end
end
