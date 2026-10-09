defmodule BrandoWeb.SitemapController do
  @moduledoc """
  Serves the generated sitemap files under `/sitemaps/` (routed by
  `Brando.Router.page_routes/1`).
  """
  use BrandoAdmin, :controller

  @doc false
  def show(conn, %{"file" => file}) do
    with {:ok, safe_file} <- Path.safe_relative(file),
         file_path = Path.join([Brando.Tenant.Storage.current_media_root(), "sitemaps", safe_file]),
         true <- File.exists?(file_path) do
      send_download(conn, {:file, file_path})
    else
      _err ->
        conn
        |> send_resp(404, "sitemap not found")
        |> halt()
    end
  end
end
