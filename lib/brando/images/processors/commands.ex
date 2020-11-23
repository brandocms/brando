defmodule Brando.Images.Processor.Commands do
  @moduledoc """
  Delegates to commands, or mocks in tests
  """
  def delegate(command, params, opts) do
    module =
      Brando.config(Brando.Images)[:commands_module] ||
        (Brando.config(Brando.Images)[:processor_module] || Brando.Images.Processor.Sharp)

    apply(module, :command, [command, params, opts])
  end
end
