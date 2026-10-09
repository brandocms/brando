# Deprecated names for the public controllers, which moved to `BrandoWeb` in
# 0.55 (#2833). A router that still routes to an old name keeps working and
# logs a warning on the first request; removed in 0.57.

defmodule Brando.SEOController do
  @moduledoc false
  @behaviour Plug

  alias Brando.Deprecated.RenamedModules

  @impl Plug
  def init(action) do
    RenamedModules.warn(__MODULE__)
    BrandoWeb.SEOController.init(action)
  end

  @impl Plug
  defdelegate call(conn, action), to: BrandoWeb.SEOController

  @deprecated "Use BrandoWeb.SEOController.robots/2 instead"
  defdelegate robots(conn, params), to: BrandoWeb.SEOController

  @deprecated "Use Brando.SEO.Robots.add_sitemap/2 instead"
  defdelegate add_sitemap(robots, url), to: Brando.SEO.Robots
end

defmodule Brando.SitemapController do
  @moduledoc false
  @behaviour Plug

  alias Brando.Deprecated.RenamedModules

  @impl Plug
  def init(action) do
    RenamedModules.warn(__MODULE__)
    BrandoWeb.SitemapController.init(action)
  end

  @impl Plug
  defdelegate call(conn, action), to: BrandoWeb.SitemapController

  @deprecated "Use BrandoWeb.SitemapController.show/2 instead"
  defdelegate show(conn, params), to: BrandoWeb.SitemapController
end

defmodule Brando.PreviewController do
  @moduledoc false
  @behaviour Plug

  alias Brando.Deprecated.RenamedModules

  @impl Plug
  def init(action) do
    RenamedModules.warn(__MODULE__)
    BrandoWeb.PreviewController.init(action)
  end

  @impl Plug
  defdelegate call(conn, action), to: BrandoWeb.PreviewController

  @deprecated "Use BrandoWeb.PreviewController.show/2 instead"
  defdelegate show(conn, params), to: BrandoWeb.PreviewController
end
