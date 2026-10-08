defmodule Brando.ImageFileFixtures do
  @moduledoc """
  Images processed before Brando recorded configs, with their size files on
  disk, for `Brando.Images.Adoption`.
  """

  alias Brando.Factory

  # The test config's "default" target: the standard sizes and `formats:
  # [:original]`. What the first libvips processor (0.55 before its release)
  # made of an 800×600 original with them, enlarging it for the larger sizes.
  @sizes %{
    "micro" => {25, 19},
    "thumb" => {400, 400},
    "small" => {700, 525},
    "medium" => {1100, 825},
    "large" => {1700, 1275},
    "xlarge" => {2100, 1575}
  }

  def standard_sizes, do: @sizes

  @doc """
  Inserts an image without a fingerprint at images/adoption/<name>.jpg on
  the "default" target, and writes its size files.

    * `:sizes` - `%{key => {width, height}}`, the standard sizes by default
    * `:formats` - the image's formats, `[:jpg]` by default
    * `:write` - the formats to write files for, its formats by default
    * `:original` - the original's `{width, height}`, `{800, 600}` by default
    * `:config_target` - `"default"` by default

  Inserts through `Brando.Repo`, into the current environment.
  """
  def unrecorded_image(name, opts \\ []) do
    {width, height} = Keyword.get(opts, :original, {800, 600})
    sizes = Keyword.get(opts, :sizes, @sizes)
    formats = Keyword.get(opts, :formats, [:jpg])

    for format <- Keyword.get(opts, :write, formats), {key, dimensions} <- sizes do
      write_image("images/adoption/#{key}/#{name}.#{format}", dimensions)
    end

    :image
    |> Factory.build(
      path: "images/adoption/#{name}.jpg",
      width: width,
      height: height,
      formats: formats,
      sizes: Map.new(sizes, fn {key, _dimensions} -> {key, "images/adoption/#{key}/#{name}.jpg"} end),
      config_target: Keyword.get(opts, :config_target, "default"),
      config_fingerprint: nil
    )
    |> Brando.Repo.insert!()
  end

  @doc "Writes a blank image of `{width, height}` at `path` in the media folder."
  def write_image(path, {width, height}) do
    file = Brando.Images.Utils.media_path(path)
    File.mkdir_p!(Path.dirname(file))
    width |> Image.new!(height, color: [90, 120, 150]) |> Image.write!(file)
  end
end
