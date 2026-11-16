defmodule <%= web_module %>.SSG do
  import Brando.SSG

  alias Brando.Pages
  alias Brando.Pages.Page

  # Published pages with a URL, in the site's languages
  urls :pages do
    {:ok, pages} =
      Pages.list_pages(%{
        filter: Page.__url_filter__(),
        status: :published,
        select: {:struct, [:uri, :language, :has_url]}
      })

    pages
    |> Brando.Sitemap.in_site_languages()
    |> Enum.map(&Page.__absolute_url__/1)
  end
end
