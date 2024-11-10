defmodule Brando.Trait.Timestamped do
  @moduledoc """
  Adds timestamps
  """
  use Brando.Trait

  def generate_code(_, _) do
    quote generated: true do
      attributes do
        attribute :inserted_at, :datetime
        attribute :updated_at, :datetime
      end
    end
  end
end
