defmodule Brando.Images.Crop do
  @moduledoc """
  Handles saving cropped/edited images from the Image Editor.
  """

  alias Brando.Images
  alias Brando.Tenant.Storage

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
    new_path = Brando.Utils.unique_filename(original_image.path)
    {width, height} = write_and_measure(new_path, binary_data, {nil, nil})

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

  @doc """
  Replace an existing image's original file with cropped binary data.

  Overwrites the file at the image's current path, updates dimensions,
  clears processed sizes, sets focal point, and queues reprocessing.

  ## Examples

      iex> save_replace(image, binary_data, %{x: 50, y: 50}, user)
      {:ok, %Brando.Images.Image{}}
  """
  def save_replace(image, binary_data, focal, user) do
    {width, height} = write_and_measure(image.path, binary_data, {image.width, image.height})

    update_params = %{
      width: width,
      height: height,
      focal: focal,
      status: :unprocessed,
      sizes: %{},
      formats: []
    }

    changeset =
      image
      |> Brando.Images.Image.changeset(update_params, user)
      |> Map.put(:action, :update)

    case Brando.Repo.update(changeset) do
      {:ok, updated_image} ->
        Images.Processing.queue_processing(updated_image, user)
        {:ok, updated_image}

      error ->
        error
    end
  end

  defp write_and_measure(path, binary_data, fallback_dimensions) do
    media_path = Storage.current_media_root()
    dest_file = Path.join(media_path, path)

    File.mkdir_p!(Path.dirname(dest_file))
    File.write!(dest_file, binary_data)

    # Use Image.from_binary instead of Image.open(path) to bypass the libvips
    # file cache, which returns stale dimensions when overwriting an existing file.
    case Image.from_binary(binary_data) do
      {:ok, img} ->
        {Image.width(img), Image.height(img)}

      {:error, _reason} ->
        fallback_dimensions
    end
  end
end
