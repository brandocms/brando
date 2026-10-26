defmodule Brando.Worker.ImageUploader do
  @moduledoc """
  Uploads an image's original and sizes, in each of its formats, to its CDN
  (`Brando.CDN.queue_upload/4`) and marks it as on the CDN (`cdn: true`) once
  every file is up. A file that fails fails the job, which Oban retries;
  until then the image keeps being served from the media folder, where its
  files stay until all are up (`keep_local_copy: false` removes them after).

  While the image is being processed (a new crop, say), its files change:
  the job waits, snoozing, and processing queues an upload when it is done,
  which replaces this one (after ten minutes the job fails and Oban retries
  it, and it never removes files the processing needs). An upload queued after this one leaves the work
  to it.

  Before 0.55 each file had a job of its own (with a `src_key`). The first of
  those to run after an upgrade queues one job for the image in their place
  (`after_per_file`), which doesn't upload again a file one of them already
  uploaded and removed (`keep_local_copy: false`).
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  # The processing that queued the upload is done moments after it does
  @snooze 5
  # Ten minutes of waiting for the image's processing
  @max_snoozes 120

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

  defp perform_tenant(
         %Oban.Job{
           id: job_id,
           args: %{"image_id" => image_id, "user_id" => user_id, "field_full_path" => field_full_path} = args
         } = job
       ) do
    cond do
      # Another upload of the image, queued after this one, uploads its
      # files as they are now and marks it
      CDN.newer_image_upload?(image_id, job_id) ->
        :ok

      wait = processing(image_id, job) ->
        wait

      true ->
        BrandoAdmin.Progress.show(user_id || :system)

        try do
          upload(job, image_id, user_id, field_path(field_full_path), after_per_file: args["after_per_file"] == true)
        after
          BrandoAdmin.Progress.hide(user_id || :system)
        end
    end
  end

  defp upload(%Oban.Job{id: job_id} = job, image_id, user_id, field_full_path, opts) do
    with {:ok, image} <- Images.get_image(image_id),
         {:ok, config} <- Images.get_config_for(image.config_target),
         :ok <- CDN.upload_image_files(image, config, user_id || :system, opts),
         {:newer_upload, false} <- {:newer_upload, CDN.newer_image_upload?(image_id, job_id)},
         nil <- processing(image_id, job),
         # Marking the upload done is the system's work: the uploader's role
         # may have changed since, and only their progress display is theirs
         {:ok, image} <- Images.update_image(image, %{cdn: true}, :system) do
      CDN.remove_local_copies(image, config)
      broadcast_status(image, field_full_path, :updated)
    else
      # Another upload of the image, queued after this one, uploads its files
      # as they are now and marks it
      {:newer_upload, true} ->
        :ok

      # Processed again while this ran: wait for it, and for the upload it
      # queues, which replaces this one
      {:snooze, _seconds} = snooze ->
        snooze

      {:error, :processing} = error ->
        error

      {:error, {:image, :not_found}} ->
        {:cancel, :image_not_found}

      # A stored path that leaves the media root never uploads
      {:error, :unsafe_media_path} ->
        {:cancel, :unsafe_media_path}

      err ->
        {:error, err}
    end
  end

  # The image is being processed (a new crop): its files are changing, and
  # processing queues an upload when it is done, which replaces this one.
  # Wait for it, for a while (a job that snoozes never runs out of
  # attempts); then fail, so Oban retries a few times more (if the
  # processing was cancelled meanwhile, this uploads), rather than remove
  # files the processing still needs.
  defp processing(image_id, %Oban.Job{meta: meta}) do
    cond do
      not Images.Processing.processing_queued?(%{id: image_id}) -> nil
      (meta["snoozed"] || 0) < @max_snoozes -> {:snooze, @snooze}
      true -> {:error, :processing}
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
