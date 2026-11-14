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
      |> html(Brando.Plug.LivePreview.put_storage_script(Utils.binary_to_term(preview.html)))
    end
  end

  # The key alone finds a preview, whichever site shared it: a host must not
  # render another site's page under its domain
  defp same_site(conn, %Preview{site_id: site_id}) when is_integer(site_id) do
    case {Brando.Tenant.mode(), conn.assigns[:current_site]} do
      {:multi, %Site{id: ^site_id, status: :active}} -> :ok
      {:multi, _another_site_or_none} -> {:error, {:preview, :not_found}}
      _one_site -> :ok
    end
  end

  defp same_site(_conn, _preview), do: :ok
end
