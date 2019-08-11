defmodule Brando.Images.Uploads.Schema do
  @moduledoc """
  Handles uploads of Brando.Image{}

  For ImageFields, see Brando.Images.Uploads.Field
  """

  @type user :: Brando.User.t()

  alias Brando.Images
  alias Brando.Upload

  @doc """
  Handle upload of Brando.Image.
  """
  @spec handle_upload(params :: Map.t(), cfg :: Map.t(), user :: user) ::
          [{:ok, Image.t()} | {:error, Changeset.t()}] | nil | Brando.Upload.error_result()
  def handle_upload(params, cfg, user) do
    with {:ok, plug} <- Map.fetch(params, "image"),
         {:ok, img_series_id} <- Map.fetch(params, "image_series_id"),
         {:ok, upload} <- Upload.process_upload(plug, cfg),
         {:ok, img_struct} <- Images.Processing.create_image_struct(upload, user),
         {:ok, operations} <- Images.Operations.create_operations(img_struct, cfg, user),
         {:ok, operation_results} <- Images.Operations.perform_operations(operations, user) do
      for result <- operation_results do
        Images.create_image(
          %{
            image: result.img_struct,
            image_series_id: img_series_id
          },
          user
        )
      end
    else
      err ->
        Upload.handle_upload_error(err)
    end
  end
end
