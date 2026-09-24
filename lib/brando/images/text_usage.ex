defmodule Brando.Images.TextUsage do
  @moduledoc """
  Finds code and templates that read an image's `alt`, `title` or `credits`
  as a string — which, since those fields became language → text maps, now
  get a map instead.

  Used by `mix brando.migrate55` (application source) and
  `mix brando.check.image_texts` (Liquid and HEEx templates stored in the
  database). It reports; it never rewrites: at each call site only a person
  can tell which language is meant.

  Matching is by receiver name, so it narrows the search rather than proving
  there is nothing left: an image's field reached through a name it does not
  know (`hero.alt` for a variable called `hero`) is not found, and a
  non-image with a known name is.
  """

  # Names an image is commonly bound to, in addition to a project's own image
  # asset fields.
  @common_receivers ~w(image img picture photo cover)
  @fields "alt|title|credits"

  @type finding :: %{line: pos_integer(), text: String.t()}

  @doc """
  The image asset fields a Blueprint source declares — `asset :cover, :image`.
  """
  @spec image_assets(String.t()) :: [String.t()]
  def image_assets(source) do
    # `asset :cover, :image` — or `asset(:cover, :image)`, as a formatter
    # that does not know the DSL writes it.
    ~r/\basset[\s(]+:(\w+)\s*,\s*:image\b/
    |> Regex.scan(source, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc "The image asset fields of every loaded Blueprint."
  @spec image_assets() :: [String.t()]
  def image_assets do
    Brando.Blueprint.list_blueprints()
    |> Enum.flat_map(fn blueprint ->
      blueprint
      |> Brando.Blueprint.Assets.__assets__()
      |> Enum.filter(&(&1.type == :image))
      |> Enum.map(&to_string(&1.name))
    end)
    |> Enum.uniq()
  rescue
    _ -> []
  end

  @doc """
  Lines of Elixir, HEEx or EEx that read `alt`, `title` or `credits` off an
  image — `@entry.cover.alt`, `image.title`. Lines that already call
  `Brando.Images.text/3` or `resolve_texts/2` are left out.
  """
  @spec scan_code(String.t(), [String.t()]) :: [finding()]
  def scan_code(content, assets \\ []) do
    pattern = receiver_pattern(assets)

    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _number} ->
      Regex.match?(pattern, line) and not String.contains?(line, ["Images.text(", "resolve_texts("])
    end)
    |> Enum.map(fn {line, number} -> %{line: number, text: String.trim(line)} end)
  end

  @doc """
  Liquid output tags (`{{ … }}`) that print an image's `alt`, `title` or
  `credits` without the `i18n` filter, which picks the page's language.
  """
  @spec scan_liquid(String.t(), [String.t()]) :: [finding()]
  def scan_liquid(content, assets \\ []) do
    pattern = receiver_pattern(assets)

    ~r/\{\{-?(.*?)-?\}\}/s
    |> Regex.scan(content, return: :index)
    |> Enum.flat_map(fn [{start, length} | _] ->
      tag = binary_part(content, start, length)

      if Regex.match?(pattern, tag) and not Regex.match?(~r/\|\s*i18n\b/, tag) do
        line = content |> binary_part(0, start) |> String.split("\n") |> length()
        [%{line: line, text: tag}]
      else
        []
      end
    end)
  end

  defp receiver_pattern(assets) do
    names = (@common_receivers ++ assets) |> Enum.uniq() |> Enum.map_join("|", &Regex.escape/1)
    ~r/(?<![\w.])@?(?:[a-z_]\w*\.)*(?:#{names})\.(?:#{@fields})\b/
  end
end
