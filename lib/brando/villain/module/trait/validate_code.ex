defmodule Brando.Villain.Module.Trait.ValidateCode do
  @moduledoc """
  Ensures that all referenced refs in code exists
  """
  use Brando.Trait
  # import Ecto.Changeset

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    # TODO: extract `%{<refs>}` from `code` and ensure they exist in `refs`
    changeset
  end
end
