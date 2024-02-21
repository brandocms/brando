defmodule Brando.Files.Uploads.Schema do
  @moduledoc """
  Handles uploads of Brando.File{}
  - Used with Villain uploads! (vars)

  TODO: Get rid of this when we have unified LV uploads across the board,
  TODO: Currently this is used for Villain `fetch` uploads via JS
  """

  alias Brando.Files
  alias Brando.Upload
  alias Brando.Users

  @type changeset :: Ecto.Changeset.t()
  @type file :: Files.File.t()
  @type user :: Users.User.t()

  @doc """
  Handle upload of Brando.File.
  """
  @spec handle_upload(params :: map, cfg :: map, user :: user) ::
          {:ok, file} | {:error, changeset}
  def handle_upload(params, cfg, user) do
    with {:ok, upload_entry} <- build_upload_entry(params),
         {:ok, meta} <- build_meta(params) do
      Upload.handle_upload(meta, upload_entry, cfg, user)
    end
  end

  def build_upload_entry(%{
        "file" => %Plug.Upload{filename: filename, content_type: content_type, path: path}
      }) do
    client_size =
      case File.stat(path) do
        {:ok, %{size: size}} -> size
        {:error, _reason} -> 0
      end

    {:ok, %{client_name: filename, client_type: content_type, client_size: client_size}}
  end

  def build_meta(%{"file" => %Plug.Upload{path: path}, "config_target" => config_target}) do
    {:ok, %{path: path, config_target: config_target}}
  end
end
