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
    with {:ok, upload_entry} <- build_upload_entry(params),
         {:ok, meta} <- build_meta(params),
         {:ok, image_struct} <- Upload.handle_upload(meta, upload_entry, cfg, user),
         {:ok, processed_image} <- Upload.process_upload(image_struct, cfg, user) do
      image_params = map_from_struct(processed_image)

      Images.create_image(image_params, user)
    end
  end

  def build_meta(%{"image" => %Plug.Upload{path: path}, "config_target" => config_target}) do
    {:ok, %{path: path, config_target: config_target}}
  end

  def build_upload_entry(%{
        "image" => %Plug.Upload{filename: filename, content_type: content_type}
      }) do
    {:ok, %{client_name: filename, client_type: content_type}}
  end
end
