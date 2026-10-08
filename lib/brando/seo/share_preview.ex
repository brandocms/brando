defmodule Brando.SEO.SharePreview do
  @moduledoc """
  What an entry looks like when it is found or shared: the search result, the
  Open Graph card (Facebook, LinkedIn) and the X card, for the meta drawer's
  Previews tab.

  The values follow `Brando.Meta.HTML.render_meta/1`: the blueprint's
  `meta_schema` first, then the SEO settings' fallbacks. The image is the one
  `og:image` names, in the size `render_meta` shares (`:largest`).

  When that size is cropped (`"crop" => true`, as `trait :meta`'s meta image
  is), Brando cut it from the original around the image's focal point. The
  card then shows that file, framed the way each platform frames it: centred
  and cut to the card's shape. `frame/2` works out where the focal point
  lands in that frame, with the same arithmetic as
  `Brando.Images.Operations.Sizing`, so the preview's marker sits where the
  shared image puts it.
  """
  alias Brando.Images.ConfigResolver
  alias Brando.Images.Operations.Sizing

  # Card shapes, width / height.
  @ratios %{open_graph: 1.91, x: 2.0}

  @max_title 60
  @max_description 155

  @type frame :: %{src: String.t(), focal: {float(), float()} | nil, ratio: float(), cropped?: boolean()}

  @doc "The aspect ratio (width / height) a platform's large card uses."
  @spec ratio(:open_graph | :x) :: float()
  def ratio(platform), do: Map.fetch!(@ratios, platform)

  @doc """
  The title, description and image `render_meta` gives an entry's page, with
  the SEO settings for `language` as fallbacks, and the title a search result
  shows. `entry` may be unsaved.
  """
  @spec values(module(), map(), String.t()) :: %{
          title: term(),
          search_title: term(),
          description: term(),
          image: term()
        }
  def values(schema, entry, language) do
    seo = Brando.Cache.SEO.get(language)
    meta = meta(schema, entry)

    %{
      title: present(meta["og:title"]) || present(meta["title"]) || present(seo.fallback_meta_title),
      # A search result shows the page's <title>, which controllers usually set
      # from the entry's own title when its meta schema gives none.
      search_title: present(meta["title"]) || present(Map.get(entry, :title)) || present(seo.fallback_meta_title),
      description:
        present(meta["og:description"]) || present(meta["description"]) || present(seo.fallback_meta_description),
      image: image(meta["og:image"]) || image(seo.fallback_meta_image)
    }
  end

  defp meta(schema, entry) do
    entry = Map.put(entry, :__meta__, %{current_url: nil, language: Map.get(entry, :language)})

    schema
    |> Brando.Blueprint.Meta.extract_meta(entry)
    |> Map.new()
  rescue
    _ -> %{}
  end

  defp present(value) when is_binary(value) do
    value = value |> Floki.parse_fragment!() |> Floki.text() |> String.trim()
    if value == "", do: nil, else: value
  end

  defp present(_value), do: nil

  defp image(%Brando.Images.Image{path: path} = image) when is_binary(path), do: image
  defp image(url) when is_binary(url) and url != "", do: url
  defp image(_image), do: nil

  @doc """
  `text` cut to what a search result shows, at a word, with an ellipsis.

      iex> Brando.SEO.SharePreview.truncate("A short title", :title)
      "A short title"

      iex> Brando.SEO.SharePreview.truncate(String.duplicate("word ", 20), :title)
      "word word word word word word word word word word word word…"
  """
  @spec truncate(String.t() | nil, :title | :description) :: String.t() | nil
  def truncate(nil, _kind), do: nil

  def truncate(text, kind) do
    max = if kind == :title, do: @max_title, else: @max_description

    if String.length(text) <= max do
      text
    else
      cut = String.slice(text, 0, max)
      cut = if String.contains?(cut, " "), do: cut |> String.split(" ") |> Enum.drop(-1) |> Enum.join(" "), else: cut
      String.trim_trailing(cut, " ,.;:") <> "…"
    end
  end

  @doc """
  The shared image for `image` framed for `platform`: the URL of the size
  `render_meta` shares, whether that size was cropped around the focal point,
  and where the focal point lands in the card, as percentages from the top
  left (`nil` when the card cuts it off or the image has none).
  """
  @spec frame(Brando.Images.Image.t() | String.t() | nil, :open_graph | :x) :: frame() | nil
  def frame(nil, _platform), do: nil

  def frame(url, platform) when is_binary(url), do: %{src: url, focal: nil, ratio: ratio(platform), cropped?: false}

  def frame(%Brando.Images.Image{} = image, platform) do
    {size_key, size_cfg} = largest_size(image)

    src =
      if is_map(image.sizes) and Map.has_key?(image.sizes, size_key),
        do: Brando.Utils.img_url(image, size_key, prefix: Brando.Utils.media_url()),
        else: Brando.Utils.img_url(image, :original, prefix: Brando.Utils.media_url())

    {shared, cropped?} = shared_region(image, size_cfg)

    %{
      src: src,
      cropped?: cropped?,
      ratio: ratio(platform),
      focal: focal_in_card(image, shared, ratio(platform))
    }
  end

  # The size `Brando.Images.URL.url(image, :largest)` picks: the widest, the
  # better quality on a tie.
  defp largest_size(image) do
    {:ok, config} = ConfigResolver.get(image)

    config.sizes
    |> Enum.max_by(fn {_key, %{"size" => dimensions} = cfg} ->
      {dimensions |> Integer.parse() |> elem(0), Map.get(cfg, "quality", 100)}
    end)
  rescue
    _ -> {"original", %{}}
  end

  @doc """
  The part of the original image a size config keeps, as `{x, y, width,
  height}` in the original's pixels, and whether it was cropped.

  A cropping size is cut around the focal point exactly as
  `Brando.Images.Operations.Sizing` cuts it; any other size keeps the whole
  image.
  """
  @spec shared_region(map(), map()) :: {{number(), number(), number(), number()}, boolean()}
  def shared_region(%{width: width, height: height} = image, size_cfg)
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    size_cfg = Sizing.get_size_cfg_orientation(size_cfg, width, height)

    if Map.get(size_cfg, "crop") == true do
      {crop_width, crop_height} = Sizing.get_crop_dimensions_from_cfg(size_cfg)

      params =
        %{
          crop: true,
          crop_width: crop_width,
          crop_height: crop_height,
          original_width: width,
          original_height: height,
          focal_point: focal(image)
        }
        |> Sizing.add_resize_dimensions()
        |> Sizing.get_original_focal_point()
        |> Sizing.transform_focal_point()
        |> Sizing.calculate_anchor()

      scale = width / params.resize_width

      {{params.anchor.x * scale, params.anchor.y * scale, crop_width * scale, crop_height * scale}, true}
    else
      {{0, 0, width, height}, false}
    end
  end

  def shared_region(_image, _size_cfg), do: {{0, 0, 1, 1}, false}

  @doc """
  Where the focal point lands in a card of `ratio` that shows `region` of the
  image centred and cut to its shape, as `{x, y}` percentages, or `nil` when
  the card cuts it off.
  """
  @spec focal_in_card(map(), {number(), number(), number(), number()}, float()) :: {float(), float()} | nil
  def focal_in_card(%{width: width, height: height} = image, {rx, ry, rw, rh}, ratio)
      when is_integer(width) and is_integer(height) do
    %{x: fx, y: fy} = focal(image)

    {cx, cy, cw, ch} =
      if rw / rh > ratio do
        visible = rh * ratio
        {rx + (rw - visible) / 2, ry, visible, rh}
      else
        visible = rw / ratio
        {rx, ry + (rh - visible) / 2, rw, visible}
      end

    px = (fx / 100 * width - cx) / cw * 100
    py = (fy / 100 * height - cy) / ch * 100

    if px >= 0 and px <= 100 and py >= 0 and py <= 100, do: {Float.round(px, 1), Float.round(py, 1)}
  end

  def focal_in_card(_image, _region, _ratio), do: nil

  defp focal(%{focal: %{x: x, y: y}}) when is_number(x) and is_number(y), do: %{x: x, y: y}
  defp focal(%{focal: %{"x" => x, "y" => y}}) when is_number(x) and is_number(y), do: %{x: x, y: y}
  defp focal(_image), do: %{x: 50, y: 50}
end
