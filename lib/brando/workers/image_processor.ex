defmodule Brando.Worker.ImageProcessor do
  use Oban.Worker, queue: :default, max_attempts: 5
  alias Brando.Images
  alias Brando.Users
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "image_id" => image_id,
            "config_target" => config_target,
            "user_id" => user_id
          } = args
      }) do
    with {:ok, image} <- Images.get_image(image_id),
         {:ok, user} <- Users.get_user(user_id),
         {:ok, config} <- Images.get_config_for(config_target),
         {:ok, operations} <- Images.Operations.create(image, config, user),
         {:ok, process_map} <- Images.Operations.perform(operations, user) do
      result = Map.get(process_map, image_id)

      Images.update_image(
        image,
        %{
          sizes: result.sizes,
          formats: result.formats
        },
        user
      )

      # Phoenix.PubSub.broadcast(
      #   Brando.pubsub(),
      #   "brando:image_updated",
      #   {schema, [:image, :updated], []}
      # )
    else
      err ->
        {:error, err}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(180)
end
