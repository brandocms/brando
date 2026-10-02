defmodule Brando.Images.Processing do
  @moduledoc false
  import Ecto.Query

  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Images.Operations
  alias Brando.Tenant.Job, as: TenantJob
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
        user_id: user.id,
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
  Is a bulk image task (`"recreate_sizes"` or `"dominant_colors"`) queued or
  running for the current tenant?
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

  defp start_image_maintenance(task, user) do
    if image_maintenance_running?(task) do
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
        |> Changeset.change(%{sizes: result.sizes, formats: result.formats})
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
        |> Changeset.change(%{sizes: result.sizes, formats: result.formats})
        |> Brando.Repo.update!()
      end

    {:ok, Enum.map(updated_images, & &1.id)}
  end
end
