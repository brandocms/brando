defmodule Brando.Images.Operations do
  @moduledoc """
  This is where we process images
  """
  @type image :: Brando.Type.Image.t()
  @type image_config :: Brando.Type.ImageConfig.t()
  @type operation :: Brando.Images.Operation.t()
  @type operation_result :: Brando.Images.OperationResult.t()
  @type user :: Brando.User.t() | :system

  alias Brando.Images
  alias Brando.Progress
  alias Brando.Utils

  @doc """
  Creates an %Operation{} for each size key in `cfg`s `:sizes`

  ## Example

      {:ok, operations} = create_operations(img_struct, img_cfg, user, id)

  """
  @spec create_operations(
          img_struct :: image,
          cfg :: image_config,
          user :: user,
          id :: integer | nil
        ) ::
          {:ok, [operation]}
  def create_operations(img_struct, cfg, user, id \\ nil) do
    id = (id && id) || Utils.random_string(:os.timestamp())
    {_, filename} = Utils.split_path(img_struct.path)
    type = Images.Utils.image_type(img_struct.path)

    operations =
      for {size_key, size_cfg} <- Map.get(cfg, :sizes) do
        %Images.Operation{
          id: id,
          user: user,
          img_struct: img_struct,
          filename: filename,
          type: type,
          size_cfg: size_cfg,
          size_key: size_key
        }
      end

    {:ok, operations}
  end

  @doc """
  Perform list of image operations as Flow
  """
  @spec perform_operations(operations :: [operation], user :: user) :: {:ok, [operation_result]}
  def perform_operations(operations, user) do
    Progress.show_progress(user)

    operation_results =
      operations
      |> Flow.from_enumerable(stages: 5, max_demand: 1)
      |> Flow.map(&resize_image/1)
      |> Flow.reduce(fn -> %{} end, fn operation, map ->
        Map.update(map, operation.id, [operation], &[operation | &1])
      end)
      |> Flow.departition(&Map.new/0, &Map.merge(&1, &2, fn _, la, lb -> la ++ lb end), & &1)
      |> Enum.map(fn result -> compile_transform_results(result, operations) end)
      |> List.flatten()

    Progress.hide_progress(user)

    {:ok, operation_results}
  end

  # assemble all `%TransformResult{}`s for each id
  defp compile_transform_results(transform_results, operations) do
    for {key, transforms} <- transform_results do
      operation = get_operation_by_key(key, operations)
      img_struct = Map.put(operation.img_struct, :sizes, transforms_to_sizes(transforms))

      %Images.OperationResult{
        id: key,
        img_struct: img_struct
      }
    end
  end

  # convert a list of transforms to a map of sizes
  defp transforms_to_sizes(transforms) do
    transforms
    |> Enum.map(&{&1.size_key, &1.image_path})
    |> Enum.into(%{})
  end

  defp get_operation_by_key(key, operations) do
    Enum.find(operations, &(&1.id == key))
  end

  defp resize_image(%Images.Operation{size_key: size_key, img_struct: %{path: path}} = operation) do
    operation =
      Map.merge(operation, %{
        sized_img_dir: Images.Utils.get_sized_dir(path, size_key),
        sized_img_path: Images.Utils.get_sized_path(path, size_key)
      })

    with {:ok, transform_result} <- Images.Operations.Sizing.create_image_size(operation) do
      transform_result
    end
  end
end
