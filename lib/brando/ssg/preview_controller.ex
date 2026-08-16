defmodule Brando.SSG.PreviewController do
  @moduledoc "Serves a short-lived preview from a versioned SSG artifact."

  use BrandoAdmin, :controller

  alias Brando.SSG.Builds

  @doc false
  def show(conn, %{"token" => token} = params) do
    with build when not is_nil(build) <- Builds.get_preview(token),
         true <- is_nil(build.pruned_at) and File.dir?(build.build_path),
         true <- managed_build_path?(build),
         {:ok, relative_path} <- preview_path(Map.get(params, "path", [])),
         file_path <- Path.join(build.build_path, relative_path),
         {:ok, %{type: :regular}} <- File.lstat(file_path) do
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_content_type(MIME.from_path(file_path))
      |> send_file(200, file_path)
    else
      _missing_or_unsafe ->
        conn
        |> send_resp(404, "Static preview not found")
        |> halt()
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
