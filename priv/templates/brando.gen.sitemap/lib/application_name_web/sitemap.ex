defmodule <%= web_module %>.Sitemap do
  import Brando.Sitemap
  alias Brando.Pages
  alias <%= web_module %>.Endpoint
  alias <%= web_module %>.Router.Helpers, as: Routes

  sitemap "pages" do
    Pages.list_pages(
      %{
        filter: %{has_url: true},
        status: :published,
        select: {:struct, [:title, :uri, :updated_at, :language]},
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
