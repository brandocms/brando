defmodule Brando.Worker.ImageMaintenance do
  @moduledoc false
  # Runs the bulk image tools in the admin's Utilities over every image.
  #
  # Each job handles one batch and enqueues the next, so no job holds the whole
  # library in memory or runs into its timeout. The chained job keeps the
  # original arguments, including the tenant prefix `Brando.Tenant.Job` attached.
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Brando.Images.Image
  alias Brando.Images.Processing
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Users

  require Logger

  @tasks ~w(recreate_sizes dominant_colors)
  # Overridable per job through a "batch_size" argument.
  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => task}} = job) when task in @tasks do
    TenantJob.run(job, fn -> run_batch(task, job.args) end)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  defp run_batch(task, %{"user_id" => user_id} = args) do
    with {:ok, user} <- Users.get_user(user_id) do
      batch_size = Map.get(args, "batch_size", @batch_size)
      images = next_batch(task, Map.get(args, "after_id", 0), batch_size)
      Enum.each(images, &run_task(task, &1, user))
      continue(images, batch_size, args)
    end
  end

  defp next_batch(task, after_id, batch_size) do
    from(i in Image,
      where: i.id > ^after_id and is_nil(i.deleted_at),
      order_by: [asc: i.id],
      limit: ^batch_size
    )
    |> only_configured(task)
    |> Brando.Repo.all()
  end

  # Sizes come from the image's config; without a target there is nothing to
  # recreate them from.
  defp only_configured(query, "recreate_sizes"), do: where(query, [i], not is_nil(i.config_target))
  defp only_configured(query, _task), do: query

  # The per-image work is already a job of its own, so this only enqueues it.
  defp run_task("recreate_sizes", image, user), do: Processing.queue_processing(image, user, [], silent: true)

  defp run_task("dominant_colors", image, user) do
    case Processing.set_dominant_color(image, user) do
      {:ok, _image} -> :ok
      {:error, reason} -> Logger.warning("==> Dominant color not set for image #{image.id}: #{inspect(reason)}")
    end
  end

  # A full batch may have more after it; a short one was the last.
  defp continue(images, batch_size, args) when length(images) == batch_size do
    args
    |> Map.put("after_id", List.last(images).id)
    |> new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp continue(_images, _batch_size, _args), do: :ok
end
