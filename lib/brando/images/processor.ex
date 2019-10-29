defmodule Brando.Images.Processor do
  @moduledoc """
  Processor behaviour for image processing.
  """
  alias Brando.Images

  @type conversion_parameters :: Images.TransformResult.t()
  @type operation_result :: Images.OperationResult.t()

  @doc "Processes image"
  @callback process_image(conversion_parameters :: conversion_parameters) ::
              {:ok, operation_result}

  @doc "Check filesystem for executable needed for processing"
  @callback confirm_executable_exists() ::
              {:ok, {:executable, :exists}}
              | {:error, {:executable, :missing}}
end
