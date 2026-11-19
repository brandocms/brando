defmodule BrandoAdmin.Images.Sources do
  @moduledoc """
  An image in the sizes it has, for an admin `<img>` shown larger than a
  thumbnail: `srcset` candidates at the widths each size was saved at, so the
  browser takes one that is sharp at the width the image is shown.
  """
  alias Brando.Images.{ConfigResolver, Size}
  alias Brando.Images.Operations.Sizing
  alias Brando.Utils

  @doc """
  `{width, url}` for each size `image` has, narrowest first, one per width.
  Low-quality sizes are blur placeholders, not candidates. Empty when the
  image has no sizes yet, or its config cannot be read.

  With `uncropped: true`, sizes cropped to a frame of their own (such as the
  square `thumb`) are left out, for an image shown in its own framing.
  """
  @spec candidates(map(), keyword()) :: [{pos_integer(), String.t()}]
  def candidates(image, opts \\ [])

  def candidates(%{sizes: sizes} = image, opts) when is_map(sizes) and map_size(sizes) > 0 do
    {:ok, config} = ConfigResolver.get(image)
    uncropped? = Keyword.get(opts, :uncropped, false)

    for {key, %{"size" => geometry} = size_config} <- config.sizes || %{},
        Map.has_key?(sizes, key),
        Map.get(size_config, "quality", 100) >= 30,
        not (uncropped? and size_config["crop"] == true),
        {:ok, dimensions} <- [Size.dimensions(geometry)],
        width = rendered_width(image, dimensions, size_config) do
      {width, Utils.img_url(image, key, prefix: Utils.media_url())}
    end
    |> Enum.sort()
    |> Enum.uniq_by(&elem(&1, 0))
  rescue
    _ -> []
  end

  def candidates(_image, _opts), do: []

  @doc "The `srcset` attribute for `candidates/2`; `nil` for none."
  @spec srcset([{pos_integer(), String.t()}]) :: String.t() | nil
  def srcset([]), do: nil
  def srcset(candidates), do: Enum.map_join(candidates, ", ", fn {width, url} -> "#{url} #{width}w" end)

  @doc """
  The candidate to put in `src`: the narrowest at least `min_width` wide, or
  the widest. `nil` for no candidates.
  """
  @spec src([{pos_integer(), String.t()}], pos_integer()) :: String.t() | nil
  def src([], _min_width), do: nil

  def src(candidates, min_width) do
    {_width, url} = Enum.find(candidates, &(elem(&1, 0) >= min_width)) || Enum.max(candidates)
    url
  end

  # The width a size is actually saved at, which `srcset` needs.
  defp rendered_width(%{width: width, height: height}, _box, size_config)
       when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    size_config |> Sizing.processed_dimensions({width, height}) |> elem(0)
  end

  defp rendered_width(_image, {box_width, _box_height}, _size_config), do: box_width
end
