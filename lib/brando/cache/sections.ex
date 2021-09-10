defmodule Brando.Cache.Sections do
  @moduledoc """
  Interaction with sections cache
  """
  alias Brando.Content

  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get sections from cache
  """
  @spec get :: binary() | nil
  def get do
    case Cachex.get(:cache, :sections_css) do
      {:ok, css} -> css
      css -> css
    end
  end

  @doc """
  Set initial section cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    sections_css = get_sections()
    Cachex.put(:cache, :sections_css, sections_css)
  end

  @doc """
  Update section cache
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, section}) do
    sections_css = get_sections()
    Cachex.update(:cache, :sections_css, sections_css)
    {:ok, section}
  end

  def update({:error, changeset}), do: {:error, changeset}

  defp get_sections do
    {:ok, sections} = Content.list_sections()

    Enum.reduce(sections, [], fn section, acc ->
      [section.css | acc]
    end)
    |> Enum.reject(&(&1 == nil))
    |> Enum.join("\r\n")
    |> minify_css
  end

  @css_minification_regex ~r/( "(?:[^"\\]+|\\.)*" | '(?:[^'\\]+|\\.)*' )|\s* ; \s* ( } ) \s*|\s* ( [*$~^|]?= | [{};,>~] | !important\b ) \s*|\s*([+-])\s*(?=[^}]*{)|( [[(:] ) \s+|\s+ ( [])] )|\s+(:)(?![^\}]*\{)|^ \s+ | \s+ \z|(\s)\s+/si

  def minify_css(css) do
    Regex.replace(@css_minification_regex, css, "\\1\\2\\3\\4\\5\\6\\7\\8")
  end
end
