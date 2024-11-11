defmodule Brando.Sitemap do
  @moduledoc """
  Sitemaps

  ## Usage

  Start by creating a `MyAppWeb.Sitemap` module and import Brando Sitemap:

      defmodule MyAppWeb.Sitemap do
        import Brando.Sitemap
        alias Brando.Pages
        alias MyAppWeb.Endpoint
        alias MyAppWeb.Router.Helpers, as: Routes

        sitemap "pages" do
          Pages.list_pages(%{status: :published, select: [:uri, :updated_at]}, :stream)
          |> Stream.map(fn e ->
            page_url = Routes.page_url(Endpoint, :show, [e.uri])

            url(%{
              priority: 0.7,
              changefreq: :weekly,
              loc: page_url,
              lastmod: e.updated_at
            })
          end)
        end
      end

  Sitemaps are regenerated by an Oban worker at 2am every night.
  To generate an initial sitemap, call `Brando.Sitemap.generate_sitemap/0`
  """

  @doc """
  Convenience macro for creating a sitemap function
  """
  defmacro sitemap(key, do: block) do
    quote do
      def unquote(:"__sitemap_for_#{key}__")() do
        unquote(block)
      end
    end
  end

  @doc """
  Convert map to Sitemapper.URL
  """
  def url(map), do: struct!(Sitemapper.URL, map) |> check_lastmod()

  @doc """
  Validate that the lastmod has a timezone, or else Google might
  refuse to read it.
  """
  def check_lastmod(%Sitemapper.URL{lastmod: nil} = url), do: url

  def check_lastmod(%Sitemapper.URL{lastmod: %NaiveDateTime{} = lastmod} = url) do
    updated_lastmod =
      lastmod
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.shift_zone!(Brando.timezone())

    Map.put(url, :lastmod, updated_lastmod)
  end

  def check_lastmod(%Sitemapper.URL{lastmod: %DateTime{}} = url), do: url

  @doc """
  Check if sitemap exists
  """
  def exists?() do
    sitemap_module = Brando.web_module(Sitemap)
    function_exported?(sitemap_module, :__info__, 1)
  end

  @doc """
  Generate sitemaps

  Gathers all sitemap functions, generates and persists to disk.

  ## Options

  Options are passed on to Sitemapper.

    * `:gzip` (default: `true`) - Sets whether the files are gzipped

  """
  def generate_sitemap(opts \\ []) do
    sitemap_module = Brando.web_module(Sitemap)
    sitemap_functions = sitemap_module.__info__(:functions)
    entries = Stream.flat_map(sitemap_functions, &apply(sitemap_module, elem(&1, 0), []))

    sitemap_path = Path.join([Brando.config(:media_path), "sitemaps"])
    File.mkdir_p!(sitemap_path)

    default_opts = [
      sitemap_url: Path.join(Brando.endpoint().url(), "sitemaps"),
      store: Sitemapper.FileStore,
      store_config: [
        path: sitemap_path
      ]
    ]

    opts = Keyword.merge(default_opts, opts)

    Brando.Repo.transaction(fn ->
      entries
      |> Sitemapper.generate(opts)
      |> Sitemapper.persist(opts)
      |> Enum.to_list()
    end)
  rescue
    UndefinedFunctionError ->
      :ok
  end
end
