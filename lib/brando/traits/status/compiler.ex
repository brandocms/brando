defmodule Brando.Trait.Status.Compiler do
  @moduledoc false

  @doc false
  def generate_code(_module, _config) do
    quote do
      attributes do
        attribute :status, :status, required: true
      end
    end
  end
end
