defmodule Brando.SSG.PreviewController do
  @moduledoc """
  Serves a short-lived preview from a versioned SSG artifact.

  With tenancy enabled a preview is served only on a host that resolves to the
  build's own site: another site's host, or none, answers 404, so the
  artifact's markup runs only in its own site's origin. The response carries
  a restrictive Content-Security-Policy.
  """

  use BrandoAdmin, :controller

  alias Brando.SSG.Builds
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
         true <- managed_build_path?(build),
         {:ok, relative_path} <- preview_path(Map.get(params, "path", [])),
         file_path <- Path.join(build.build_path, relative_path),
         {:ok, %{type: :regular}} <- File.lstat(file_path) do
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("content-security-policy", @content_security_policy)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_content_type(MIME.from_path(file_path))
      |> send_file(200, file_path)
    else
      _missing_or_unsafe ->
        conn
        |> send_resp(404, "Static preview not found")
        |> halt()
    end
  end

  defp request_site(conn) do
    cond do
      not Tenant.enabled?() -> {:ok, :any}
      match?(%Brando.Sites.Site{}, conn.assigns[:current_site]) -> {:ok, conn.assigns.current_site}
      true -> :error
    end
  end

  defp preview_path([]), do: {:ok, "index.html"}

  defp preview_path(segments) when is_list(segments) do
    with {:ok, safe_path} <- segments |> Enum.join("/") |> Path.safe_relative() do
      if Path.extname(safe_path) == "" do
        {:ok, Path.join(safe_path, "index.html")}
      else
        {:ok, safe_path}
      end
    end
  end

  defp managed_build_path?(build) do
    Path.dirname(Path.expand(build.build_path)) == Path.expand(Builds.build_root(build.site))
  end
end
