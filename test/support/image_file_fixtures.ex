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

  @doc """
  Inserts an image with its original written at
  images/replace/<name>-<n>.<ext>, as an upload stores it, with the file's
  `content_hash`. Each raster file has a colour of its own, so a hash of its
  own. `opts`: `:ext` (`"jpg"`, `"png"` or `"svg"`), and image fields.
  """
  def file_image(name, {width, height}, opts \\ []) do
    ext = Keyword.get(opts, :ext, "jpg")
    path = "images/replace/#{name}-#{System.unique_integer([:positive])}.#{ext}"
    file = Brando.Images.Utils.media_path(path)
    File.mkdir_p!(Path.dirname(file))

    case ext do
      "svg" ->
        fill = "##{System.unique_integer([:positive])}"

        File.write!(
          file,
          ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}"><rect width="10" height="10" fill="#{fill}"/></svg>)
        )

      _ ->
        color = for _ <- 1..3, do: :rand.uniform(255)
        width |> Image.new!(height, color: color) |> Image.write!(file)
    end

    hash = :sha256 |> :crypto.hash(File.read!(file)) |> Base.encode16(case: :lower)

    :image
    |> Factory.build(
      Keyword.merge(
        [
          path: path,
          width: width,
          height: height,
          formats: [String.to_existing_atom(ext)],
          sizes: %{},
          content_hash: hash,
          config_target: "default",
          status: :processed
        ],
        Keyword.delete(opts, :ext)
      )
    )
    |> Brando.Repo.insert!()
  end
end
