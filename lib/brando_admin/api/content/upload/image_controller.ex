defmodule BrandoAdmin.API.Content.Upload.ImageController do
  @moduledoc """
  Main controller for Brando backend
  """
  use BrandoAdmin, :controller

  alias Brando.Images.Uploads.Schema
  alias Brando.Type.ImageConfig

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

    {cfg, params} =
      case Map.get(params, "config_target") do
        nil ->
          default_config =
            Brando.config(Brando.Images)[:default_config] ||
              ImageConfig.default_config()

          default_config_struct =
            maybe_struct(ImageConfig, default_config)

          {default_config_struct, Map.put(params, "config_target", "default")}

        config_target ->
          {:ok, image_cfg} = Brando.Images.get_config_for(config_target)
          {image_cfg, params}
      end

    # insert the formats we have in the block
    cfg = Map.put(cfg, :formats, upload_formats)

    payload =
      case Schema.handle_upload(params, cfg, user) do
        {:error, %Ecto.Changeset{} = changeset} ->
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

        {:error, {:image, :not_found}} ->
          error_msg = "Image file not found during processing"
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

        {:error, error} ->
          error_msg = "Error during upload: #{inspect(error)}"
          %{status: 500, error: error_msg}
      end

    json(conn, payload)
  end

  @doc """
  Replace an existing image's file with a cropped version.

  Receives the image blob and image_id, replaces the original file,
  updates dimensions/focal/status, and queues reprocessing.
  """
  def replace_crop(conn, %{"image_id" => image_id, "image" => upload, "focal_x" => fx, "focal_y" => fy}) do
    user = Brando.Utils.current_user(conn)
    focal = %{x: String.to_integer(fx), y: String.to_integer(fy)}

    with {:ok, image} <- Brando.Images.get_image(image_id),
         {:ok, binary_data} <- File.read(upload.path),
         {:ok, _updated_image} <- Brando.Images.Crop.save_replace(image, binary_data, focal, user) do
      json(conn, %{status: 200, image_id: image.id})
    else
      {:error, reason} ->
        json(conn, %{status: 500, error: "Error replacing image: #{inspect(reason)}"})
    end
  end

  defp sizes_with_media_url(image) do
    Map.new(image.sizes, fn {k, v} -> {k, Brando.Utils.media_url(v)} end)
  end

  defp maybe_struct(_struct_type, %ImageConfig{} = config), do: config
  defp maybe_struct(struct_type, config), do: struct(struct_type, config)
end
