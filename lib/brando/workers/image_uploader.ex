defmodule Brando.Worker.ImageUploader do
  @moduledoc """
  Uploads an image's original and sizes, in each of its formats, to its CDN
  (`Brando.CDN.queue_upload/4`)
  and marks it as on the CDN (`cdn: true`) once every file is up. A file that
  fails fails the job, which Oban retries; until then the image keeps being
  served from the media folder, where its files stay until all are up
  (`keep_local_copy: false` removes them after).

  Before 0.55 each file had a job of its own (with a `src_key`). The first of
  those to run after an upgrade queues one job for the image in their place
  (`after_per_file`), which doesn't upload again a file one of them already
  uploaded and removed (`keep_local_copy: false`).
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Brando.CDN
  alias Brando.Images
  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{
         args: %{"src_key" => _, "image_id" => image_id, "user_id" => user_id, "field_full_path" => field_full_path}
       }) do
    case Images.get_image(image_id) do
      {:ok, image} ->
        with {:ok, _job} <- CDN.queue_upload(image, user(user_id), field_full_path, after_per_file: true), do: :ok

      {:error, _} ->
        {:cancel, :image_not_found}
    end
  end

  defp perform_tenant(%Oban.Job{
         id: job_id,
         args: %{"image_id" => image_id, "user_id" => user_id, "field_full_path" => field_full_path} = args
       }) do
    BrandoAdmin.Progress.show(user_id || :system)

    try do
      upload(job_id, image_id, user_id, field_path(field_full_path), after_per_file: args["after_per_file"] == true)
    after
      BrandoAdmin.Progress.hide(user_id || :system)
    end
  end

  defp upload(job_id, image_id, user_id, field_full_path, opts) do
    with {:ok, image} <- Images.get_image(image_id),
         {:ok, config} <- Images.get_config_for(image.config_target),
         :ok <- CDN.upload_image_files(image, config, user_id || :system, opts),
         false <- CDN.image_upload_waiting?(image_id, job_id),
         {:ok, image} <- Images.update_image(image, %{cdn: true}, user(user_id)) do
      CDN.remove_local_copies(image, config)
      broadcast_status(image, field_full_path, :updated)
    else
      # Processed again while this ran (a new crop): the job queued then
      # uploads the new files and marks the image
      true ->
        :ok

      {:error, {:image, :not_found}} ->
        {:cancel, :image_not_found}

      # A stored path that leaves the media root never uploads
      {:error, :unsafe_media_path} ->
        {:cancel, :unsafe_media_path}

      err ->
        {:error, err}
    end
  end

  defp user(nil), do: :system
  defp user(user_id), do: %{id: user_id}

  defp field_path(field_full_path) do
    Enum.map(field_full_path, fn
      segment when is_binary(segment) -> String.to_existing_atom(segment)
      integer -> integer
    end)
  end

  # Each file has three minutes
  @impl Oban.Worker
  def timeout(%Oban.Job{args: args}), do: :timer.seconds(180) * max(args["files"] || 1, 1)

  defp broadcast_status(image, path, status) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:image:#{image.id}",
      {image, [:image, status], path}
    )

    {:ok, image}
  end
end
