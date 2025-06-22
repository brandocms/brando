defmodule Brando.Trait.EnsureUID do
  @moduledoc """
  Ensure UID field is set by generating if not
  """
  use Brando.Trait

  import Ecto.Changeset

  def changeset_mutator(module, _config, changeset, _user, _opts) do
    case get_field(changeset, :uid) do
      nil -> 
        new_uid = Brando.Utils.generate_uid()
        IO.puts("=== EnsureUID: Generated new UID #{new_uid} for #{inspect(module)} ===")
        put_change(changeset, :uid, new_uid)
      existing_uid -> 
        IO.puts("=== EnsureUID: Using existing UID #{existing_uid} for #{inspect(module)} ===")
        changeset
    end
  end
end
