defmodule Brando.Images.Processor.Dummy do
  @moduledoc """
  Dummy processing
  """
  alias Brando.Images

  @behaviour Brando.Images.Processor

  @doc """
  Wrapper for System.cmd
  """
  def command(_cmd, _params, _opts), do: nil

  @doc """
  Process image conversion
  """
  def process_image(%Images.ConversionParameters{
        image_id: image_id,
        size_key: size_key,
        format: format,
        image_dest_rel_path: image_dest_rel_path
      }) do
    {:ok,
     %Images.TransformResult{
       image_id: image_id,
       size_key: size_key,
       image_path: image_dest_rel_path,
       format: format,
       cmd_params: ""
     }}
  end

  def get_dominant_color(_), do: nil

  def confirm_executable_exists do
    {:ok, {:executable, :exists}}
  end
end
