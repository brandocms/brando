defmodule Brando.Images.ImageResolver do
  @moduledoc """
  Resolver for image categories
  """
  use Brando.Web, :resolver
  alias Brando.Images

  @doc """
  Create image
  """
  def create(%{image_series_id: series_id, image_upload_params: %{image: image}}, %{
        context: %{current_user: current_user}
      }) do
    {:ok, cfg} = Images.get_series_config(series_id)

    params = %{"image" => image, "image_series_id" => series_id}

    case Images.Uploads.Schema.handle_upload(params, cfg, current_user) do
      {:error, _} ->
        :error

      images when is_list(images) ->
        List.first(images)
    end
  end

  @doc """
  Delete images
  """
  def delete_images(%{image_ids: image_ids}, %{context: %{current_user: _current_user}}) do
    #! TODO - check permissios
    Images.delete_images(image_ids)
    {:ok, 200}
  end

  def update_meta(%{image_id: image_id, image_meta_params: image_meta_params}, %{
        context: %{current_user: current_user}
      }) do
    image_id
    |> Images.get_image!()
    |> Images.update_image_meta(image_meta_params, current_user)
  end
end
