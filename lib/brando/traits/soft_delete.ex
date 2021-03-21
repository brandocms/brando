defmodule Brando.Traits.SoftDelete do
  @moduledoc """
  Adds `deleted_at`
  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()

  attributes do
    attribute :deleted_at, :datetime
  end
end
