defmodule Brando.Images.Operation do
  @moduledoc """
  Struct for carrying info about an image transform
  """
  defstruct image_id: nil,
            user_id: nil,
            total_operations: nil,
            operation_index: nil,
            processed_formats: nil,
            image_struct: nil,
            filename: nil,
            type: nil,
            size_cfg: nil,
            size_key: nil,
            sized_image_dir: nil,
            sized_image_path: nil

  @type t :: %__MODULE__{}
end
