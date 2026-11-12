defmodule <%= web_module %>.LivePreview do
  use Brando.LivePreview

  alias Brando.Pages

  # Renders a page as <%= web_module %>.CMS.PageController does: in its site's
  # layout and templates (Brando.Site.Frontend), with the identity, navigation
  # and footer partials its pipeline and action assign, and the site's assigns.
  preview_target Pages.Page do
    label "Page"
    layout fn _page -> Brando.Site.Frontend.root_layout({<%= web_module %>.CMS.Layouts, :root}) end
    template fn page -> {Brando.Site.Frontend.page_html(), page.template} end
    site_assigns true
    template_section fn page -> page.uri end
    template_prop :page

    # The assigns are cached for the preview session and follow the page's
    # language; the header and footer they fill sit outside <main>, which is
    # all an ordinary update replaces.
    rerender_on_change [[:language]]
    reassign_on_change [
      {:identity, [:language]},
      {:navigation, [:language]},
      {:partials, [:language]}
    ]

    assign :identity, fn _page, language -> Brando.Cache.Identity.get(to_string(language)) end

    assign :navigation, fn _page, language ->
      Brando.Cache.Navigation.get("main", to_string(language))
    end

    assign :partials, fn _page, language ->
      {:ok, partials} =
        Pages.get_fragments(%{filter: %{parent_key: "partials", language: language}})

      partials
    end
  end
end
