defmodule Brando.JSONLD.HTML do
  @moduledoc """
  HTML functions for rendering JSON-LD data as a single @graph document.
  """

  import Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  alias Brando.JSONLD

  @doc """
  Renders all JSON-LD entities as a single `@graph` script tag.
  """
  def render_json_ld(%{conn: %{assigns: %{language: language}} = conn} = assigns) do
    cached_identity = Brando.Cache.Identity.get(language)

    if map_size(cached_identity) > 0 do
      cached_seo = Brando.Cache.SEO.get(language)

      entities = [
        build_identity(cached_identity.type, cached_identity, cached_seo),
        build_website(cached_identity, cached_seo),
        build_webpage(conn, cached_identity, cached_seo),
        build_breadcrumbs(conn),
        build_content_entity(conn)
      ]

      assigns = assign(assigns, :graph_json, encode_graph(entities))

      ~H"""
      <script type="application/ld+json">
        <%= @graph_json %>
      </script>
      """
    else
      ~H""
    end
  end

  def render_json_ld(assigns), do: ~H""

  defp build_identity(type, cached_identity, cached_seo) do
    identity_schema_module(type).build({cached_identity, cached_seo})
  end

  defp identity_schema_module("organization"), do: JSONLD.Schema.Organization
  defp identity_schema_module("corporation"), do: JSONLD.Schema.Corporation
  defp identity_schema_module("professional_service"), do: JSONLD.Schema.ProfessionalService
  defp identity_schema_module("local_business"), do: JSONLD.Schema.LocalBusiness
  defp identity_schema_module("restaurant"), do: JSONLD.Schema.Restaurant

  defp build_website(cached_identity, cached_seo) do
    JSONLD.Schema.WebSite.build({cached_identity, cached_seo})
  end

  defp build_webpage(conn, cached_identity, cached_seo) do
    JSONLD.Schema.WebPage.build(conn, cached_identity, cached_seo)
  end

  defp build_breadcrumbs(%{assigns: %{json_ld_breadcrumbs: breadcrumbs}}) do
    breadcrumbs
    |> Enum.with_index()
    |> Enum.map(fn {{name, url}, idx} ->
      JSONLD.Schema.ListItem.build(idx + 1, name, url)
    end)
    |> JSONLD.Schema.BreadcrumbList.build()
  end

  defp build_breadcrumbs(_), do: nil

  defp build_content_entity(%{assigns: %{json_ld_entities: entities}}), do: entities
  defp build_content_entity(%{assigns: %{json_ld_entity: entity}}), do: entity
  defp build_content_entity(_), do: nil

  # Safe: to_graph_json returns JSON from Jason.encode!/1 — no user HTML content.
  # Content is injected inside <script type="application/ld+json"> which is not
  # parsed as HTML by browsers.
  defp encode_graph(entities), do: raw(JSONLD.to_graph_json(entities))
end
