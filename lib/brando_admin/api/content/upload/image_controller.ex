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

    params = Map.put(params, "config_target", "default")

    payload =
      case Schema.handle_upload(params, cfg, user) do
        {:error, changeset} ->
          traversed_errors =
            Ecto.Changeset.traverse_errors(changeset, fn
              {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
              msg -> msg
            end)

          error_msg = """
          Error occured while uploading!<br><br>
          #{inspect(traversed_errors, pretty: true)}
          """

          %{status: 500, error: error_msg}

        {:error, :content_type, attemped_mime, allowed_mime} ->
          error_msg = """
          Trying to upload unsupported type [#{attemped_mime}]!<br><br>
          Allowed types are:<br><br>
          #{inspect(allowed_mime, pretty: true)}
          """

          %{status: 500, error: error_msg}

        {:ok, image} ->
          sizes_map = sizes_with_media_url(image)

          %{
            status: 200,
            uid: uid,
            image: %{
              id: image.id,
              dominant_color: image.dominant_color,
              sizes: sizes_map,
              src: Brando.Utils.media_url(image.path),
              width: image.width,
              height: image.height
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
