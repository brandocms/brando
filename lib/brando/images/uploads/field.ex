defmodule Brando.Images.Upload.Field do
  @moduledoc """
  Handles uploads of image fields

  For schemas, see Brando.Images.Uploads.Schema
  """

  @type user :: Brando.User.t() | :system

  alias Brando.Images
  alias Brando.Type
  alias Brando.Upload

  @doc """
  Handles the upload by starting a chain of operations on the plug.
  This function handles upload when we have an image field on a schema,
  not when the schema itself represents an image. (See Brando.Images.Upload.Schema)

  ## Parameters

    * `name`: the field we are operating on.
    * `plug`: a Plug.Upload struct.
    * `cfg`: the field's cfg from has_image_field

  """
  @spec handle_upload(
          field_name :: atom | String.t(),
          upload_plug :: Plug.Upload.t(),
          image_config :: Type.ImageConfig.t(),
          user :: user
        ) ::
          {:ok, {:handled, atom, Type.Image}} | {:error, {atom, {:error, String.t()}}}
  def handle_upload(name, %Plug.Upload{} = plug, cfg, user) do
    with {:ok, upload} <- Upload.process_upload(plug, cfg),
         {:ok, img_struct} <- Images.Processing.create_image_struct(upload, user),
         {:ok, operations} <- Images.Operations.create_operations(img_struct, cfg, user),
         {:ok, results} <- Images.Operations.perform_operations(operations, user) do
      img_struct =
        results
        |> List.first()
        |> Map.get(:img_struct)

      {:ok, {:handled, name, img_struct}}
    else
      err -> {:error, {name, Upload.handle_upload_error(err)}}
    end
  end

  def handle_upload(name, image, _, _) do
    {:ok, {:unhandled, name, image}}
  end
end
