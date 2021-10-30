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
  def recreate_sizes_for_image(%{id: image_id} = image, user) do
    {:ok, image_config} = Images.get_config_for(image)
    Images.Utils.delete_sized_images(image)

    with {:ok, ops} <- Operations.create(image, image_config, user),
         {:ok, %{^image_id => result}} <- Images.Operations.perform(ops, user) do
      image
      |> Image.changeset(%{sizes: result.sizes, formats: result.formats})
      |> Brando.repo().update
    else
      err ->
        Logger.error("""

        ==> recreate_sizes_for(:image, ...) failed
        #{inspect(err)}

        """)

        err
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
    {:ok, images} = Brando.Images.list_images(%{filter: %{config_target: {schema, field_name}}})
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
