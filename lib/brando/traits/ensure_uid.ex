defmodule Brando.Trait.EnsureUID do
  @moduledoc """
  Ensure UID field is set by generating if not
  """
  use Brando.Trait

  import Ecto.Changeset

  # Generate the uid before `validate_required` looks for it — a schema that
  # declares `uid` required and leans on this trait to supply it would otherwise
  # fail its own validation on insert.
  @changeset_phase :before_validate_required

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    case get_field(changeset, :uid) do
      nil -> put_change(changeset, :uid, Brando.Utils.generate_uid())
      _ -> changeset
    end
  end
end
