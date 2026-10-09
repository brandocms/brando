defmodule BrandoWeb.SEOControllerTest do
  use ExUnit.Case, async: true

  alias BrandoWeb.SEOController

  @url "https://example.com/sitemaps/sitemap.xml.gz"

  test "add_sitemap/2 names the sitemap after the rules" do
    assert SEOController.add_sitemap("User-agent: *\nDisallow: /admin/\n", @url) ==
             "User-agent: *\nDisallow: /admin/\n\nSitemap: #{@url}\n"
  end

  test "add_sitemap/2 leaves robots alone without a sitemap" do
    assert SEOController.add_sitemap("User-agent: *\n", nil) == "User-agent: *\n"
  end

  test "add_sitemap/2 keeps a sitemap the editors named" do
    robots = "User-agent: *\nsitemap: https://example.com/other.xml\n"
    assert SEOController.add_sitemap(robots, @url) == robots
  end
end
