defmodule Brando.Images.Processor do
  @moduledoc """
  Processor behaviour for image processing.
  """
  alias Brando.Images

  @type conversion_parameters :: Images.TransformResult.t()
  @type operation_result :: Images.OperationResult.t()
  @type executable_result :: {:ok, {:executable, :exists}} | {:error, {:executable, :missing}}

  @doc "Processes image"
  @callback process_image(conversion_parameters) :: {:ok, operation_result}

  @doc "Check image for dominant color"
  @callback get_dominant_color(image_path :: binary) :: binary() | nil

  @doc "Check filesystem for executable needed for processing"
  @callback confirm_executable_exists() :: executable_result
end
