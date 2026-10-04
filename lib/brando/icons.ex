defmodule Brando.Icons do
  @moduledoc """
  The Lucide icon set Brando renders, drawn by one generated stylesheet.

  Icons are vendored into `priv/lucide/icons.json` by
  `mix brando.lucide.update` and compiled into this module. Names are bare
  Lucide names (`house`, `file-text`). `resolve/1` also accepts Lucide's
  deprecated aliases and the `hero-*` names Brando used before Lucide (see
  `Brando.Icons.Legacy`), so content saved with old names keeps rendering.

  `Brando.HTML.Icon.icon/1` renders `<span data-icon class="lucide-name">`.
  The stylesheet at `stylesheet_path/0`, which `Brando.Plug.Icons` serves with
  immutable caching, draws it as a CSS mask. One node and one dynamic
  attribute per icon keeps the block editor's mount small: an SVG sprite
  `<use>` cost 13% on a 115-block entry.
  """

  alias Brando.Icons.Legacy

  @source Path.join([__DIR__, "..", "..", "priv", "lucide", "icons.json"]) |> Path.expand()
  @external_resource @source

  %{"version" => version, "icons" => icons, "aliases" => aliases, "tags" => tags} =
    @source |> File.read!() |> Jason.decode!()

  @version version
  @icons icons
  @aliases aliases
  @tags tags
  @names icons |> Map.keys() |> Enum.sort()

  # One rule per icon, keyed on a class so the browser matches it in constant
  # time: `.lucide-house{--lucide:url("data:…")}`. `[data-icon]` paints
  # `currentColor` through that mask. This is the Phoenix generator's Heroicons
  # technique: one DOM node and one dynamic attribute per icon.
  @svg_open ~s(<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'>)

  @stylesheet IO.iodata_to_binary([
                ":where([data-icon]){display:inline-block;flex:none;width:1.25rem;height:1.25rem;",
                "vertical-align:middle;background-color:currentColor;",
                "-webkit-mask:var(--lucide) center/contain no-repeat;mask:var(--lucide) center/contain no-repeat}",
                for name <- @names do
                  body = icons |> Map.fetch!(name) |> String.replace("\"", "'")
                  [".lucide-", name, ~s[{--lucide:url("data:image/svg+xml;utf8,], @svg_open, body, ~s[</svg>")}]]
                end
              ])

  @stylesheet_gzip :zlib.gzip(@stylesheet)
  @hash :sha256 |> :crypto.hash(@stylesheet) |> Base.encode16(case: :lower) |> binary_part(0, 12)
  @stylesheet_file "lucide-#{version}-#{@hash}.css"
  @path_prefix "/__brando/icons"

  @doc "The vendored Lucide version."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Every current Lucide icon name, sorted."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc """
  Returns `true` when `name` is a current Lucide icon name.

  Aliases and `hero-*` names return `false`; use `resolve/1` for those.
  """
  @spec exists?(term()) :: boolean()
  def exists?(name) when is_binary(name), do: is_map_key(@icons, name)
  def exists?(_name), do: false

  @doc """
  Resolves a name to a current Lucide icon name.

  Accepts current names, Lucide's deprecated aliases and legacy `hero-*`
  names. Returns `:error` for anything else.

      iex> Brando.Icons.resolve("house")
      {:ok, "house"}

      iex> Brando.Icons.resolve("home")
      {:ok, "house"}

      iex> Brando.Icons.resolve("hero-x-mark-solid")
      {:ok, "x"}

      iex> Brando.Icons.resolve("nope")
      :error
  """
  @spec resolve(term()) :: {:ok, String.t()} | :error
  def resolve(name) when is_binary(name) do
    candidate = Legacy.lookup(name) || name

    cond do
      is_map_key(@icons, candidate) -> {:ok, candidate}
      is_map_key(@aliases, candidate) -> {:ok, Map.fetch!(@aliases, candidate)}
      true -> :error
    end
  end

  def resolve(_name), do: :error

  @doc "Search tags per icon name, for an icon picker."
  @spec tags() :: %{String.t() => [String.t()]}
  def tags, do: @tags

  @doc "The stylesheet that draws every icon, a mask rule per `.lucide-<name>` class."
  @spec stylesheet() :: binary()
  def stylesheet, do: @stylesheet

  @doc "`stylesheet/0`, gzipped at compile time."
  @spec stylesheet_gzip() :: binary()
  def stylesheet_gzip, do: @stylesheet_gzip

  @doc "The stylesheet's file name. It changes whenever the stylesheet does."
  @spec stylesheet_file() :: String.t()
  def stylesheet_file, do: @stylesheet_file

  @doc """
  The URL path of the stylesheet. It carries the Lucide version and a content
  hash, so it can be cached forever.
  """
  @spec stylesheet_path() :: String.t()
  def stylesheet_path, do: @path_prefix <> "/" <> @stylesheet_file
end
