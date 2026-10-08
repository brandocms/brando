defmodule Brando.Worker.ImageMaintenance do
  @moduledoc false
  # Runs the bulk image tools in the admin's Utilities over every image.
  #
  # Each job handles one batch and enqueues the next, so no job holds the whole
  # library in memory or runs into its timeout. The chained job keeps the
  # original arguments, including the tenant prefix `Brando.Tenant.Job` attached.
  #
  # "recreate_changed_sizes" first adopts the images processed before configs
  # were recorded whose files already match (`Brando.Images.Adoption`), and
  # queues only the rest. It carries the counts from batch to batch in its
  # arguments and broadcasts them on `Processing.topic/0`.
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Brando.Images.Adoption
  alias Brando.Images.Image
  alias Brando.Images.Processing
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Users

  require Logger

  @tasks ~w(recreate_sizes recreate_changed_sizes dominant_colors)
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

      counts =
        images
        |> only_changed(task)
        |> run_tasks(task, user)

      args = Map.merge(args, counts, fn _key, total, count -> total + count end)

      case continue(images, batch_size, args) do
        :done ->
          finish(task, args)

        result ->
          progress(task, :running, args)
          result
      end
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
  defp only_configured(query, task) when task in ["recreate_sizes", "recreate_changed_sizes"],
    do: where(query, [i], not is_nil(i.config_target))

  defp only_configured(query, _task), do: query

  # Filtered after the batch is read rather than in the query, since the
  # current fingerprint comes from code, not the database. Each target's is
  # resolved once per batch.
  defp only_changed(images, "recreate_changed_sizes") do
    current =
      images
      |> Enum.map(& &1.config_target)
      |> Enum.uniq()
      |> Map.new(&{&1, Processing.current_fingerprint(&1)})

    Enum.filter(images, &Processing.changed_config?(&1, current[&1.config_target]))
  end

  defp only_changed(images, _task), do: images

  # Images processed before configs were recorded are kept when their files
  # already match their config; only the rest are recreated.
  defp run_tasks(images, "recreate_changed_sizes" = task, user) do
    {adopted, rest} = Adoption.adopt(images)
    Enum.each(rest, &run_task(task, &1, user))
    %{"adopted" => length(adopted), "recreated" => length(rest)}
  end

  defp run_tasks(images, task, user) do
    Enum.each(images, &run_task(task, &1, user))
    %{}
  end

  # The per-image work is already a job of its own, so this only enqueues it.
  defp run_task(task, image, user) when task in ["recreate_sizes", "recreate_changed_sizes"],
    do: Processing.queue_processing(image, user, [], silent: true)

  defp run_task("dominant_colors", image, user) do
    case Processing.set_dominant_color(image, user) do
      {:ok, _image} -> :ok
      {:error, reason} -> Logger.warning("==> Dominant color not set for image #{image.id}: #{inspect(reason)}")
    end
  end

  # A full batch may have more after it; a short one was the last. Only a full
  # batch has its last slot filled.
  defp continue(images, batch_size, args) do
    case Enum.at(images, batch_size - 1) do
      nil -> :done
      last -> enqueue_after(last.id, args)
    end
  end

  defp finish("recreate_changed_sizes" = task, args) do
    Logger.info(
      "==> Recreate changed images: #{args["adopted"] || 0} already matched their config, #{args["recreated"] || 0} recreated"
    )

    progress(task, :done, args)
    :ok
  end

  defp finish(_task, _args), do: :ok

  defp progress("recreate_changed_sizes" = task, state, args) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Processing.topic(),
      {:image_maintenance, %{task: task, state: state, adopted: args["adopted"] || 0, recreated: args["recreated"] || 0}}
    )
  end

  defp progress(_task, _state, _args), do: :ok

  defp enqueue_after(id, args) do
    args
    |> Map.put("after_id", id)
    |> new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
