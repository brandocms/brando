defmodule Brando.Trait.Timestamped.Compiler do
  @moduledoc false

  @doc false
  def generate_code(_module, _config) do
    quote generated: true do
      attributes do
        attribute :inserted_at, :datetime
        attribute :updated_at, :datetime
      end
    end
  end
end
