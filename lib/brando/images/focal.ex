defmodule Brando.Images.Focal do
  @moduledoc """
  Focal struct
  """

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder, only: [:x, :y]}

  defstruct x: nil,
            y: nil
end
