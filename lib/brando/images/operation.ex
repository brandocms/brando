defmodule Brando.Images.Operation do
  @moduledoc """
  Struct for carrying info about an image transform
  """
  alias Brando.Type

  defstruct id: nil,
            user: nil,
            img_struct: %Type.Image{},
            filename: nil,
            type: nil,
            size_cfg: %Type.ImageConfig{},
            size_key: nil,
            sized_img_dir: nil,
            sized_img_path: nil

end
