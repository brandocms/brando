defmodule Brando.Worker.ImageUploader do
  use Oban.Worker, queue: :default, max_attempts: 5
  import Ecto.Query
  alias Brando.CDN
  alias Brando.Images
  alias Brando.Tenant.Job, as: TenantJob
  # alias Brando.Users

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{
         id: job_id,
         args: %{
           "image_id" => image_id,
           "src_key" => src_key,
           "dest_key" => dest_key,
           "user_id" => user_id,
           "config_target" => config_target,
           "field_full_path" => field_full_path
         }
       }) do
    BrandoAdmin.Progress.show(user_id)

    field_full_path =
      Enum.map(field_full_path, fn
        segment when is_binary(segment) -> String.to_existing_atom(segment)
        integer -> integer
      end)

    with {:ok, config} <- Images.get_config_for(config_target),
         {:ok, s3_key} <- CDN.upload_image(src_key, dest_key, config, user_id) do
      if any_remaining_jobs?(image_id, job_id) do
        {:ok, s3_key}
      else
        finalize_image_upload(image_id, user_id, field_full_path)
      end
    else
      err ->
        {:error, err}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(180)

  defp finalize_image_upload(image_id, user_id, field_full_path) do
    BrandoAdmin.Progress.hide(user_id)
    {:ok, image} = Images.get_image(image_id)

    case Images.update_image(image, %{cdn: true}, %{id: user_id}) do
      {:ok, image} -> broadcast_status(image, field_full_path, :updated)
      err -> err
    end
  end

  defp any_remaining_jobs?(image_id, job_id) do
    context = TenantJob.context_fragment()

    query =
      from j in Oban.Job,
        select: [j.id],
        where:
          ^"image_upload_#{image_id}" in j.tags and
            j.state != ^"completed" and
            fragment("? @> ?", j.args, ^context)

    result = Brando.Repo.all(query)
    result != [[job_id]]
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
