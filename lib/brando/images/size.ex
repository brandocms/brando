defmodule Brando.Images.Size do
  @moduledoc """
  One entry in an image config's `sizes`.

  Configs usually write a size as a string-keyed map:

      "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true}

  Atom keys and `%Brando.Images.Size{}` are accepted as well. Every entry is
  checked when the config is normalized (for a literal Blueprint config, when
  the Blueprint compiles) and stored as the string-keyed map above, which is
  the shape processing and rendering read.

  ## Fields

    * `size` - the geometry: `"700"` (a width), `"x400"` (a height) or
      `"400x400"`, optionally with an ImageMagick flag such as `>`. Required.
      The image is fitted inside the geometry, keeping its proportions, and a
      smaller original is enlarged; a width alone is fitted inside a square of
      that width. Processing reads past the flags: `"400x400>"` is processed
      like `"400x400"`, and `"50%"` is 50 pixels, not half.
    * `quality` - an integer from 1 to 100. Processing uses 100 without one.
    * `crop` - crop to the geometry around the image's focal point.
    * `ratio` - an aspect ratio such as `"3/2"`. A cropped size that gives only
      a width or a height needs one to know the other.

  A size can also differ by orientation. Both keys are required:

      "medium" => %{
        "portrait" => %{"size" => "700", "quality" => 75},
        "landscape" => %{"size" => "1100", "quality" => 75}
      }

  ## Presets

  `sizes: :standard` uses the list below, the same as
  `Brando.Type.ImageConfig.default_config/0`. To add sizes or replace some,
  give a map with it: `sizes: {:standard, %{"hero" => %{"size" => "2400"}}}`.

      "micro"  => %{"size" => "25", "quality" => 20, "crop" => false}
      "thumb"  => %{"size" => "400x400>", "quality" => 75, "crop" => true}
      "small"  => %{"size" => "700", "quality" => 75}
      "medium" => %{"size" => "1100", "quality" => 75}
      "large"  => %{"size" => "1700", "quality" => 75}
      "xlarge" => %{"size" => "2100", "quality" => 75}
  """

  @type t :: %__MODULE__{
          size: String.t(),
          quality: 1..100 | nil,
          crop: boolean() | nil,
          ratio: String.t() | nil
        }

  defstruct size: nil, quality: nil, crop: nil, ratio: nil

  @fields ~w(size quality crop ratio)
  @orientations ~w(portrait landscape)
  # ImageMagick geometry flags. Processing strips them before reading the numbers.
  @geometry_flags ["^", "!", ">", "<", "%"]

  @presets %{
    standard: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true},
      "small" => %{"size" => "700", "quality" => 75},
      "medium" => %{"size" => "1100", "quality" => 75},
      "large" => %{"size" => "1700", "quality" => 75},
      "xlarge" => %{"size" => "2100", "quality" => 75}
    }
  }

  @doc "Returns the names of the size presets."
  @spec presets() :: [atom()]
  def presets, do: @presets |> Map.keys() |> Enum.sort()

  @doc "Returns the sizes of the preset `name`."
  @spec preset!(atom()) :: %{String.t() => map()}
  def preset!(name) do
    case Map.fetch(@presets, name) do
      {:ok, sizes} -> sizes
      :error -> raise ArgumentError, "unknown size preset #{inspect(name)}, expected one of #{inspect(presets())}"
    end
  end

  @doc """
  Checks a config's `sizes` and returns them as string-keyed maps.

  Accepts a map of sizes, a preset name, or `{preset, sizes}` to merge sizes
  over a preset. Any other value is returned unchanged for the config
  validator to reject.
  """
  @spec normalize_sizes(term()) :: {:ok, term()} | {:error, String.t()}
  def normalize_sizes(preset) when is_atom(preset) and not is_nil(preset) do
    with {:ok, sizes} <- fetch_preset(preset), do: normalize_sizes(sizes)
  end

  def normalize_sizes({preset, extra}) when is_atom(preset) and is_map(extra) and not is_struct(extra) do
    with {:ok, sizes} <- fetch_preset(preset), do: normalize_sizes(Map.merge(sizes, string_keys(extra)))
  end

  def normalize_sizes(sizes) when is_map(sizes) and not is_struct(sizes) do
    Enum.reduce_while(sizes, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case normalize(value) do
        {:ok, size} -> {:cont, {:ok, Map.put(acc, to_string(key), size)}}
        {:error, message} -> {:halt, {:error, ":sizes[#{inspect(to_string(key))}] #{message}"}}
      end
    end)
  end

  def normalize_sizes(other), do: {:ok, other}

  @doc """
  Checks one size entry, or a portrait/landscape pair, and returns it as a
  string-keyed map.
  """
  @spec normalize(term()) :: {:ok, map()} | {:error, String.t()}
  def normalize(value) do
    with {:ok, map} <- to_map(value) do
      if orientation_pair?(map), do: normalize_orientations(map), else: normalize_entry(map)
    end
  end

  @doc """
  Parses a size's geometry into `{width, height}`, either of which may be nil.
  """
  @spec dimensions(String.t()) :: {:ok, {pos_integer() | nil, pos_integer() | nil}} | :error
  def dimensions(geometry) when is_binary(geometry) do
    geometry
    |> String.replace(@geometry_flags, "")
    |> String.split("x")
    |> case do
      [width] -> parse_dimensions(width, "")
      [width, height] -> parse_dimensions(width, height)
      _other -> :error
    end
  end

  def dimensions(_geometry), do: :error

  defp fetch_preset(name) do
    case Map.fetch(@presets, name) do
      {:ok, sizes} -> {:ok, sizes}
      :error -> {:error, ":sizes uses the unknown size preset #{inspect(name)}, expected one of #{inspect(presets())}"}
    end
  end

  defp to_map(%__MODULE__{} = size) do
    size
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> to_map()
  end

  defp to_map(value) when is_map(value) or is_list(value) do
    if is_map(value) or Keyword.keyword?(value) do
      {:ok, string_keys(value)}
    else
      {:error, "must be a map, got: #{inspect(value)}"}
    end
  end

  defp to_map(value), do: {:error, "must be a map, got: #{inspect(value)}"}

  defp string_keys(value), do: Map.new(value, fn {key, value} -> {to_string(key), value} end)

  defp orientation_pair?(map), do: Enum.any?(@orientations, &Map.has_key?(map, &1))

  defp normalize_orientations(map) do
    case {Map.keys(map) -- @orientations, @orientations -- Map.keys(map)} do
      {[], []} ->
        Enum.reduce_while(@orientations, {:ok, %{}}, &put_orientation(map, &1, &2))

      {[], missing} ->
        {:error, "sets an orientation but has no #{Enum.map_join(missing, " or ", &inspect/1)} size"}

      {unknown, _missing} ->
        {:error, "mixes orientations with other keys: #{inspect(Enum.sort(unknown))}"}
    end
  end

  defp put_orientation(map, orientation, {:ok, acc}) do
    with {:ok, entry} <- to_map(Map.fetch!(map, orientation)),
         {:ok, entry} <- normalize_entry(entry) do
      {:cont, {:ok, Map.put(acc, orientation, entry)}}
    else
      {:error, message} -> {:halt, {:error, "(#{orientation}) #{message}"}}
    end
  end

  defp normalize_entry(map) do
    with :ok <- known_keys(map),
         {:ok, dimensions} <- geometry(Map.get(map, "size")),
         {:ok, quality} <- quality(Map.get(map, "quality")),
         :ok <- crop(Map.get(map, "crop")),
         :ok <- ratio(Map.get(map, "ratio")),
         :ok <- crop_dimensions(map, dimensions) do
      {:ok, put_present(map, "quality", quality)}
    end
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp known_keys(map) do
    case Map.keys(map) -- @fields do
      [] -> :ok
      [key | _] -> {:error, "has an unknown key #{inspect(key)}#{suggestion(key)}"}
    end
  end

  defp suggestion(key) do
    field = Enum.max_by(@fields, &String.jaro_distance(key, &1))
    if String.jaro_distance(key, field) > 0.8, do: " (did you mean #{inspect(field)}?)", else: ""
  end

  defp geometry(nil), do: {:error, ~s(has no "size")}

  defp geometry(geometry) do
    case dimensions(geometry) do
      {:ok, dimensions} -> {:ok, dimensions}
      :error -> {:error, ~s(has an invalid "size" #{inspect(geometry)}, expected a geometry such as "700" or "400x400>")}
    end
  end

  defp quality(nil), do: {:ok, nil}
  defp quality(quality) when is_integer(quality) and quality in 1..100, do: {:ok, quality}

  defp quality(quality) when is_binary(quality) do
    case Integer.parse(quality) do
      {integer, ""} -> quality(integer)
      _other -> invalid_quality(quality)
    end
  end

  defp quality(quality), do: invalid_quality(quality)

  defp invalid_quality(quality), do: {:error, ~s(has an invalid "quality" #{inspect(quality)}, expected 1–100)}

  defp crop(crop) when is_nil(crop) or is_boolean(crop), do: :ok
  defp crop(crop), do: {:error, ~s(has an invalid "crop" #{inspect(crop)}, expected a boolean)}

  defp ratio(nil), do: :ok

  defp ratio(ratio) when is_binary(ratio) do
    with [width, height] <- String.split(ratio, "/"),
         {:ok, {_width, _height}} <- parse_dimensions(width, height),
         false <- width == "" or height == "" do
      :ok
    else
      _other -> invalid_ratio(ratio)
    end
  end

  defp ratio(ratio), do: invalid_ratio(ratio)

  defp invalid_ratio(ratio), do: {:error, ~s(has an invalid "ratio" #{inspect(ratio)}, expected a ratio such as "3/2")}

  # Cropping needs both dimensions; with only one, the ratio supplies the other.
  defp crop_dimensions(%{"crop" => true} = map, {width, height}) when is_nil(width) or is_nil(height) do
    if Map.has_key?(map, "ratio") do
      :ok
    else
      {:error, ~s(is cropped but its "size" gives one dimension; add a "ratio" such as "3/2")}
    end
  end

  defp crop_dimensions(_map, _dimensions), do: :ok

  defp parse_dimensions(width, height) do
    with {:ok, width} <- parse_dimension(width),
         {:ok, height} <- parse_dimension(height),
         true <- not (is_nil(width) and is_nil(height)) do
      {:ok, {width, height}}
    else
      _other -> :error
    end
  end

  defp parse_dimension(""), do: {:ok, nil}

  defp parse_dimension(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> :error
    end
  end
end
