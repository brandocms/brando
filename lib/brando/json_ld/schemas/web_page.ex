defmodule Brando.JSONLD.Schema.WebPage do
  @moduledoc """
  WebPage schema.

  Auto-generated for every page render. Connects identity and website
  to the page-level content entity via @id references.

  Supports WebPage subtypes: AboutPage, ContactPage, CollectionPage,
  ItemPage, ProfilePage, SearchResultsPage.
  """

  @derive Jason.Encoder
  defstruct "@type": "WebPage",
            "@id": nil,
            url: nil,
            name: nil,
            description: nil,
            inLanguage: nil,
            isPartOf: nil,
            breadcrumb: nil,
            primaryImageOfPage: nil

  @doc """
  Builds a WebPage entity from conn data.
  """
  def build(conn, _cached_identity, _cached_seo) do
    url = Brando.Utils.current_url(conn)
    type = Map.get(conn.assigns, :json_ld_page_type, "WebPage")

    %__MODULE__{
      "@type": type,
      "@id": Path.join(url, "#webpage"),
      url: url,
      name: conn.assigns[:page_title],
      inLanguage: conn.assigns[:language],
      isPartOf: %{"@id": Path.join(Brando.Utils.hostname(), "#website")},
      breadcrumb: build_breadcrumb_ref(conn)
    }
  end

  defp build_breadcrumb_ref(%{assigns: %{json_ld_breadcrumbs: _}}) do
    %{"@id": "#{Brando.Utils.hostname()}/#breadcrumb"}
  end

  defp build_breadcrumb_ref(_), do: nil
end
