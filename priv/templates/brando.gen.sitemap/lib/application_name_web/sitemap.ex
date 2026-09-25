defmodule <%= web_module %>.Sitemap do
  import Brando.Sitemap
  alias Brando.Pages
  alias Brando.Pages.Page

  sitemap "pages" do
    Pages.list_pages(
      %{
        filter: Page.__url_filter__(),
        status: :published,
        select: {:struct, [:title, :uri, :updated_at, :language, :has_url]},
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
        lastmod:
          page.updated_at
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.shift_zone!(Brando.timezone())
      })
    end)
  end
end
