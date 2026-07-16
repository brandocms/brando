defmodule Brando.Trait.Timestamped do
  @moduledoc """
  Adds timestamps
  """
  use Brando.Trait

  alias Brando.Trait.Timestamped.Compiler

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)
end
