defmodule <%= web_module %>.Sitemap do
  import Brando.Sitemap
  alias Brando.Pages
  alias Brando.Pages.Page

  sitemap "pages" do
    Pages.list_pages(
      %{
        filter: Page.__url_filter__(),
        status: :published,
        select: {:struct, [:title, :uri, :content_modified_at, :edited_at, :updated_at, :language, :has_url]},
        order: "asc language, asc title"
      },
      :stream
    )
    |> Stream.map(fn page ->
      page_url = Brando.HTML.absolute_url(page, :with_host)

      url(%{
        priority: 0.7,
        changefreq: :weekly,
        loc: page_url,
        lastmod: Brando.Blueprint.Value.modified_at(page)
      })
    end)
  end
end
