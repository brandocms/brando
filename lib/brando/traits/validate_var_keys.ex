defmodule Brando.Trait.ValidateVarKeys do
  @moduledoc """
  Validates that var keys in HEEx modules don't collide with reserved assigns.
  """
  use Brando.Trait

  def changeset_mutator(_, _, changeset, _, _) do
    Brando.Content.Module.validate_var_keys(changeset)
  end
end
