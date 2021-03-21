defmodule Brando.Traits.Status do
  @moduledoc """
  Adds `deleted_at`
  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()

  def fields do
    # field :status, Brando.Type.Status
  end
end
