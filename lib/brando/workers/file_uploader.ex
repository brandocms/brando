defmodule Brando.Worker.FileUploader do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Brando.CDN
  alias Brando.Files
  alias Brando.Users

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "file_id" => file_id,
          "config_target" => config_target,
          "user_id" => user_id,
          "field_full_path" => field_full_path
        }
      }) do
    field_full_path =
      Enum.map(field_full_path, fn
        segment when is_binary(segment) -> String.to_existing_atom(segment)
        integer -> integer
      end)

    with {:ok, file} <- Files.get_file(file_id),
         {:ok, user} <- Users.get_user(user_id),
         {:ok, config} <- Files.get_config_for(config_target),
         {:ok, _s3_key} <- CDN.upload_file(file, config, user_id) do
      file_params = %{cdn: true}

      case Files.update_file(file, file_params, user) do
        {:ok, file} ->
          broadcast_status(file, field_full_path, :updated)

        err ->
          err
      end
    else
      err ->
        {:error, err}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(180)

  defp broadcast_status(file, path, status) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:file:#{file.id}",
      {file, [:file, status], path}
    )

    {:ok, file}
  end
end
