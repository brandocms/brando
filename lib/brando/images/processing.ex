defmodule Brando.Images.Processing do
  @moduledoc false
  import Ecto.Query

  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Images.Operations
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Type.ImageConfig
  alias Brando.Upload
  alias Brando.Users.User
  alias Brando.Worker
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type id :: binary | integer
  @type image :: Image.t()
  @type upload :: Upload.t()
  @type user :: User.t()

  @doc """
  Queue an image for processing
  """
  def queue_processing(image, user, field_full_path \\ [], opts \\ []) do
    args =
      TenantJob.attach(%{
        image_id: image.id,
        config_target: image.config_target,
        user_id: Brando.Users.job_user_id(user),
        field_full_path: field_full_path,
        silent: Keyword.get(opts, :silent, false)
      })

    Brando.Repo.delete_all(
      from j in Oban.Job,
        where: fragment("? @> ?", j.args, ^args)
    )

    args
    |> Worker.ImageProcessor.new(replace_args: true)
    |> Oban.insert()
  end

  @unfinished_states ~w(available scheduled executing retryable)

  @doc """
  Is an `ImageProcessor` job already queued or running for this image?

  For callers that re-queue *opportunistically* rather than because something
  changed — the image drawer re-queues on close. `queue_processing/4` deletes
  every matching job before inserting, which for a job in `executing` discards
  its row instead of deduping against it, leaving two passes writing the same
  derivative files. Ask this first and skip the re-queue.

  Matches on `image_id` alone: a job queued under a different
  `field_full_path` is still a pass over the same image.
  """
  def processing_queued?(%{id: image_id}) when not is_nil(image_id) do
    worker = Oban.Worker.to_string(Worker.ImageProcessor)
    args = TenantJob.attach(%{image_id: image_id})

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and
            j.state in ^@unfinished_states and
            fragment("? @> ?", j.args, ^args),
        select: true,
        limit: 1

    Brando.Repo.one(query) == true
  end

  def processing_queued?(_image), do: false

  @doc """
  Recreate all transforms for a single image
  """
  @spec recreate_sizes_for_image(image, user, list()) :: {:ok, image} | {:error, changeset}
  def recreate_sizes_for_image(image, user, field_full_path \\ []) do
    queue_processing(image, user, field_full_path)
  end

  @doc """
  Recreate all transforms for all images.

  Queues a background job that walks the images in batches and queues each
  one for processing, so it is safe to call from the admin or a release shell.
  Returns `{:error, :already_running}` while an earlier run is unfinished.
  """
  @spec recreate_sizes_for_images(user) :: {:ok, Oban.Job.t()} | {:error, :already_running | term}
  def recreate_sizes_for_images(user), do: start_image_maintenance("recreate_sizes", user)

  @doc """
  Recreate the sizes of the images whose config has changed since they were
  processed. See `changed_config?/2`.

  Runs in the background like `recreate_sizes_for_images/1`, and neither starts
  while the other is unfinished.
  """
  @spec recreate_sizes_for_changed_images(user) :: {:ok, Oban.Job.t()} | {:error, :already_running | term}
  def recreate_sizes_for_changed_images(user), do: start_image_maintenance("recreate_changed_sizes", user)

  @doc """
  The fingerprint of the config images with `config_target` are processed
  with today, or nil when the target no longer resolves to a config.
  """
  @spec current_fingerprint(String.t()) :: String.t() | nil
  def current_fingerprint(config_target) do
    {:ok, config} = Images.get_config_for(config_target)
    ImageConfig.fingerprint(config)
  rescue
    # A removed field or module: processing would fail the same way, so there
    # is nothing to recreate these images with.
    _error -> nil
  end

  @doc """
  Was the image processed with a config other than its target's current one?

  `current_fingerprint` is `current_fingerprint/1` for the image's target.
  Images processed before fingerprints were stored have none and count as
  changed. Images whose target no longer resolves never do.
  """
  @spec changed_config?(image, String.t() | nil) :: boolean
  def changed_config?(_image, nil), do: false
  def changed_config?(%{config_fingerprint: fingerprint}, current_fingerprint), do: fingerprint != current_fingerprint

  @doc """
  Counts the images `recreate_sizes_for_changed_images/1` would recreate.
  """
  @spec count_changed_images() :: non_neg_integer
  def count_changed_images do
    changed_config_targets() |> Map.values() |> Enum.sum()
  end

  @doc """
  The config targets whose current config differs from the one some of their
  images were made with, and how many images each: what
  `count_changed_images/0` counts, per target.
  """
  @spec changed_config_targets() :: %{String.t() => pos_integer}
  def changed_config_targets do
    %{changed: changed, unrecorded: unrecorded} = config_breakdown()
    Map.merge(changed, unrecorded, fn _target, a, b -> a + b end)
  end

  @doc """
  The images `changed_config_targets/0` counts, split in two, by config target:
  `changed` were made with a config that has since changed; `unrecorded` were
  made before Brando recorded configs, so whether theirs changed isn't known.
  """
  @spec config_breakdown() :: %{changed: %{String.t() => pos_integer}, unrecorded: %{String.t() => pos_integer}}
  def config_breakdown do
    query =
      from i in Image,
        where: is_nil(i.deleted_at) and not is_nil(i.config_target),
        group_by: [i.config_target, i.config_fingerprint],
        select: {i.config_target, i.config_fingerprint, count(i.id)}

    rows = Brando.Repo.all(query)

    current =
      rows
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Map.new(&{&1, current_fingerprint(&1)})

    Enum.reduce(rows, %{changed: %{}, unrecorded: %{}}, fn {config_target, fingerprint, count}, acc ->
      cond do
        not changed_config?(%{config_fingerprint: fingerprint}, current[config_target]) -> acc
        is_nil(fingerprint) -> update_in(acc, [:unrecorded, config_target], &((&1 || 0) + count))
        true -> update_in(acc, [:changed, config_target], &((&1 || 0) + count))
      end
    end)
  end

  @doc """
  Set dominant color for a single image.

  Leaves the stored color alone when none can be read from the file.
  """
  @spec set_dominant_color(image, user) :: {:ok, image} | {:error, changeset | :no_dominant_color}
  def set_dominant_color(image, user) do
    case Images.Operations.Info.get_dominant_color(image.path) do
      nil -> {:error, :no_dominant_color}
      dominant_color -> Images.update_image(image, %{dominant_color: dominant_color}, user)
    end
  end

  @doc """
  Set dominant color for all images.

  Runs in the background like `recreate_sizes_for_images/1`.
  """
  @spec set_dominant_color_for_images(user) :: {:ok, Oban.Job.t()} | {:error, :already_running | term}
  def set_dominant_color_for_images(user), do: start_image_maintenance("dominant_colors", user)

  @doc """
  Is a bulk image task (`"recreate_sizes"`, `"recreate_changed_sizes"` or
  `"dominant_colors"`) queued or running for the current tenant?
  """
  @spec image_maintenance_running?(String.t()) :: boolean
  def image_maintenance_running?(task) do
    worker = Oban.Worker.to_string(Worker.ImageMaintenance)
    args = TenantJob.attach(%{task: task})

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and
            j.state in ^@unfinished_states and
            fragment("? @> ?", j.args, ^args),
        select: true,
        limit: 1

    Brando.Repo.one(query) == true
  end

  # Both recreate tasks queue the same per-image jobs, so one waits for the other.
  @recreate_tasks ~w(recreate_sizes recreate_changed_sizes)

  defp start_image_maintenance(task, user) do
    blocking = if task in @recreate_tasks, do: @recreate_tasks, else: [task]

    if Enum.any?(blocking, &image_maintenance_running?/1) do
      {:error, :already_running}
    else
      %{task: task, user_id: user.id}
      |> TenantJob.attach()
      |> Worker.ImageMaintenance.new()
      |> Oban.insert()
    end
  end

  @doc """
  Recreates sizes for an image field.

  This applies to ALL records with matching schema/field, for instance if we want to recreate
  all transforms for the `avatar` field of our `User` schema:

      iex(1)> recreate_sizes_for_image_field(User, :avatar, current_user)

    This will recreate all transforms for all users
  """
  @spec recreate_sizes_for_image_field(module, atom, user) :: {:ok, [id]}
  def recreate_sizes_for_image_field(schema, field_name, user) do
    {:ok, images} =
      Brando.Images.list_images(%{filter: %{config_target: {"image", schema, field_name}}})

    %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(schema, field_name)

    operations =
      Enum.flat_map(images, fn image ->
        Images.Utils.delete_sized_images(image)

        {:ok, operations} =
          Operations.create(
            image,
            cfg,
            user
          )

        operations
      end)

    {:ok, operation_results} = Operations.perform(operations, user)
    images_by_id = Map.new(images, &{&1.id, &1})

    updated_images =
      for {image_id, result} <- operation_results do
        images_by_id
        |> Map.fetch!(image_id)
        |> Changeset.change(%{
          sizes: result.sizes,
          formats: result.formats,
          config_fingerprint: ImageConfig.fingerprint(cfg)
        })
        |> Brando.Repo.update!()
      end

    {:ok, Enum.map(updated_images, & &1.id)}
  end

  def recreate_sizes_for_image_field("default", user) do
    {:ok, images} = Brando.Images.list_images(%{filter: %{config_target: "default"}})
    {:ok, cfg} = Brando.Images.get_config_for(%{config_target: "default"})

    operations =
      Enum.flat_map(images, fn image ->
        Images.Utils.delete_sized_images(image)

        {:ok, operations} =
          Operations.create(
            image,
            cfg,
            user
          )

        operations
      end)

    {:ok, operation_results} = Operations.perform(operations, user)
    images_by_id = Map.new(images, &{&1.id, &1})

    updated_images =
      for {image_id, result} <- operation_results do
        images_by_id
        |> Map.fetch!(image_id)
        |> Changeset.change(%{
          sizes: result.sizes,
          formats: result.formats,
          config_fingerprint: ImageConfig.fingerprint(cfg)
        })
        |> Brando.Repo.update!()
      end

    {:ok, Enum.map(updated_images, & &1.id)}
  end
end
