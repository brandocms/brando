defmodule Brando.Trait.Sequenced.Compiler do
  @moduledoc false

  @doc false
  def generate_code(_module, _config) do
    quote do
      attributes do
        attribute :sequence, :integer, default: 0
      end
    end
  end
end
