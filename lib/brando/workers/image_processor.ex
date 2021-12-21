defmodule Brando.Worker.ImageProcessor do
  use Oban.Worker, queue: :default, max_attempts: 5
  alias Brando.Images
  alias Brando.Users
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "image_id" => image_id,
          "config_target" => config_target,
          "user_id" => user_id
        }
      }) do
    with {:ok, image} <- Images.get_image(image_id),
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
          Phoenix.PubSub.broadcast(
            Brando.pubsub(),
            "brando:image:#{image.id}",
            {image, [:image, :updated], []}
          )

          {:ok, image}

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
end
