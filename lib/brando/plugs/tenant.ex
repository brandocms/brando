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
  site's public host would (`BrandoWeb.SEOController`).
  """

  import Plug.Conn, only: [assign: 3, halt: 1, put_private: 3, put_resp_header: 3, send_resp: 3]

  alias Brando.SSG.Context
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Frontend

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case redirect_target(conn) do
      nil ->
        resolve_tenant(conn)

      {_site, environment} ->
        # A static build of a site whose base URL is now a redirect host
        # fetches every page on that host, with its signed context
        case build_context(conn) do
          {site, built_environment} -> conn |> mark_build() |> put_tenant(site, built_environment)
          nil -> redirect(conn, environment.domain)
        end
    end
  end

  defp resolve_tenant(conn) do
    case resolve_with_source(conn) do
      {:build, site, environment} ->
        conn |> mark_build() |> put_tenant(site, environment)

      {_source, site, environment} ->
        put_tenant(conn, site, environment)

      nil ->
        Tenant.put_prefix(nil)

        case shared_preview_tenant(conn) do
          {site, environment} -> put_tenant(conn, site, environment)
          nil -> reject_missing_multi_site(conn)
        end
    end
  end

  defp mark_build(conn), do: put_private(conn, :brando_ssg_build, true)

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
  the host's. A shared preview's link is not resolved here. Also used by
  `Brando.Plug.I18n.put_locale/2` when it runs before this plug.
  """
  @spec resolve(Plug.Conn.t()) :: {Brando.Sites.Site.t(), Brando.Environments.Environment.t()} | nil
  def resolve(conn) do
    case resolve_with_source(conn) do
      {_source, site, environment} -> {site, environment}
      nil -> nil
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
