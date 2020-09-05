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
          Pages.list_pages(%{status: :published, select: [:slug, :updated_at]}, :stream)
          |> Stream.map(fn e ->
            page_url = Routes.page_url(Endpoint, :show, [e.slug])

            url(%{
              priority: 0.7,
              changefreq: :weekly,
              loc: page_url,
              lastmod: e.updated_at
            })
          end)
        end
      end
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
  def url(map), do: struct!(Sitemapper.URL, map)

  @doc """
  Generate sitemaps

  Gathers all sitemap functions, generates and persists to disk.
  """
  def generate_sitemap() do
    sitemap_module = Brando.web_module(Sitemap)
    sitemap_functions = sitemap_module.__info__(:functions)
    entries = Stream.flat_map(sitemap_functions, &apply(sitemap_module, elem(&1, 0), []))

    sitemap_path = Path.join([Brando.config(:media_path), "sitemaps"])
    File.mkdir_p!(sitemap_path)

    opts = [
      sitemap_url: Brando.endpoint().url,
      store: Sitemapper.FileStore,
      store_config: [
        path: sitemap_path
      ]
    ]

    Brando.repo().transaction(fn ->
      entries
      |> Sitemapper.generate(opts)
      |> Sitemapper.persist(opts)
      |> Enum.to_list()
    end)
  end
end
