defmodule BrandoAdmin.API.Content.Upload.ImageController do
  @moduledoc """
  Main controller for Brando backend
  """
  use BrandoAdmin, :controller
  alias Brando.Images.Uploads.Schema

  def create(conn, %{"uid" => uid, "formats" => formats} = params) do
    user = Brando.Utils.current_user(conn)

    upload_formats =
      case formats do
        "" ->
          [:original]

        formats ->
          formats
          |> String.split(",")
          |> Enum.map(&String.to_existing_atom/1)
      end

    cfg = Brando.config(Brando.Images)[:default_config]
    # insert the formats we have in the block
    cfg = Map.put(cfg, :formats, upload_formats)

    payload =
      case Schema.handle_upload(params, cfg, user) do
        {:error, err} ->
          %{status: 500, error: err}

        {:ok, image} ->
          sizes_map = sizes_with_media_url(image)

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
  end

  defp sizes_with_media_url(image) do
    image.sizes
    |> Enum.map(fn {k, v} -> {k, Brando.Utils.media_url(v)} end)
    |> Enum.into(%{})
  end
end
