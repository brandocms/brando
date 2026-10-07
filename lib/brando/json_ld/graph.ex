defmodule Brando.JSONLD.Graph do
  @moduledoc """
  Assembles the entities of a page's JSON-LD `@graph`.

  `entities/1` is what `Brando.JSONLD.HTML.render_json_ld/1` emits for a
  request: the site's identity, the `WebSite`, the `WebPage`, breadcrumbs,
  the identity's services and whatever the controller added with
  `Brando.Plug.HTML.put_json_ld/4`.

  `for_entry/3` builds the same graph for an entry outside a request, the way
  the guide's controller does it: `put_title/2`, `put_breadcrumbs/2` and
  `put_json_ld/3` on a connection for the entry's URL. The admin's structured
  data inspector reads it from here, so what it shows is what the page emits.
  A controller that adds more (extra entities, its own breadcrumbs) emits more.
  """

  alias Brando.JSONLD
  alias Brando.Plug.HTML, as: PlugHTML

  @doc """
  The graph's entities for `conn`, or `[]` when the site has no identity in
  the connection's language.
  """
  @spec entities(Plug.Conn.t()) :: [term()]
  def entities(%{assigns: %{language: language}} = conn) do
    cached_identity = Brando.Cache.Identity.get(language)

    if map_size(cached_identity) > 0 do
      cached_seo = Brando.Cache.SEO.get(language)

      [
        build_identity(cached_identity.type, cached_identity, cached_seo),
        JSONLD.Schema.WebSite.build({cached_identity, cached_seo}),
        JSONLD.Schema.WebPage.build(conn, cached_identity, cached_seo),
        build_breadcrumbs(conn),
        Brando.Sites.Services.to_json_ld(cached_identity),
        build_content_entity(conn)
      ]
    else
      []
    end
  end

  def entities(_conn), do: []

  @doc """
  Builds, outside a request, the connection a controller holds after
  describing `entry` of `module`: its URL, language and title, its
  breadcrumbs when it has stored ones (pages), and its entity from the
  blueprint's `json_ld_schema`.

  ## Options

    * `:language` — defaults to the entry's language, then the site's default
    * `:path` — the page's path, defaulting to the entry's `absolute_url`
    * `:title` — the page title, defaulting to the entry's identifier title
  """
  @spec build_conn(module(), map(), keyword()) :: Plug.Conn.t()
  def build_conn(module, entry, opts \\ []) do
    language = Keyword.get_lazy(opts, :language, fn -> entry_language(entry) end)
    path = Keyword.get_lazy(opts, :path, fn -> path(module, entry) || "/" end)
    title = Keyword.get_lazy(opts, :title, fn -> title(module, entry) end)

    conn =
      %Plug.Conn{request_path: path, assigns: %{language: language}}
      |> PlugHTML.put_title(title)
      |> PlugHTML.put_breadcrumbs(entry)

    if has_json_ld?(module), do: PlugHTML.put_json_ld(conn, module, entry), else: conn
  end

  @doc """
  The JSON-LD document the page for `entry` emits: the exact content of its
  `<script type="application/ld+json">`. `nil` when the site has no identity.
  """
  @spec for_entry(module(), map(), keyword()) :: String.t() | nil
  def for_entry(module, entry, opts \\ []) do
    case module |> build_conn(entry, opts) |> entities() do
      [] -> nil
      entities -> JSONLD.to_graph_json(entities)
    end
  end

  @doc "Whether `module` declares a `json_ld_schema`."
  @spec has_json_ld?(module()) :: boolean()
  def has_json_ld?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0) and
      Spark.Dsl.Extension.get_entities(module, :json_ld_schemas) != []
  end

  @doc "The path of `entry`'s page, from its blueprint's `absolute_url`, or `nil`."
  @spec path(module(), map()) :: String.t() | nil
  def path(module, entry) do
    with true <- function_exported?(module, :__has_absolute_url__, 0),
         true <- module.__has_absolute_url__(),
         url when is_binary(url) and url != "" <- module.__absolute_url__(entry) do
      url |> URI.parse() |> Map.get(:path) |> Kernel.||("/")
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp title(module, entry) do
    if function_exported?(module, :__has_identifier__, 0) and module.__has_identifier__() do
      entry |> module.__identifier__(skip_cover: true) |> Map.get(:title)
    else
      Map.get(entry, :title)
    end
  rescue
    _ -> Map.get(entry, :title)
  end

  defp entry_language(entry) do
    case Map.get(entry, :language) do
      nil -> to_string(Brando.config(:default_language))
      language -> to_string(language)
    end
  end

  defp build_identity(type, cached_identity, cached_seo) do
    identity_schema_module(type).build({cached_identity, cached_seo})
  end

  defp identity_schema_module("person"), do: JSONLD.Schema.IdentityPerson
  defp identity_schema_module("organization"), do: JSONLD.Schema.Organization
  defp identity_schema_module("corporation"), do: JSONLD.Schema.Corporation
  defp identity_schema_module("professional_service"), do: JSONLD.Schema.ProfessionalService
  defp identity_schema_module("local_business"), do: JSONLD.Schema.LocalBusiness
  defp identity_schema_module("restaurant"), do: JSONLD.Schema.Restaurant
  defp identity_schema_module("educational_organization"), do: JSONLD.Schema.EducationalOrganization
  defp identity_schema_module("government_organization"), do: JSONLD.Schema.GovernmentOrganization
  defp identity_schema_module("ngo"), do: JSONLD.Schema.NGO
  defp identity_schema_module("medical_organization"), do: JSONLD.Schema.MedicalOrganization
  defp identity_schema_module("sports_organization"), do: JSONLD.Schema.SportsOrganization
  defp identity_schema_module("art_gallery"), do: JSONLD.Schema.ArtGallery
  defp identity_schema_module("architect"), do: JSONLD.Schema.Architect
  defp identity_schema_module("employment_agency"), do: JSONLD.Schema.EmploymentAgency

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
end
