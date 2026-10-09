defmodule BrandoWeb.SEOController do
  @moduledoc """
  Serves the site's `robots.txt` (routed by `Brando.Router.page_routes/1`).
  """
  use BrandoAdmin, :controller

  alias Brando.Cache
  alias Brando.SEO.Robots
  alias Plug.Conn

  @doc """
  Serves `robots.txt`: the editors' robots text, the AI crawler policy and
  the sitemap. See `Brando.SEO.Robots`.
  """
  def robots(%{assigns: %{language: language}} = conn, _) do
    robots =
      language
      |> Cache.SEO.get()
      |> Robots.render(sitemap_url())

    conn
    |> Conn.put_resp_content_type("text/plain")
    |> Conn.resp(200, robots)
    |> Conn.send_resp()
  end

  @doc """
  Names the sitemap at the end of `robots`, unless there is none or the
  editors' text already names one.
  """
  defdelegate add_sitemap(robots, url), to: Robots

  # Only once one has been generated: a fresh install has the module but
  # waits for the nightly job, and a crawler sent to a 404 learns nothing
  defp sitemap_url do
    index = Path.join([Brando.Tenant.Storage.current_media_root(), "sitemaps", "sitemap.xml.gz"])

    if Brando.Sitemap.exists?() and File.exists?(index) do
      Brando.Utils.hostname("sitemaps/sitemap.xml.gz")
    end
  end
end
