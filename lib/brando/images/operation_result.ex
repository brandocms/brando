defmodule Brando.Images.OperationResult do
  @moduledoc """
  Struct for carrying info about an image transform's result
  """
  defstruct image_id: nil,
            sizes: nil,
            formats: nil
end
