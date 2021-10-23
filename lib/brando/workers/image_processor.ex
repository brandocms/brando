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
    Logger.info("==> ImageProcessor")
    Logger.info(inspect(args, pretty: true))

    with {:ok, image} <- Images.get_image(image_id),
         {:ok, user} <- Users.get_user(user_id),
         {:ok, config} <- Images.get_config_for(config_target),
         {:ok, operations} <- Images.Operations.create(image, config, nil, user),
         {:ok, %{sizes: processed_sizes, formats: processed_formats}} <-
           Images.Operations.perform(operations, user) do
      # {:ok, updated_image} =
      Images.update_image(image, %{sizes: processed_sizes, formats: processed_formats}, user)

      # Phoenix.PubSub.broadcast(
      #   Brando.pubsub(),
      #   "brando:image_updated",
      #   {schema, [:image, :updated], []}
      # )
    else
      err ->
        Logger.error(inspect(err, pretty: true))
    end

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(180)
end
