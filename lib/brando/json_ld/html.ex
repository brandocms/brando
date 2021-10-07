defmodule Brando.JSONLD.HTML do
  @moduledoc """
  HTML functions for rendering JSONLD data
  """

  alias Brando.JSONLD
  import Phoenix.HTML
  import Phoenix.HTML.Tag

  @type conn :: Plug.Conn.t()

  @doc """
  Renders all JSON LD
  """
  @spec render_json_ld(conn) :: [{:safe, term}]
  def render_json_ld(%{assigns: %{language: language}} = conn) do
    cached_identity = Brando.Cache.Identity.get(language)
    cached_seo = Brando.Cache.SEO.get(language)

    breadcrumbs = render_json_ld(:breadcrumbs, conn)

    identity =
      render_json_ld(String.to_existing_atom(cached_identity.type), {cached_identity, cached_seo})

    entity = render_json_ld(:entity, conn)

    [breadcrumbs, identity, entity]
  end

  def render_json_ld(:breadcrumbs, %{assigns: %{json_ld_breadcrumbs: breadcrumbs}}) do
    breadcrumb_json =
      Enum.map(Enum.with_index(breadcrumbs), fn {{name, url}, idx} ->
        JSONLD.Schema.ListItem.build(idx + 1, name, url)
      end)
      |> JSONLD.Schema.BreadcrumbList.build()
      |> JSONLD.to_json()

    content_tag(:script, raw(breadcrumb_json), type: "application/ld+json")
  end

  def render_json_ld(:corporation, {cached_identity, cached_seo}) do
    corporation_json =
      {cached_identity, cached_seo}
      |> JSONLD.Schema.Corporation.build()
      |> JSONLD.to_json()

    content_tag(:script, raw(corporation_json), type: "application/ld+json")
  end

  def render_json_ld(:organization, {cached_identity, cached_seo}) do
    organization_json =
      {cached_identity, cached_seo}
      |> JSONLD.Schema.Organization.build()
      |> JSONLD.to_json()

    content_tag(:script, raw(organization_json), type: "application/ld+json")
  end

  def render_json_ld(:entity, %{assigns: %{json_ld_entity: entity}}) do
    entity_json = JSONLD.to_json(entity)
    content_tag(:script, raw(entity_json), type: "application/ld+json")
  end

  def render_json_ld(_, _), do: []
end
