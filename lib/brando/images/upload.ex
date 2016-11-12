defmodule Brando.Images.Upload do
  @moduledoc """
  Processing function for image uploads.
  """

  import Brando.Images.Utils, only: [create_image_sizes: 1]

  def create_image_struct(upload) do
    create_image_sizes(upload)
  end
end
