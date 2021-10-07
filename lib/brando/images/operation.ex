defmodule Brando.Images.Operation do
  @moduledoc """
  Struct for carrying info about an image transform
  """
  alias Brando.Images
  alias Brando.Type

  defstruct id: nil,
            user: nil,
            total_operations: nil,
            operation_index: nil,
            image_struct: %Images.Image{},
            filename: nil,
            type: nil,
            size_cfg: %Type.ImageConfig{},
            size_key: nil,
            sized_image_dir: nil,
            sized_image_path: nil
end
