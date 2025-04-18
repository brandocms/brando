defmodule Brando.Images.Operations do
  @moduledoc """
  This is where we process images
  """
  alias Brando.Images
  alias Brando.Utils
  alias BrandoAdmin.Progress

  require Logger

  @type image :: Brando.Images.Image.t()
  @type image_config :: Brando.Type.ImageConfig.t()
  @type operation :: Brando.Images.Operation.t()
  @type operation_result :: Brando.Images.OperationResult.t()
  @type user :: Brando.Users.User.t() | :system

  @doc """
  Creates an %Operation{} for each size key in `cfg`s `:sizes` and for each
  format in `cfg`s `:formats`

  ## Example

      {:ok, operations} = create(image, image_config, user)

  """
  @spec create(
          image :: image,
          cfg :: image_config,
          user :: user
        ) :: {:ok, [operation]}
  def create(%{path: path, id: id} = image_struct, cfg, user) do
    user_id = (is_map(user) && user.id) || user
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
              image_id: id,
              type: image_type,
              user_id: user_id,
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
  Perform list of image operations
  """
  @spec perform([operation], user) :: {:ok, map}
  def perform([], _) do
    {:ok, %{}}
  end

  def perform(operations, user) do
    max_concurrency = Application.get_env(:brando, :concurrent_image_jobs) || 1

    Progress.show(user.id)
    start_msec = :os.system_time(:millisecond)

    operation_results =
      if max_concurrency > 1 do
        operations
        |> Task.async_stream(&__MODULE__.resize_image/1,
          max_concurrency: max_concurrency,
          timeout: 60_000
        )
        |> Enum.to_list()
        |> Enum.map(&elem(&1, 1))
        |> compile_transform_results(operations)
      else
        operations
        |> Enum.map(&__MODULE__.resize_image/1)
        |> compile_transform_results(operations)
      end

    end_msec = :os.system_time(:millisecond)
    seconds_lapsed = (end_msec - start_msec) * 0.001

    Logger.debug("==> Brando.Images.Operations: Finished in #{seconds_lapsed} seconds..")

    Progress.hide(user.id)

    {:ok, operation_results}
  end

  # assemble all `%TransformResult{}`s for each id
  defp compile_transform_results(transform_results, operations) do
    transform_results
    |> Enum.reduce(%{}, fn result, map ->
      Map.update(map, result.image_id, [result], &[result | &1])
    end)
    |> Enum.reduce(%{}, fn {image_id, transforms}, map ->
      operation = get_operation_by_image_id(image_id, operations)

      result = %Images.OperationResult{
        image_id: image_id,
        sizes: transforms_to_sizes(transforms),
        formats: operation.processed_formats
      }

      Map.put(map, result.image_id, result)
    end)
  end

  defp get_operation_by_image_id(image_id, operations), do: Enum.find(operations, &(&1.image_id == image_id))

  # convert a list of transforms to a map of sizes
  defp transforms_to_sizes(transforms) do
    Map.new(transforms, &{&1.size_key, &1.image_path})
  end

  def resize_image(%Images.Operation{} = operation) do
    case Images.Operations.Sizing.create_image_size(operation) do
      {:ok, transform_result} ->
        transform_result

      {:error, err} ->
        raise Brando.Exception.ImageProcessingError,
          message: """


          Failed creating image size

          #{inspect(err, pretty: true)}
          """
    end
  end
end
