defmodule Brando.Trait.SoftDelete do
  @moduledoc """
  Adds `deleted_at`
  """
  use Brando.Trait

  attributes do
    attribute :deleted_at, :datetime
  end
end
