defmodule Brando.Trait.Blocks do
  @moduledoc """
  Blocks
  Only used to register the trait.
  """
  use Brando.Trait

  @impl true
  def validate(_module, _config) do
    true
  end
end
