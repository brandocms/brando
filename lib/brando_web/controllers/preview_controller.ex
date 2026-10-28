defmodule BrandoWeb.PreviewController do
  @moduledoc """
  Serves shared ephemeral previews at `/__p__/:preview_key` (routed by
  `Brando.Router.page_routes/1`): a public link to a snapshot of an entry's
  rendered page, for people without an admin account, until it expires.
  The key is looked up by its hash (`Brando.Sites.Preview.hash_key/1`).
  """
  use BrandoAdmin, :controller

  alias Brando.Sites
  alias Brando.Sites.Preview
  alias Brando.Utils

  action_fallback BrandoWeb.FallbackController

  @doc false
  def show(conn, %{"preview_key" => preview_key}) do
    preview_opts = %{matches: %{preview_key: Preview.hash_key(preview_key)}}

    with {:ok, preview} <- Sites.get_preview(preview_opts),
         :gt <- DateTime.compare(preview.expires_at, DateTime.utc_now()) do
      # Sandboxed as a live preview is (`Brando.Plug.LivePreview`): the
      # snapshot holds editor content and is served on the site's origin.
      # The policy the pipeline set (`put_secure_browser_headers`, the
      # site's own directives) still applies.
      policy =
        Enum.join([Brando.Plug.LivePreview.sandbox_policy() | get_resp_header(conn, "content-security-policy")], "; ")

      conn
      |> put_resp_header("content-security-policy", policy)
      |> html(Brando.Plug.LivePreview.put_storage_script(Utils.binary_to_term(preview.html)))
    else
      {:error, _} = error -> error
      _ -> {:error, {:preview, :not_found}}
    end
  end
end
