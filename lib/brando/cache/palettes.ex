defmodule Brando.Cache.Palettes do
  @moduledoc """
  Interaction with palettes cache
  """
  alias Brando.Content

  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get palettes from cache
  """
  @spec get :: binary() | nil
  def get do
    case Cachex.get(:cache, :palettes_css) do
      {:ok, css} -> css
      css -> css
    end
  end

  @doc """
  Set initial palette cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    palettes_css = get_palettes()
    Cachex.put(:cache, :palettes_css, palettes_css)
  end

  @doc """
  Update palette cache
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, palette}) do
    palettes_css = get_palettes()
    Cachex.update(:cache, :palettes_css, palettes_css)
    {:ok, palette}
  end

  def update({:error, changeset}), do: {:error, changeset}

  defp get_palettes do
    {:ok, palettes} = Content.list_palettes()

    Enum.reduce(palettes, [], fn palette, acc ->
      [namespace_css(palette) | acc]
    end)
    |> Enum.reject(&(&1 == nil))
    |> Enum.join("\r\n")
    |> minify_css
  end

  defp namespace_css(%{global: true} = palette) do
    Enum.map(palette.colors, fn color ->
      "--palette-#{palette.namespace}-#{palette.key}-#{color.key}: #{color.hex_value};"
    end)
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

  @css_minification_regex ~r/( "(?:[^"\\]+|\\.)*" | '(?:[^'\\]+|\\.)*' )|\s* ; \s* ( } ) \s*|\s* ( [*$~^|]?= | [{};,>~] | !important\b ) \s*|\s*([+-])\s*(?=[^}]*{)|( [[(:] ) \s+|\s+ ( [])] )|\s+(:)(?![^\}]*\{)|^ \s+ | \s+ \z|(\s)\s+/si

  def minify_css(css) do
    Regex.replace(@css_minification_regex, css, "\\1\\2\\3\\4\\5\\6\\7\\8")
  end
end
