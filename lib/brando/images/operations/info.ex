defmodule Brando.Images.Operations.Info do
  @moduledoc """
  Image info operations
  """
  alias Brando.Images

  @doc """
  Get processor module from config and call function
  """
  def get_dominant_color(image_path) do
    module = Brando.config(Images)[:processor_module] || Images.Processor.Sharp
    apply(module, :get_dominant_color, [image_path])
  end
end
