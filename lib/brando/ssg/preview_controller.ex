defmodule Brando.SSG.PreviewController do
  @moduledoc """
  Serves a short-lived preview from a versioned SSG artifact.

  With tenancy enabled a preview is served only on a host that resolves to the
  build's own site: another site's host, or none, answers 404, so the
  artifact's markup runs only in its own site's origin. With several sites it
  never opens on one of the installation's own hosts, such as the admin's, even
  for a site bound to it. The response carries a restrictive
  Content-Security-Policy.

  The preview is the build's own: its HTML and CSS name the build's files
  under the preview's path (`Brando.SSG.PreviewRewrite`), so it loads the
  assets and media the build copied and its links stay inside it. A path the
  build has no file for answers the build's `404.html` with status 404.
  """

  use BrandoAdmin, :controller

  alias Brando.SSG.BuildPath
  alias Brando.SSG.Builds
  alias Brando.SSG.PreviewRewrite
  alias Brando.Tenant

  # The build's scripts run, with the site's own origin: an opaque one would
  # need CORS for its module scripts and fonts, which the site's assets do not
  # send, and leave the page blank. Forms post nowhere, and plugins, top-level
  # navigation and dialogs are off.
  @content_security_policy "sandbox allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox; " <>
                             "base-uri 'none'; form-action 'none'; frame-ancestors 'self'; object-src 'none'"

  @doc false
  def show(conn, %{"token" => token} = params) do
    with {:ok, site_scope} <- request_site(conn),
         build when not is_nil(build) <- Builds.get_preview(token, site_scope),
         true <- is_nil(build.pruned_at) and File.dir?(build.build_path),
         true <- BuildPath.managed?(build.build_path, build.site),
         {:ok, relative_path} <- BuildPath.relative(Map.get(params, "path", [])) do
      if BuildPath.regular_file?(build.build_path, relative_path),
        do: send_preview(conn, build, token, relative_path, 200),
        else: send_not_found(conn, build, token)
    else
      _missing_or_unsafe -> not_found(conn)
    end
  end

  defp send_not_found(conn, build, token) do
    if BuildPath.regular_file?(build.build_path, "404.html"),
      do: send_preview(conn, build, token, "404.html", 404),
      else: not_found(conn)
  end

  defp not_found(conn) do
    conn
    |> send_resp(404, "Static preview not found")
    |> halt()
  end

  defp send_preview(conn, build, token, relative_path, status) do
    file_path = Path.join(build.build_path, relative_path)
    content_type = MIME.from_path(file_path)

    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("content-security-policy", @content_security_policy)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_content_type(content_type)

    prefix = "/__ssg_preview__/" <> token

    case content_type do
      "text/html" -> send_resp(conn, status, PreviewRewrite.html(File.read!(file_path), prefix, site_bases(build)))
      "text/css" -> send_resp(conn, status, PreviewRewrite.css(File.read!(file_path), prefix, site_bases(build)))
      _other -> conn |> Brando.Plug.Usage.put_file(file_path) |> send_file(status, file_path)
    end
  end

  # The origins the build's pages name the site on: the environment's own
  # and the site's public one
  defp site_bases(%{site: site, environment: environment}) do
    in_build = fn -> Enum.uniq([Brando.Utils.hostname(), Brando.Utils.public_hostname()]) end

    if Tenant.enabled?() and match?(%Brando.Environments.Environment{}, environment),
      do: Tenant.with_prefix(Tenant.prefix(site, environment), in_build),
      else: in_build.()
  end

  defp request_site(conn) do
    cond do
      not Tenant.enabled?() -> {:ok, :any}
      Tenant.mode() == :multi and Brando.Tenant.InstallationHosts.member?(conn.host) -> :error
      match?(%Brando.Sites.Site{}, conn.assigns[:current_site]) -> {:ok, conn.assigns.current_site}
      true -> :error
    end
  end
end
