defmodule Brando.SitemapController do
  @moduledoc """
  Controller for i18n actions.
  """
  use BrandoAdmin, :controller

  @doc false
  def show(conn, %{"file" => file}) do
    with {:ok, safe_file} <- Path.safe_relative(file),
         file_path = Path.join([Brando.config(:media_path), "sitemaps", safe_file]),
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
