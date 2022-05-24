defmodule Brando.Images do
  @moduledoc """
  Context for Images.
  Handles uploads too.
  Interfaces with database
  """

  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.Images.Image
  alias Brando.Images
  alias Brando.Users.User

  @type id :: binary | integer
  @type changeset :: changeset
  @type params :: map
  @type user :: User.t()

  query :single, Image, do: fn query -> from(t in query) end

  matches Image do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
    end
  end

  query :list, Image, do: fn query -> from(t in query) end

  filters Image do
    fn
      {:ids, ids}, query ->
        from t in query, where: t.id in ^ids

      {:config_target, nil}, query ->
        from(t in query)

      {:config_target, "default"}, query ->
        target_string = "default"
        from t in query, where: t.config_target == ^target_string

      {:config_target, target_string}, query when is_binary(target_string) ->
        from t in query, where: t.config_target == ^target_string

      {:config_target, {type, schema, field}}, query ->
        target_string = "#{type}:#{inspect(schema)}:#{field}"
        from t in query, where: t.config_target == ^target_string

      {:path, path}, query ->
        from q in query, where: ilike(q.path, ^"%#{path}%")
    end
  end

  mutation :update, Image
  mutation :delete, Image

  @doc """
  Create new image
  """
  @spec create_image(params, user) :: {:ok, Image.t()} | {:error, changeset}
  def create_image(params, user) do
    %Image{}
    |> Image.changeset(params, user)
    |> Brando.repo().insert
  end

  @doc """
  Get image.
  Raises on failure
  """
  def get_image!(id) do
    query =
      from t in Image,
        where: t.id == ^id and is_nil(t.deleted_at)

    Brando.repo().one!(query)
  end

  @doc """
  Delete `ids` from database
  Also deletes all dependent image sizes.
  """
  def delete_images(ids) when is_list(ids) do
    q = from m in Image, where: m.id in ^ids
    Brando.repo().soft_delete_all(q)
  end

  @spec get_image_orientation(integer, integer) :: binary
  def get_image_orientation(width, height) do
    (width > height && "landscape") || (width == height && "square") ||
      "portrait"
  end

  @spec get_image_orientation(map) :: binary
  def get_image_orientation(%{width: width, height: height}) do
    (width > height && "landscape") || (width == height && "square") ||
      "portrait"
  end

  def get_config_for(%{config_target: nil}) do
    struct(Brando.Type.ImageConfig, Brando.config(Brando.Images)[:default_config])
  end

  def get_config_for(%{config_target: config_target}) when is_binary(config_target) do
    config =
      case String.split(config_target, ":") do
        [type, schema, field_name] when type in ["image", "gallery"] ->
          schema_module = Module.concat([schema])

          field_name
          |> String.to_atom()
          |> schema_module.__asset_opts__()
          |> Map.get(:cfg)

        ["default"] ->
          struct(Brando.Type.ImageConfig, Brando.config(Brando.Images)[:default_config])
      end

    {:ok, config}
  end

  def get_config_for(config_target) when is_binary(config_target) do
    get_config_for(%{config_target: config_target})
  end

  def get_config_for(_) do
    get_config_for(%{config_target: "default"})
  end

  def get_processed_formats(path, nil) do
    original_type = Images.Utils.image_type(path)
    List.wrap(original_type)
  end

  def get_processed_formats(path, formats) do
    original_type = Images.Utils.image_type(path)
    Enum.map(formats, &((&1 == :original && original_type) || &1))
  end

  def list_generated_sizes(image) do
    {:ok, %{formats: formats, sizes: sizes}} = get_config_for(image)

    require Logger
    Logger.error(inspect(formats, pretty: true))
    Logger.error(inspect(sizes, pretty: true))
  end

  def duplicate_image(image_id, user) do
    original_image = get_image!(image_id)

    src_file =
      :media_path
      |> Brando.config()
      |> Path.join(original_image.path)

    new_file = Brando.Utils.unique_filename(original_image.path)

    dest_file =
      :media_path
      |> Brando.config()
      |> Path.join(new_file)

    with :ok <- File.cp(src_file, dest_file) do
      new_image_params =
        original_image
        |> Brando.Utils.map_from_struct()
        |> Map.drop([:id, :inserted_at, :updated_at])
        |> Map.put(:path, new_file)
        |> Map.put(:sizes, %{})
        |> Map.put(:status, :unprocessed)

      create_image(new_image_params, user)
    end
  end
end
