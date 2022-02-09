defmodule Brando.Trait.EnsureUID do
  @moduledoc """
  Ensure UID field is set by generating if not
  """
  use Brando.Trait
  import Ecto.Changeset

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    case get_field(changeset, :uid) do
      nil -> put_change(changeset, :uid, Brando.Utils.generate_uid())
      _ -> changeset
    end
  end
end
