defmodule BrandoIntegrationWeb.Sitemap do
  import Brando.Sitemap
  alias Brando.Pages

  sitemap "pages" do
    Pages.list_pages(
      %{filter: %{has_url: true}, status: :published, select: [:title, :uri, :updated_at]},
      :stream
    )
    |> Stream.map(fn _entry ->
      page_url = "http://localhost/index"

      lastmod = ~N[2023-08-10 10:00:00]

      url(%{
        priority: 0.7,
        changefreq: :weekly,
        loc: page_url,
        lastmod: lastmod
      })
    end)
  end
end

defmodule Brando.SitemapTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Sitemap
  alias Brando.Pages
  alias Sitemapper.URL

  test "check_lastmod/1" do
    url = %URL{lastmod: ~N[2023-12-20 14:00:00], loc: "/"}
    checked_url = Sitemap.check_lastmod(url)
    assert DateTime.to_iso8601(checked_url.lastmod) == "2023-12-20T15:00:00+01:00"
    url = %URL{lastmod: checked_url.lastmod, loc: "/"}
    checked_url = Sitemap.check_lastmod(url)
    assert DateTime.to_iso8601(checked_url.lastmod) == "2023-12-20T15:00:00+01:00"
  end

  test "sitemap/1" do
    usr = Factory.insert(:random_user)

    {:ok, _p1} =
      Pages.create_page(
        Factory.params_for(:page, title: "Title English", language: :en),
        usr
      )

    assert Sitemap.exists?()
    assert BrandoIntegrationWeb.Sitemap.__info__(:functions) == [__sitemap_for_pages__: 0]
    assert {:ok, _} = Sitemap.generate_sitemap(gzip: false)

    sitemap_index_path = Path.join([Brando.config(:media_path), "sitemaps", "sitemap.xml"])
    sitemap_index = File.read!(sitemap_index_path)

    assert sitemap_index =~ "<loc>http://localhost/sitemaps/sitemap-00001.xml</loc>"

    sitemap_path = Path.join([Brando.config(:media_path), "sitemaps", "sitemap-00001.xml"])
    sitemap = File.read!(sitemap_path)

    assert sitemap =~
             "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd\" xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n<url>\n  <loc>http://localhost/index</loc>\n  <lastmod>2023-08-10T12:00:00+02:00</lastmod>\n  <changefreq>weekly</changefreq>\n  <priority>0.7</priority>\n</url>\n</urlset>\n"
  end
end
