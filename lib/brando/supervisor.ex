defmodule Brando.Supervisor do
  @moduledoc """
  Main Brando supervisor.

  Looks after `Brando.Registry`.
  """
  use Supervisor

  def start_link do
    image_processing_module =
      Brando.config(Brando.Images)[:processor_module] || Brando.Images.Processor.Mogrify

    {:ok, {:executable, :exists}} = apply(image_processing_module, :confirm_executable_exists, [])

    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    children = [
      supervisor(Brando.Registry, []),
      supervisor(Brando.Config, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
