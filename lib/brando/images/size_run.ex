defmodule Brando.Images.SizeRun do
  @moduledoc false
  # A run of Utilities → Image sizes: **Recreate image sizes** or **Recreate
  # changed images**, from the click to the last image processed.
  #
  # `Brando.Worker.ImageMaintenance` walks the images in batches and queues an
  # `ImageProcessor` job for each image to recreate. The run reports to the
  # admin who started it as `BrandoAdmin.Work` under `work_key/0`, counting each
  # image when its job succeeds or gives up:
  #
  #   * `begin/1`, before the walk is queued, starts the work, open (more
  #     batches may follow) and with nothing counted yet;
  #   * `queue/2`, per batch, adds the batch's images to the count, then
  #     queues them, each tracked as a step that names its image when it fails;
  #   * `close/2`, after the last batch, says there are no more: the work ends
  #     when the last queued image is done, or at once when there were none.
  #
  # Whether a run is going on comes from the jobs, not from that work, which
  # only its admin sees: `running?/0` is true while the walk or any image it
  # queued is waiting or being processed, for every admin, on every node.
  #
  # Later steps of the same run (re-rendering the entries that show a recreated
  # image) can join its count with `BrandoAdmin.Work.start/4` and `total:`
  # before the last image's step is in, as `queue/2` does.
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Images.Processing
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Worker
  alias BrandoAdmin.Work

  @work_key "image-sizes"
  # In each image job's meta, so the run's jobs can be found
  @meta_key "image_size_run"
  @tasks ~w(recreate_sizes recreate_changed_sizes)
  @unfinished_states ~w(available scheduled executing retryable)
  # Images can wait behind other image work; a stalled run is given up later
  @timeout to_timeout(minute: 30)

  @doc "The `BrandoAdmin.Work` key a run reports under."
  @spec work_key() :: String.t()
  def work_key, do: @work_key

  @doc "The image maintenance tasks that are a run."
  @spec tasks() :: [String.t()]
  def tasks, do: @tasks

  @doc """
  Is a run going on in the current site: its walk unfinished, or an image it
  queued waiting or being processed?
  """
  @spec running?() :: boolean()
  def running? do
    Enum.any?(@tasks, &Processing.image_maintenance_running?/1) or remaining() > 0
  end

  @doc "How many images the runs in the current site have queued and not finished."
  @spec remaining() :: non_neg_integer()
  def remaining do
    worker = Oban.Worker.to_string(Worker.ImageProcessor)
    args = TenantJob.attach(%{})

    Brando.Repo.one(
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state in ^@unfinished_states and
            fragment("? @> ?", j.meta, ^%{@meta_key => true}) and
            fragment("? @> ?", j.args, ^args),
        select: count(j.id)
    )
  end

  @doc """
  Starts the run's work for `user`, before its walk is queued. Work still
  running under the key belongs to no run (none is going on), and is ended.
  """
  @spec begin(Processing.user()) :: :ok
  def begin(user) do
    if Work.running?(Work.get(user, @work_key)), do: Work.fail(user, @work_key)

    Work.in_locale(user, fn ->
      Work.start(user, @work_key, gettext("Recreating image sizes"),
        total: 0,
        open: true,
        timeout: @timeout,
        done: gettext("Image sizes recreated"),
        failed: gettext("Some images could not be recreated")
      )
    end)
  end

  @doc "Ends the work of a run whose walk could not be queued."
  @spec abort(Processing.user()) :: :ok
  def abort(user), do: Work.fail(user, @work_key)

  @doc """
  Adds `images` to the run's count, then queues each one to be recreated.
  Returns how many it queued.
  """
  @spec queue([Processing.image()], Processing.user()) :: non_neg_integer()
  def queue([], _user), do: 0

  def queue(images, user) do
    Work.start(user, @work_key, nil, total: length(images))

    Enum.each(images, fn image ->
      prepare = fn changeset -> mark(changeset, user, image) end

      case Processing.queue_processing(image, user, [], silent: true, prepare: prepare) do
        {:ok, _job} -> :ok
        # Counted, and never run: it failed
        {:error, _reason} -> Work.advance(user, @work_key, :error, item: image.id)
      end
    end)

    length(images)
  end

  @doc """
  No more images: the run ends when the last queued one is done, or at once
  when `queued`, the run's count, is none.
  """
  @spec close(Processing.user(), non_neg_integer()) :: :ok
  def close(user, queued) do
    Work.in_locale(user, fn ->
      done =
        if queued == 0,
          do: gettext("No images to recreate"),
          else: ngettext("%{count} image recreated", "%{count} images recreated", queued)

      Work.close(user, @work_key, done: done)
    end)
  end

  defp mark(changeset, user, image) do
    meta = Ecto.Changeset.get_field(changeset, :meta) || %{}

    changeset
    |> Ecto.Changeset.put_change(:meta, Map.put(meta, @meta_key, true))
    |> Work.track(user, @work_key, step: true, item: image.id)
  end
end
