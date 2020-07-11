defmodule Brando.Images.Uploads.Schema do
  @moduledoc """
  Handles uploads of Brando.Image{}

  For ImageFields, see Brando.Images.Uploads.Field
  """

  @type user :: Brando.Users.User.t()

  alias Brando.Images
  alias Brando.Upload

  @doc """
  Handle upload of Brando.Image.
  """
  @spec handle_upload(params :: map, cfg :: map, user :: user) ::
          [any()] | {:error, binary}
  def handle_upload(params, cfg, user) do
    with {:ok, plug} <- Map.fetch(params, "image"),
         {:ok, img_series_id} <- Map.fetch(params, "image_series_id"),
         {:ok, upload} <- Upload.process_upload(plug, cfg),
         {:ok, image_struct} <- Images.Processing.create_image_type_struct(upload, user),
         {:ok, operations} <- Images.Operations.create(image_struct, cfg, nil, user),
         {:ok, operation_results} <- Images.Operations.perform(operations, user) do
      for result <- operation_results do
        Images.create_image(
          %{
            image: result.image_struct,
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
