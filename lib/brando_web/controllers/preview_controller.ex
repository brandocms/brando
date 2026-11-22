defmodule BrandoWeb.PreviewController do
  @moduledoc """
  Serves shared ephemeral previews at `/__p__/:preview_key` (routed by
  `Brando.Router.page_routes/1`): a public link to a snapshot of an entry's
  rendered page, for people without an admin account, until it expires.
  The key is looked up by its hash (`Brando.Sites.Preview.hash_key/1`).

  In multi-site mode a preview opens only under the site it was shared from:
  on that site's hosts, and on a host with no site, where `Brando.Plug.Tenant`
  takes the tenant context from the preview. A preview with no site (stored
  before previews recorded theirs, with no pinned asset set) opens on any
  site's host.

  A connected AI tool's preview of a proposal (`proposal_id`) opens only
  while that proposal version is under review (`Sites.get_shared_preview/1`),
  and in multi-site mode only under the site and environment it was shared
  from: not on the same site's live host for a staging proposal, and nowhere
  once that environment is deleted. It is answered with
  `X-Robots-Tag: noindex, nofollow` and `Cache-Control: no-store`, and no
  banner, so a screenshot of it is the page.
  """
  use BrandoAdmin, :controller

  alias Brando.Sites
  alias Brando.Sites.Preview
  alias Brando.Sites.Site
  alias Brando.Utils

  action_fallback BrandoWeb.FallbackController

  @doc false
  def show(conn, %{"preview_key" => preview_key}) do
    with {:ok, preview} <- Sites.get_shared_preview(preview_key),
         :ok <- same_site(conn, preview) do
      # Sandboxed as a live preview is (`Brando.Plug.LivePreview`): the
      # snapshot holds editor content and is served on the site's origin.
      # The policy the pipeline set (`put_secure_browser_headers`, the
      # site's own directives) still applies.
      policy =
        Enum.join([Brando.Plug.LivePreview.sandbox_policy() | get_resp_header(conn, "content-security-policy")], "; ")

      conn
      |> put_resp_header("content-security-policy", policy)
      |> proposal_headers(preview)
      |> html(Brando.Plug.LivePreview.put_storage_script(Utils.binary_to_term(preview.html)))
    end
  end

  # The key alone finds a preview, whichever site shared it: a host must not
  # render another site's page under its domain
  defp same_site(conn, %Preview{site_id: site_id} = preview) when is_integer(site_id) do
    case {Brando.Tenant.mode(), conn.assigns[:current_site]} do
      {:multi, %Site{id: ^site_id, status: :active}} -> same_environment(conn, preview)
      {:multi, _another_site_or_none} -> {:error, {:preview, :not_found}}
      _one_site -> :ok
    end
  end

  defp same_site(_conn, _preview), do: :ok

  # A proposal's preview shows a draft of one environment: the same site's
  # other hosts do not open it, and a deleted environment (`environment_id`
  # nilified) opens it nowhere
  defp same_environment(conn, %Preview{proposal_id: proposal_id, environment_id: environment_id})
       when is_binary(proposal_id) do
    case conn.assigns[:current_environment] do
      %{id: ^environment_id} when is_integer(environment_id) -> :ok
      _another_environment -> {:error, {:preview, :not_found}}
    end
  end

  defp same_environment(_conn, _preview), do: :ok

  defp proposal_headers(conn, %Preview{proposal_id: proposal_id}) when is_binary(proposal_id) do
    conn
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_header("cache-control", "no-store")
  end

  defp proposal_headers(conn, _preview), do: conn
end
