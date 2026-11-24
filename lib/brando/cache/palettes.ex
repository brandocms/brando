defmodule Brando.Cache.Palettes do
  @moduledoc """
  Interaction with palettes cache
  """
  use Brando.Tracing.Decorator

  alias Brando.Cache
  alias Brando.Content
  alias Brando.Content.Palette
  alias Brando.Content.SharedLibrary

  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get palettes CSS from cache
  """
  @spec get_css :: binary() | nil
  def get_css do
    case Cache.get_site(:palettes_css) do
      nil -> filled(:palettes_css)
      css -> css
    end
  end

  def get do
    case Cache.get_site(:palettes) do
      nil -> filled(:palettes)
      palettes -> palettes
    end
  end

  defp filled(key), do: if(Brando.Tenant.outside_site?(), do: nil, else: Cache.fill(:palettes)[key])

  @doc """
  Set initial palette cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  @decorate span("brando.cache.set_palettes")
  def set do
    if Brando.Tenant.outside_site?() do
      {:ok, false}
    else
      Cache.fill(:palettes)
      {:ok, true}
    end
  end

  @doc false
  # What `Brando.Cache` stores for the cache. `palettes` are the environment's own, for the admin's colour inputs,
  # which look them up by local id. The CSS holds every palette the site's
  # content resolves (`SharedLibrary.list_for_rendering/3`): its own, and the
  # shared ones enabled for it or used by its blocks, a customized one in
  # place of its shared one. Its own are all kept, and a shared one whose
  # namespace and key one of them has is left out. It reads the allowlist
  # from the database: on another node, the refresh that forgets the cached
  # one may run after the one that rebuilds this cache.
  def load do
    {:ok, palettes} = Content.list_palettes()

    {own, shared} =
      :palette
      |> SharedLibrary.list_for_current_tenant(cached_allowlist: false)
      |> Enum.split_with(&(&1.library_origin == :local))

    owned = MapSet.new(own, &css_name/1)
    css_palettes = own ++ Enum.reject(shared, &MapSet.member?(owned, css_name(&1)))
    [palettes: palettes, palettes_css: process_palettes(css_palettes)]
  end

  defp css_name(palette), do: {palette.namespace, palette.key}

  @doc """
  Update palette cache, once the transaction around the caller has
  committed (`Brando.Cache.rebuild_after_commit/1`)
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, palette}) do
    Cache.rebuild_after_commit(:palettes)
    {:ok, palette}
  end

  def update({:error, changeset}), do: {:error, changeset}

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

  # Names are escaped and colours stored before values were checked left
  # out (`Palette.css_escape/1`, `Palette.css_colors/1`): the CSS is written
  # into the page's `<style>` as it is.
  defp namespace_css(%{global: true} = palette) do
    prefix = Palette.css_escape("palette-#{palette.namespace}-#{palette.key}-")

    palette_vars =
      Enum.map(Palette.css_colors(palette.colors), fn color ->
        "--#{prefix}#{Palette.css_escape(color.key)}: #{color.hex_value};"
      end)

    ":root {#{palette_vars}}"
  end

  defp namespace_css(%{namespace: namespace, key: key} = palette) do
    opening_tag = [~s([b-section="#{Palette.css_escape("#{namespace}-#{key}")}"] {)]
    closing_tag = ["}"]

    colors =
      Enum.map(Palette.css_colors(palette.colors), fn color ->
        "--#{Palette.css_escape(color.key)}: #{color.hex_value};"
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
