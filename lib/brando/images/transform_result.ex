defmodule Brando.Images.TransformResult do
  @moduledoc """
  Struct for carrying info about an image transform's result
  """
  defstruct id: nil,
            size_key: nil,
            image_path: nil,
            cmd_params: nil,
            format: nil
end
