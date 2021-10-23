defmodule Brando.Images.Operations do
  @moduledoc """
  This is where we process images
  """
  require Logger

  alias Brando.Images
  alias BrandoAdmin.Progress
  alias Brando.Utils

  @type image :: Brando.Images.Image.t()
  @type image_config :: Brando.Type.ImageConfig.t()
  @type operation :: Brando.Images.Operation.t()
  @type operation_result :: Brando.Images.OperationResult.t()
  @type user :: Brando.Users.User.t() | :system

  @doc """
  Creates an %Operation{} for each size key in `cfg`s `:sizes` and for each
  format in `cfg`s `:formats`

  ## Example

      {:ok, operations} = create(image, image_config, id, user)

  """
  @spec create(
          image :: image,
          cfg :: image_config,
          id :: integer | nil,
          user :: user
        ) :: {:ok, [operation]}
  def create(%{path: path} = image_struct, cfg, id, user) do
    id = id || Utils.random_string(:os.timestamp())
    {_, filename} = Utils.split_path(path)

    sizes = Map.get(cfg, :sizes)
    formats = Map.get(cfg, :formats)

    total_operations = Enum.count(Map.keys(sizes)) * Enum.count(formats)
    processed_formats = Images.get_processed_formats(path, formats)
    original_type = Images.Utils.image_type(path)

    operations =
      Enum.map(formats, fn format ->
        image_type = (format == :original && original_type) || format

        {format_operations, _} =
          Enum.reduce(sizes, {[], 0}, fn {size_key, size_cfg}, {ops, idx} ->
            sized_image_dir = Images.Utils.get_sized_dir(path, size_key)
            sized_image_path = Images.Utils.get_sized_path(path, size_key, image_type)

            operation = %Images.Operation{
              id: id,
              type: image_type,
              user: user,
              filename: filename,
              processed_formats: processed_formats,
              image_struct: image_struct,
              size_cfg: size_cfg,
              size_key: size_key,
              sized_image_dir: sized_image_dir,
              sized_image_path: sized_image_path,
              total_operations: total_operations,
              operation_index: idx + 1
            }

            {ops ++ [operation], idx + 1}
          end)

        format_operations
      end)

    {:ok, List.flatten(operations)}
  end

  @doc """
  Perform list of image operations as Flow
  """
  @spec perform([operation], user) :: {:ok, [operation_result]}
  def perform(operations, user) do
    Progress.show(user)

    Logger.debug("==> Brando.Images.Operations: Starting #{Enum.count(operations)} operations..")

    start_msec = :os.system_time(:millisecond)

    operation_results =
      operations
      |> Enum.map(&resize_image/1)
      |> compile_transform_results(operations)

    require Logger
    Logger.error(inspect(operation_results, pretty: true))

    end_msec = :os.system_time(:millisecond)
    seconds_lapsed = (end_msec - start_msec) * 0.001

    Logger.debug("==> Brando.Images.Operations: Finished in #{seconds_lapsed} seconds..")

    Progress.hide(user)

    {:ok, operation_results}
  end

  defp compile_transform_results(transform_results, operations) do
    processed_formats =
      operations
      |> List.first()
      |> Map.get(:processed_formats)

    sizes = transforms_to_sizes(transform_results)

    %Images.OperationResult{
      sizes: sizes,
      formats: processed_formats
    }
  end

  # convert a list of transforms to a map of sizes
  defp transforms_to_sizes(transforms) do
    transforms
    |> Enum.map(&{&1.size_key, &1.image_path})
    |> Enum.into(%{})
  end

  defp get_operation_by_key(key, operations), do: Enum.find(operations, &(&1.id == key))

  defp resize_image(%Images.Operation{} = operation) do
    {:ok, transform_result} = Images.Operations.Sizing.create_image_size(operation)
    transform_result
  end
end
