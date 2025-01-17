defmodule BrandoAdmin.API.Content.Upload.FileController do
  @moduledoc """
  Legacy upload of files (used in Block vars)
  """
  use BrandoAdmin, :controller

  alias Brando.Files.Uploads.Schema

  def create(conn, %{"uid" => uid} = params) do
    user = Brando.Utils.current_user(conn)

    {cfg, params} =
      case Map.get(params, "config_target") do
        nil ->
          {Brando.config(Brando.Files)[:default_config] ||
             Brando.Type.FileConfig.default_config(), Map.put(params, "config_target", "default")}

        config_target ->
          {:ok, file_cfg} = Brando.Files.get_config_for(config_target)
          {file_cfg, params}
      end

    payload =
      case Schema.handle_upload(params, cfg, user) do
        {:error, changeset} ->
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

        {:error, :content_type, attemped_mime, allowed_mime} ->
          error_msg = """
          Trying to upload unsupported type [#{attemped_mime}]!<br><br>
          Allowed types are:<br><br>
          #{inspect(allowed_mime, pretty: true)}
          """

          %{status: 500, error: error_msg}

        {:ok, file} ->
          %{
            status: 200,
            uid: uid,
            file: %{
              id: file.id,
              src: Brando.Utils.media_url(file),
              filesize: file.filesize
            }
          }
      end

    json(conn, payload)
  end
end
