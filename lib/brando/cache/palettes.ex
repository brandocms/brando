defmodule Brando.Cache.Palettes do
  @moduledoc """
  Interaction with palettes cache
  """
  alias Brando.Content

  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get palettes CSS from cache
  """
  @spec get_css :: binary() | nil
  def get_css do
    case Cachex.get(:cache, :palettes_css) do
      {:ok, css} -> css
      css -> css
    end
  end

  def get do
    case Cachex.get(:cache, :palettes) do
      {:ok, palettes} -> palettes
      palettes -> palettes
    end
  end

  @doc """
  Set initial palette cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    {:ok, palettes} = get_palettes()
    palettes_css = get_palettes_css(palettes)
    Cachex.put(:cache, :palettes, palettes)
    Cachex.put(:cache, :palettes_css, palettes_css)
  end

  @doc """
  Update palette cache
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, palette}) do
    {:ok, palettes} = get_palettes()
    palettes_css = get_palettes_css(palettes)
    Cachex.put(:cache, :palettes, palettes)
    Cachex.update(:cache, :palettes_css, palettes_css)
    {:ok, palette}
  end

  def update({:error, changeset}), do: {:error, changeset}

  defp get_palettes do
    Content.list_palettes()
  end

  defp get_palettes_css(palettes) do
    process_palettes(palettes)
  end

  defp process_palettes(palettes) do
    palettes
    |> Enum.reduce([], fn palette, acc ->
      [namespace_css(palette) | acc]
    end)
    |> Enum.reject(&(&1 == nil))
    |> Enum.join("\r\n")
    |> minify_css()
    |> Phoenix.HTML.raw()
  end

  defp namespace_css(%{global: true} = palette) do
    palette_vars =
      Enum.map(palette.colors, fn color ->
        "--palette-#{palette.namespace}-#{palette.key}-#{color.key}: #{color.hex_value};"
      end)

    ":root {#{palette_vars}}"
  end

  defp namespace_css(%{namespace: namespace, key: key} = palette) do
    opening_tag = [~s([b-section="#{namespace}-#{key}"] {)]
    closing_tag = ["}"]

    colors =
      Enum.map(palette.colors, fn color ->
        "--#{color.key}: #{color.hex_value};"
      end)

    opening_tag ++ colors ++ closing_tag
  end

  @doc """
  Minifies CSS by removing unnecessary whitespace and formatting.

  ## Examples

      iex> Brando.Cache.Palettes.minify_css("body { color: red; }")
      "body{color:red;}"

  """
  def minify_css(css) do
    css_minification_regex =
      ~r/( "(?:[^"\\]+|\\.)*" | '(?:[^'\\]+|\\.)*' )|\s* ; \s* ( } ) \s*|\s* ( [*$~^|]?= | [{};,>~] | !important\b ) \s*|\s*([+-])\s*(?=[^}]*{)|( [[(:] ) \s+|\s+ ( [])] )|\s+(:)(?![^\}]*\{)|^ \s+ | \s+ \z|(\s)\s+/si

    Regex.replace(css_minification_regex, css, "\\1\\2\\3\\4\\5\\6\\7\\8")
  end
end
