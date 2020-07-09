defmodule Brando.Images.Focal do
  @moduledoc """
  Focal struct
  """

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder, only: [:x, :y]}

  defstruct x: 50,
            y: 50
end
