defmodule Brando.Images.Processing do
  require Logger

  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Images.Operations
  alias Brando.Upload
  alias Brando.Users.User
  alias Brando.Worker
  alias Ecto.Changeset

  import Ecto.Query

  @type changeset :: Changeset.t()
  @type id :: binary | integer
  @type image :: Image.t()
  @type upload :: Upload.t()
  @type user :: User.t()

  @doc """
  Queue an image for processing
  """
  def queue_processing(image, user) do
    args = %{
      image_id: image.id,
      config_target: image.config_target,
      user_id: user.id
    }

    Brando.repo().delete_all(
      from j in Oban.Job,
        where: fragment("? @> ?", j.args, ^args)
    )

    args
    |> Worker.ImageProcessor.new(replace_args: true)
    |> Oban.insert()
  end

  @doc """
  Recreate all transforms for a single image
  """
  @spec recreate_sizes_for_image(image, user) :: {:ok, image} | {:error, changeset}
  def recreate_sizes_for_image(image, user) do
    queue_processing(image, user)
  end

  @doc """
  Recreate all transforms for all images
  """
  @spec recreate_sizes_for_images(user) :: list
  def recreate_sizes_for_images(user) do
    {:ok, images} = Images.list_images()

    for image <- images do
      recreate_sizes_for_image(image, user)
    end
  end

  @doc """
  Set dominant color for a single image
  """
  @spec set_dominant_color(image, user) :: {:ok, image} | {:error, changeset}
  def set_dominant_color(image, user) do
    dominant_color = Images.Operations.Info.get_dominant_color(image.path)
    Images.update_image(image, %{dominant_color: dominant_color}, user)
  end

  @doc """
  Set dominant color for all images
  """
  @spec set_dominant_color_for_images(user) :: list
  def set_dominant_color_for_images(user) do
    {:ok, images} = Images.list_images()

    for image <- images do
      set_dominant_color(image, user)
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

    %{cfg: cfg} = schema.__asset_opts__(field_name)

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

    updated_images =
      for {image_id, result} <- operation_results do
        images
        |> Enum.find(&(&1.id == image_id))
        |> Changeset.change(%{sizes: result.sizes, formats: result.formats})
        |> Brando.repo().update!
      end

    {:ok, Enum.map(updated_images, & &1.id)}
  end
end
