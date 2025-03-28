defmodule Brando.Worker.ImageProcessor do
  @moduledoc false
  use Oban.Worker, queue: :image_processing, max_attempts: 5

  alias Brando.Images
  alias Brando.Users

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "image_id" => image_id,
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

    with {:ok, image} <- Images.get_image(image_id),
         {:ok, _} <- broadcast_status(image, field_full_path, :processing),
         {:ok, _} <- Images.Utils.delete_sized_images(image),
         {:ok, user} <- Users.get_user(user_id),
         {:ok, config} <- Images.get_config_for(config_target),
         {:ok, operations} <- Images.Operations.create(image, config, user),
         {:ok, process_map} <- Images.Operations.perform(operations, user) do
      result = Map.get(process_map, image_id)

      image_params = %{
        sizes: result.sizes,
        formats: result.formats,
        status: :processed
      }

      case Images.update_image(image, image_params, user) do
        {:ok, image} ->
          maybe_run_completed_callback(image, config, user)
          Brando.CDN.maybe_upload_image(image, field_full_path, user, config)
          broadcast_status(image, field_full_path, :updated)

        err ->
          err
      end
    else
      err ->
        {:error, err}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(400)

  defp maybe_run_completed_callback(image, config, user) do
    case config.completed_callback do
      nil ->
        {:ok, image}

      completed_callback ->
        case completed_callback.(image, user) do
          {:ok, image} -> {:ok, image}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp broadcast_status(image, path, status) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:image:#{image.id}",
      {image, [:image, status], path}
    )

    {:ok, image}
  end
end
