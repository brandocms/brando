defmodule Brando.Trait.SoftDelete.Compiler do
  @moduledoc false

  @doc false
  def generate_code(_module, _config) do
    quote do
      attributes do
        attribute :deleted_at, :datetime
      end
    end
  end
end
