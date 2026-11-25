defmodule Brando.Plug.Tenant do
  @moduledoc """
  Resolves frontend tenant context, without a database query but for a shared
  preview's link.

  Multi-site requests resolve by normalized host through `Brando.Tenant.Cache`.
  Single-site mode falls back to the configured site's live environment when no
  domain is assigned. Unknown hosts clear process context instead of inheriting
  stale state. In multi-site mode they are rejected so an application cannot
  accidentally serve unscoped or another tenant's content, with one exception:
  a shared preview's link (`/__p__/:preview_key`) takes its context from the
  preview, which costs one query on that path only.

  A request on one of an environment's redirect hosts is redirected
  permanently, from the cache, to the same path and query on the
  environment's domain, with the endpoint URL's scheme and port: 301 for GET and HEAD,
  308 for other methods. One that carries a static build's valid signed
  context (`Brando.SSG.Context`) is served under that context instead. A response for an environment that is not live
  carries `X-Robots-Tag: noindex, nofollow`.

  A request resolved from a static build's signed context is marked
  `conn.private.brando_ssg_build`, so what answers it can answer as the
  site's public host would (`BrandoWeb.SEOController`). With
  `tenancy_mode: :none` one that carries a valid signed context is marked
  (`Brando.SSG.Context.build_request?/1`). Such a request renders with the
  asset set the build recorded (`Brando.SSG.Context.asset_set_id/1`), and
  answers 503 when that set is gone, so the build fails rather than link
  files its artifact does not hold.

  A request on a static site's preview host (`Brando.SSG.PreviewHost`), one
  no environment binds, is decided before anything else above: only a build
  preview of that site (`/__ssg_preview__/:token/*path`) goes on, under the
  build's own environment, and every response there carries
  `X-Robots-Tag: noindex, nofollow`. Every other request on it answers 404.

  A request a host serving its build let through for a plug before the
  router, which none answered, gets the build's 404 page here and goes no
  further (`Brando.SSG.LocalDelivery.answer_unanswered/1`).
  """

  import Plug.Conn, only: [assign: 3, halt: 1, put_private: 3, put_resp_header: 3, register_before_send: 2, send_resp: 3]

  alias Brando.Assets.SiteAssets
  alias Brando.Environments.Environment
  alias Brando.SSG.Builds
  alias Brando.SSG.Context
  alias Brando.SSG.LocalDelivery
  alias Brando.SSG.PreviewHost
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Frontend

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{private: %{brando_ssg_before_router: _site}} = conn, _opts),
    do: LocalDelivery.answer_unanswered(conn)

  def call(conn, _opts) do
    # One process serves each request of a kept-alive connection
    SiteAssets.drop_build_set()

    case redirect_target(conn) do
      nil ->
        case PreviewHost.site(conn.host) do
          nil -> resolve_tenant(conn)
          found -> preview_host(conn, found)
        end

      {_site, environment} ->
        # A static build of a site whose base URL is now a redirect host
        # fetches every page on that host, with its signed context
        case build_context(conn) do
          {site, built_environment} -> put_build(conn, site, built_environment)
          nil -> redirect(conn, environment.domain)
        end
    end
  end

  defp resolve_tenant(conn) do
    case resolve_with_source(conn) do
      {:build, site, environment} ->
        put_build(conn, site, environment)

      {_source, site, environment} ->
        put_tenant(conn, site, environment)

      nil ->
        Tenant.put_prefix(nil)

        case shared_preview_tenant(conn) do
          {site, environment} -> put_tenant(conn, site, environment)
          nil -> conn |> mark_standalone_build() |> reject_missing_multi_site()
        end
    end
  end

  # A preview host (`Brando.SSG.PreviewHost`) answers its site's build
  # previews only, each under its build's environment, and 404 for every
  # other path, an unknown token, a site that is no active static one, and a
  # build whose environment is gone. The token in the link is the access, so
  # `Brando.Plug.Lockdown` lets it through.
  defp preview_host(conn, found) do
    Tenant.put_prefix(nil)

    conn =
      conn
      |> put_private(:brando_preview_host, true)
      |> put_resp_header("x-robots-tag", "noindex, nofollow")

    with {:ok, site} <- found,
         ["__ssg_preview__", token | _path] <- conn.path_info,
         %{environment: %Environment{} = environment} <- Builds.get_preview(token, site) do
      put_tenant(conn, site, environment)
    else
      _not_a_preview -> conn |> send_resp(404, "Not found") |> halt()
    end
  end

  defp put_build(conn, site, environment) do
    case mark_build(conn) do
      %Plug.Conn{halted: true} = conn -> conn
      conn -> put_tenant(conn, site, environment)
    end
  end

  # Rendered with the build's recorded set until the response is sent
  defp mark_build(conn) do
    with {:ok, asset_set_id} <- Context.asset_set_id(conn),
         :ok <- SiteAssets.put_build_set(asset_set_id) do
      conn
      |> put_private(:brando_ssg_build, true)
      |> register_before_send(fn conn ->
        SiteAssets.drop_build_set()
        conn
      end)
    else
      _set_gone ->
        conn
        |> send_resp(503, "The asset set this build recorded is no longer available")
        |> halt()
    end
  end

  # With `tenancy_mode: :none` a build's signed context names no site
  defp mark_standalone_build(conn), do: if(Context.build_request?(conn), do: mark_build(conn), else: conn)

  defp put_tenant(conn, site, environment) do
    prefix = Tenant.prefix(site, environment)
    Tenant.put_prefix(prefix)

    conn
    |> assign(:current_site, site)
    |> assign(:current_environment, environment)
    |> assign(:tenant_prefix, prefix)
    |> no_index(environment)
  end

  # An environment that is not live answers on a public host too
  # (`staging.example.com`); crawlers are told to leave it alone
  defp no_index(conn, %{live: true}), do: conn
  defp no_index(conn, _environment), do: put_resp_header(conn, "x-robots-tag", "noindex, nofollow")

  # A redirect host answers from the cache, before any other resolution but a
  # static build's: it is no environment's domain and no installation host, so
  # nothing else answers on it
  defp redirect_target(%{private: %{brando_live_preview: true}}), do: nil

  defp redirect_target(conn) do
    if Tenant.enabled?(), do: Cache.get_redirect(conn.host)
  end

  # Permanent: 301 for GET and HEAD, 308 for the rest, which keeps the method
  # and body
  defp redirect(conn, domain) do
    status = if conn.method in ["GET", "HEAD"], do: 301, else: 308
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    conn
    |> put_resp_header("location", "#{origin(domain)}#{requested_path(conn)}#{query}")
    |> send_resp(status, "")
    |> halt()
  end

  # `Brando.Plug.Markdown` takes `.md` off the path before the router
  defp requested_path(conn), do: conn.private[:brando_original_request_path] || conn.request_path

  # The endpoint URL's scheme, and its port when that is not the scheme's
  # default, as Phoenix's URL helpers write it
  defp origin(domain) do
    %URI{scheme: scheme, port: port} = URI.parse(Brando.endpoint().url())
    scheme = scheme || "https"
    port = if port && port != URI.default_port(scheme), do: ":#{port}", else: ""
    "#{scheme}://#{domain}#{port}"
  end

  # A shared preview's link is on the endpoint's host, which belongs to no
  # site: it opens there under the site and environment it was shared from.
  # Only that path is looked up, and only an unexpired preview of an active
  # site lets the request through. A suspended or archived site's host
  # resolves to no site either, and opens nothing.
  defp shared_preview_tenant(%{path_info: ["__p__", key], host: host}) do
    if Tenant.mode() == :multi and not Frontend.inactive_site_host?(host) do
      case Brando.Sites.get_shared_preview(key) do
        {:ok, preview} -> Frontend.shared_preview_tenant(preview)
        {:error, _not_found} -> nil
      end
    end
  end

  defp shared_preview_tenant(_conn), do: nil

  @doc """
  The site and environment `conn` is for, or nil: an internal preview
  render's, then a static build's signed header (`Brando.SSG.Context`), then
  the host's. A shared preview's link is not resolved here, nor a preview
  host (`Brando.SSG.PreviewHost`). Also used by
  `Brando.Plug.I18n.put_locale/2` when it runs before this plug.
  """
  @spec resolve(Plug.Conn.t()) :: {Brando.Sites.Site.t(), Brando.Environments.Environment.t()} | nil
  def resolve(conn) do
    with false <- PreviewHost.preview_host?(conn.host),
         {_source, site, environment} <- resolve_with_source(conn) do
      {site, environment}
    else
      _none -> nil
    end
  end

  # Internal preview rendering has a server-resolved workspace but no frontend
  # host. This private connection metadata cannot be supplied by an HTTP client.
  defp resolve_with_source(%{
         private: %{
           brando_live_preview: true,
           brando_preview_context:
             {%Brando.Sites.Site{id: id} = site, %Brando.Environments.Environment{site_id: id} = environment}
         }
       }) do
    {:preview, site, environment}
  end

  defp resolve_with_source(conn) do
    case build_context(conn) do
      {site, environment} ->
        {:build, site, environment}

      nil ->
        case Frontend.resolve(conn.host) do
          {site, environment} -> {:host, site, environment}
          nil -> nil
        end
    end
  end

  defp build_context(conn) do
    conn
    |> Plug.Conn.get_req_header(Context.header())
    |> List.first()
    |> Context.resolve()
  end

  defp reject_missing_multi_site(conn) do
    if Tenant.mode() == :multi do
      conn
      |> send_resp(404, "Not found")
      |> halt()
    else
      conn
    end
  end
end
