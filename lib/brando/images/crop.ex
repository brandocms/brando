defmodule Brando.Images.Crop do
  @moduledoc """
  Handles saving cropped/edited images from the Image Editor.
  """

  alias Brando.Images

  @doc """
  Save a cropped image as a new copy.

  Writes the binary data as a new file with unique filename,
  creates a new Image record with same `config_target` as original,
  sets the provided focal point, and queues image processing.

  ## Examples

      iex> save_as_new_copy(original_image, binary_data, %{x: 50, y: 50}, user)
      {:ok, %Brando.Images.Image{}}
  """
  def save_as_new_copy(original_image, binary_data, focal, user) do
    media_path = Brando.config(:media_path)
    new_path = Brando.Utils.unique_filename(original_image.path)

    dest_file =
      media_path
      |> Path.join(new_path)

    File.mkdir_p!(Path.dirname(dest_file))
    File.write!(dest_file, binary_data)

    {width, height} =
      case Image.open(dest_file) do
        {:ok, img} -> {Image.width(img), Image.height(img)}
        _ -> {nil, nil}
      end

    new_image_params = %{
      path: new_path,
      width: width,
      height: height,
      focal: focal,
      config_target: original_image.config_target,
      status: :unprocessed,
      sizes: %{},
      formats: []
    }

    case Images.create_image(new_image_params, user) do
      {:ok, image} ->
        Images.Processing.queue_processing(image, user)
        {:ok, image}

      error ->
        error
    end
  end
end
