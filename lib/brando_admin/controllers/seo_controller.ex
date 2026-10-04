defmodule Brando.SEOController do
  @moduledoc """
  Controller for i18n actions.
  """
  use BrandoAdmin, :controller

  alias Brando.Cache
  alias Plug.Conn

  @default_robots """
  User-agent: *
  Disallow: /admin/
  """

  @doc false
  def robots(%{assigns: %{language: language}} = conn, _) do
    seo = Cache.SEO.get(language)

    robots =
      seo
      |> Map.get(:robots)
      |> Kernel.||(@default_robots)
      |> add_sitemap(sitemap_url())

    conn
    |> Conn.resp(200, robots)
    |> Conn.send_resp()
  end

  @doc """
  Names the sitemap at the end of `robots`, unless there is none or the
  editors' text already names one.
  """
  def add_sitemap(robots, nil), do: robots

  def add_sitemap(robots, url) do
    if robots =~ ~r/^\s*sitemap\s*:/im do
      robots
    else
      String.trim_trailing(robots) <> "\n\nSitemap: #{url}\n"
    end
  end

  # Only once one has been generated: a fresh install has the module but
  # waits for the nightly job, and a crawler sent to a 404 learns nothing
  defp sitemap_url do
    index = Path.join([Brando.Tenant.Storage.current_media_root(), "sitemaps", "sitemap.xml.gz"])

    if Brando.Sitemap.exists?() and File.exists?(index) do
      Brando.Utils.hostname("sitemaps/sitemap.xml.gz")
    end
  end
end
