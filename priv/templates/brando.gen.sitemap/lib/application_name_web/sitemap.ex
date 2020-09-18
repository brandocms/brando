defmodule <%= web_module %>.Sitemap do
  import Brando.Sitemap
  alias Brando.Pages
  alias <%= web_module %>.Endpoint
  alias <%= web_module %>.Router.Helpers, as: Routes

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
