defmodule Brando.Trait.Timestamps do
  @moduledoc """
  Adds timestamps
  """
  use Brando.Trait

  attributes do
    attribute :inserted_at, :datetime
    attribute :updated_at, :datetime
  end
end
