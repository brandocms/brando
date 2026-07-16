defmodule Brando.Trait.Translatable do
  @moduledoc "Adds language metadata and optional alternate-entry relationships."
  use Brando.Trait

  alias Brando.Trait.Translatable.Compiler

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)
end
