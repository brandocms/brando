defmodule Brando.JSONLD.HTML do
  @moduledoc """
  HTML functions for rendering JSONLD data
  """

  alias Brando.JSONLD
  import Phoenix.HTML
  import Phoenix.LiveView.Helpers

  @type conn :: Plug.Conn.t()

  @doc """
  Renders all JSON LD
  """
  def render_json_ld(%{conn: %{assigns: %{language: language} = conn}} = assigns) do
    cached_identity = Brando.Cache.Identity.get(language)
    cached_identity_type = String.to_existing_atom(cached_identity.type)
    cached_seo = Brando.Cache.SEO.get(language)

    breadcrumbs = render_json_ld(:breadcrumbs, conn)
    identity = render_json_ld(cached_identity_type, {cached_identity, cached_seo})
    entity = render_json_ld(:entity, conn)

    ~H"""
    <%= if breadcrumbs != "" do %><script type="application/ld+json">
      <%= breadcrumbs %>
    </script><% end %>
    <%= if identity != "" do %><script type="application/ld+json">
      <%= identity %>
    </script><% end %>
    <%= if entity != "" do %><script type="application/ld+json">
      <%= entity %>
    </script><% end %>
    """
  end

  def render_json_ld(:breadcrumbs, %{assigns: %{json_ld_breadcrumbs: breadcrumbs}}) do
    breadcrumb_json =
      Enum.map(Enum.with_index(breadcrumbs), fn {{name, url}, idx} ->
        JSONLD.Schema.ListItem.build(idx + 1, name, url)
      end)
      |> JSONLD.Schema.BreadcrumbList.build()
      |> JSONLD.to_json()

    raw(breadcrumb_json)
  end

  def render_json_ld(:corporation, {cached_identity, cached_seo}) do
    corporation_json =
      {cached_identity, cached_seo}
      |> JSONLD.Schema.Corporation.build()
      |> JSONLD.to_json()

    raw(corporation_json)
  end

  def render_json_ld(:organization, {cached_identity, cached_seo}) do
    organization_json =
      {cached_identity, cached_seo}
      |> JSONLD.Schema.Organization.build()
      |> JSONLD.to_json()

    raw(organization_json)
  end

  def render_json_ld(:entity, %{assigns: %{json_ld_entity: entity}}) do
    entity_json = JSONLD.to_json(entity)
    raw(entity_json)
  end

  def render_json_ld(_, _), do: ""
end
