defmodule Brando.Images.Uploads.Schema do
  @moduledoc """
  Handles uploads of Brando.Image{}
  - Used with Villain uploads!

  TODO: Get rid of this when we have unified LV uploads across the board,
  TODO: Currently this is used for Villain `fetch` uploads via JS
  """

  alias Brando.Images
  alias Brando.Upload
  alias Brando.Users

  import Brando.Utils, only: [map_from_struct: 1]

  @type changeset :: Ecto.Changeset.t()
  @type image :: Images.Image.t()
  @type user :: Users.User.t()

  @doc """
  Handle upload of Brando.Image.
  """
  @spec handle_upload(params :: map, cfg :: map, user :: user) ::
          {:ok, image} | {:error, changeset}
  def handle_upload(params, cfg, user) do
    with {:ok, plug} <- Map.fetch(params, "image"),
         {:ok, upload_entry} <- build_upload_entry(plug),
         {:ok, meta} <- build_meta(plug),
         {:ok, img_series_id} <- Map.fetch(params, "image_series_id"),
         {:ok, image_struct} <- Upload.handle_upload(meta, upload_entry, cfg, user),
         {:ok, processed_image} <- Upload.process_upload(image_struct, cfg, user) do
      image_params = %{
        image: map_from_struct(processed_image),
        image_series_id: img_series_id
      }

      Images.create_image(image_params, user)
    end
  end

  def build_meta(%Plug.Upload{path: path}) do
    {:ok, %{path: path}}
  end

  def build_upload_entry(%Plug.Upload{filename: filename, content_type: content_type}) do
    {:ok, %{client_name: filename, client_type: content_type}}
  end
end
