defmodule Brando.Worker.ImageProcessor do
  @moduledoc false
  use Oban.Worker, queue: :image_processing, max_attempts: 5

  alias Brando.Assets.CompletedCallback
  alias Brando.Assets.ProcessingStatus
  alias Brando.Images
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Type.ImageConfig
  alias Brando.Users

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(
         %Oban.Job{
           args:
             %{
               "image_id" => image_id,
               "config_target" => config_target,
               "user_id" => user_id,
               "field_full_path" => field_full_path
             } = args
         } = job
       ) do
    silent? = Map.get(args, "silent", false)

    field_full_path =
      Enum.map(field_full_path, fn
        segment when is_binary(segment) -> String.to_existing_atom(segment)
        integer -> integer
      end)

    with {:ok, image} <- Images.get_image(image_id),
         {:ok, original} <- Images.restore_original(image) do
      process(job, image, original, config_target, user_id, field_full_path, silent?)
    else
      err ->
        handle_processing_error(job, image_id, field_full_path, err)
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(400)

  # An original restored from the CDN for this run is removed again unless
  # the image is handed over for delivery, which removes it with the sizes
  # (`keep_local_copy: false`). A retry restores it again.
  defp process(job, image, original, config_target, user_id, field_full_path, silent?) do
    result =
      try do
        with {:ok, _} <- broadcast_status(image, field_full_path, :processing),
             # Before the sizes go: an image over the limit keeps the ones it has
             :ok <- Images.PixelLimit.check_image(image),
             {:ok, _} <- Images.Utils.delete_sized_images(image),
             {:ok, user} <- Users.get_job_user(user_id),
             {:ok, config} <- Images.get_config_for(config_target),
             {:ok, operations} <- Images.Operations.create(image, config, user),
             {:ok, process_map} <- Images.Operations.perform(operations, user, silent: silent?) do
          update_processed(image, Map.fetch!(process_map, image.id), config, user)
        end
      rescue
        error ->
          Images.discard_restored_original(image, original)
          reraise error, __STACKTRACE__
      end

    case result do
      {:processed, image, config, user} ->
        finish_processing(image, original, config, user, field_full_path)

      {:not_updated, error} ->
        Images.discard_restored_original(image, original)
        error

      {:error, :too_many_pixels} ->
        Images.discard_restored_original(image, original)
        broadcast_processing_error(image.id, field_full_path)
        {:cancel, :too_many_pixels}

      err ->
        Images.discard_restored_original(image, original)
        handle_processing_error(job, image.id, field_full_path, err)
    end
  end

  defp update_processed(image, result, config, user) do
    image_params =
      Map.merge(
        %{
          formats: result.formats,
          sizes: result.sizes,
          status: :processed,
          config_fingerprint: ImageConfig.fingerprint(config)
        },
        upright_dimensions(image)
      )

    case Images.update_image(image, image_params, user) do
      {:ok, image} -> {:processed, image, config, user}
      error -> {:not_updated, error}
    end
  end

  # A callback that raises fails the job before the image is handed over
  defp finish_processing(image, original, config, user, field_full_path) do
    try do
      CompletedCallback.run(config, image, user)
    rescue
      error ->
        Images.discard_restored_original(image, original)
        reraise error, __STACKTRACE__
    end

    Brando.CDN.maybe_upload_image(image, field_full_path, user, config)
    ProcessingStatus.broadcast(:image, image, :done)
    broadcast_status(image, field_full_path, :updated)
  end

  # Images uploaded before Brando recorded upright dimensions have those of
  # the file as stored. A photo stored on its side gets them turned, so that
  # rendering (width and height, srcset widths) matches what is shown.
  defp upright_dimensions(%{path: path, width: width, height: height}) when is_binary(path) do
    with {:ok, img} <- Image.open(Images.Utils.media_path(path)),
         true <- Images.Utils.rotated?(img),
         {upright_width, upright_height} when {upright_width, upright_height} != {width, height} <-
           Images.Utils.upright_dimensions(img) do
      %{width: upright_width, height: upright_height}
    else
      _ -> %{}
    end
  end

  defp upright_dimensions(_image), do: %{}

  defp handle_processing_error(job, image_id, field_full_path, error) do
    # Earlier attempts may still succeed; only a terminal broadcast should
    # release subscribers from their processing state.
    if job.attempt >= job.max_attempts do
      broadcast_processing_error(image_id, field_full_path)
    end

    {:error, error}
  end

  defp broadcast_processing_error(image_id, field_full_path) do
    case Images.get_image(image_id) do
      {:ok, image} ->
        ProcessingStatus.broadcast(:image, image, :failed)
        broadcast_status(image, field_full_path, :error)

      _error ->
        :noop
    end
  end

  defp broadcast_status(image, path, status) do
    Logger.info(
      "==> Broadcasting image #{status}: id=#{image.id}, path=#{inspect(path)}, channel=brando:image:#{image.id}"
    )

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:image:#{image.id}",
      {image, [:image, status], path}
    )

    {:ok, image}
  end
end
