defmodule BrandoAdmin.API.Content.Upload.ImageController do
  @moduledoc """
  Controller for image crop replacement in the image editor.
  """
  use BrandoAdmin, :controller

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
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{status: 403, error: "You do not have permission to edit this image."})

      {:error, reason} ->
        json(conn, %{status: 500, error: "Error replacing image: #{inspect(reason)}"})
    end
  end
end
