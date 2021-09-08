defmodule BrandoAdmin.API.Content.Upload.ImageController do
  @moduledoc """
  Main controller for Brando backend
  """
  use BrandoAdmin, :controller
  alias Brando.Images.Uploads.Schema

  def create(conn, %{"uid" => uid, "slug" => series_slug} = params) do
    user = Brando.Utils.current_user(conn)

    case Brando.Images.get_series_by_slug(series_slug) do
      {:ok, series} ->
        cfg = series.cfg || Brando.config(Brando.Images)[:default_config]
        params = Map.put(params, "image_series_id", series.id)

        payload =
          case Schema.handle_upload(params, cfg, user) do
            {:error, err} ->
              %{
                status: 500,
                error: err
              }

            {:ok, image} ->
              sizes = sizes_with_media_url(image)
              sizes_map = Enum.into(sizes, %{})

              %{
                status: 200,
                uid: uid,
                image: %{
                  id: image.id,
                  dominant_color: image.image.dominant_color,
                  sizes: sizes_map,
                  src: Brando.Utils.media_url(image.image.path),
                  width: image.image.width,
                  height: image.image.height
                }
              }
          end

        json(conn, payload)

      {:error, {:image_series, :not_found}} ->
        error_msg =
          "Image series `#{series_slug}` not found. Make sure it exists before using it as an upload target"

        json(conn, %{status: 500, error: error_msg})
    end
  end

  defp sizes_with_media_url(image),
    do: Enum.map(image.image.sizes, fn {k, v} -> {k, Brando.Utils.media_url(v)} end)
end
