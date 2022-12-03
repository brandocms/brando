defmodule Brando.Images.Operation do
  @moduledoc """
  Struct for carrying info about an image transform
  """
  defstruct image_id: nil,
            user: nil,
            total_operations: nil,
            operation_index: nil,
            processed_formats: nil,
            image_struct: %Brando.Images.Image{},
            filename: nil,
            type: nil,
            size_cfg: %Brando.Type.ImageConfig{},
            size_key: nil,
            sized_image_dir: nil,
            sized_image_path: nil
end
