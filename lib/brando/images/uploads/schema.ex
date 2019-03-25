defmodule Brando.Images.Uploads.Schema do
  @moduledoc """
  Handles uploads of Brando.Image{}

  For ImageFields, see Brando.Images.Uploads.Field
  """

  alias Brando.Images
  alias Brando.Progress
  alias Brando.Upload

  @doc """
  Handle upload of Brando.Image.
  """
  def handle_upload(params, cfg, user) do
    with {:ok, plug} <- Map.fetch(params, "image"),
         {:ok, img_series_id} <- Map.fetch(params, "image_series_id"),
         {:ok, upload} <- Upload.process_upload(plug, cfg),
         {:ok, img_struct} <- Images.Utils.create_image_struct(upload, user),
         {:ok, operations} <- Images.Operations.create_operations(img_struct, cfg, user),
         {:ok, image_structs} <- Images.Operations.perform_operations(operations, user) do

      for i <- image_structs do
        Images.create_image(%{
          image: i,
          image_series_id: img_series_id,
        }, user)
      end
    else
      nil ->
        nil

      err ->
        Upload.handle_upload_error(err)
    end
  end
end
